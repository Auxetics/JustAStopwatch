using System;
using System.Diagnostics;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;
using Microsoft.Win32;
using System.IO;
using System.Reflection;
using System.Windows.Interop;

namespace JustAStopwatch
{
    public partial class MainWindow : Window
    {
        private DispatcherTimer _timer;
        private DispatcherTimer _positionTimer;
        private DateTime _startTime;
        private TimeSpan _elapsedTime = TimeSpan.Zero;
        private bool _isRunning = false;
        
        private readonly string AppVersion = Assembly.GetExecutingAssembly().GetName().Version?.ToString(2) ?? "1.0";
        private string _downloadUrl = "";
        
        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr FindWindow(string lpClassName, string? lpWindowName);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr FindWindowEx(IntPtr hwndParent, IntPtr hwndChildAfter, string lpszClass, string? lpszWindow);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
        private static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        public MainWindow()
        {
            string appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "JustAStopwatch");
            string installedExe = Path.Combine(appDataPath, "JustAStopwatch.exe");
            string currentExe = Environment.ProcessPath!;

            if (!currentExe.Equals(installedExe, StringComparison.OrdinalIgnoreCase))
            {
                try
                {
                    Directory.CreateDirectory(appDataPath);
                    File.Copy(currentExe, installedExe, true);
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = installedExe,
                        UseShellExecute = true
                    });
                    Application.Current.Shutdown();
                    return;
                }
                catch
                {
                    // Fail silently and run from current location
                }
            }

            InitializeComponent();
            
            _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
            _timer.Tick += Timer_Tick;
            
            _positionTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
            _positionTimer.Tick += PositionTimer_Tick;
            
            CheckStartupStatus();
            CheckForUpdates();
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            _positionTimer.Start();
            UpdatePosition();
        }

        private void Timer_Tick(object? sender, EventArgs e)
        {
            var totalElapsed = _elapsedTime + (DateTime.Now - _startTime);
            TimeText.Text = FormatTime(totalElapsed);
        }

        private string FormatTime(TimeSpan time)
        {
            if (time.TotalHours >= 1)
                return $"{(int)time.TotalHours:00}:{time.Minutes:00}:{time.Seconds:00}";
            return $"{time.Minutes:00}:{time.Seconds:00}";
        }

        private void Grid_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ClickCount == 2)
            {
                _isRunning = false;
                _timer.Stop();
                _elapsedTime = TimeSpan.Zero;
                TimeText.Text = "00:00";
            }
            else
            {
                if (_isRunning)
                {
                    _timer.Stop();
                    _elapsedTime += DateTime.Now - _startTime;
                    _isRunning = false;
                }
                else
                {
                    _startTime = DateTime.Now;
                    _timer.Start();
                    _isRunning = true;
                }
            }
        }

        private void UpdatePosition()
        {
            IntPtr trayWnd = FindWindow("Shell_TrayWnd", null);
            if (trayWnd != IntPtr.Zero)
            {
                IntPtr notifyWnd = FindWindowEx(trayWnd, IntPtr.Zero, "TrayNotifyWnd", null);
                if (notifyWnd != IntPtr.Zero)
                {
                    if (GetWindowRect(notifyWnd, out RECT rect))
                    {
                        var primaryMonitorWidth = SystemParameters.PrimaryScreenWidth;
                        var primaryMonitorHeight = SystemParameters.PrimaryScreenHeight;
                        
                        // Convert physical rect to logical units
                        var source = PresentationSource.FromVisual(this);
                        double scaleX = source?.CompositionTarget?.TransformToDevice.M11 ?? 1.0;
                        double scaleY = source?.CompositionTarget?.TransformToDevice.M22 ?? 1.0;

                        double logicalLeft = rect.Left / scaleX;
                        double logicalTop = rect.Top / scaleY;

                        this.Left = logicalLeft - this.Width - 10; // 10px padding
                        this.Top = logicalTop + ((rect.Bottom - rect.Top) / scaleY - this.Height) / 2.0;
                        return;
                    }
                }
            }
            
            // Fallback
            var workArea = SystemParameters.WorkArea;
            this.Left = workArea.Right - this.Width - 10;
            this.Top = workArea.Bottom - this.Height - 10;
        }

        private void PositionTimer_Tick(object? sender, EventArgs e)
        {
            UpdatePosition();
            
            try
            {
                var hwnd = new WindowInteropHelper(this).Handle;
                if (hwnd != IntPtr.Zero)
                {
                    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
                }
            }
            catch { }
        }

        private void MenuStartup_Click(object sender, RoutedEventArgs e)
        {
            string runKey = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run";
            string appDataPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "JustAStopwatch");
            string installedExe = Path.Combine(appDataPath, "JustAStopwatch.exe");
            string path = File.Exists(installedExe) ? installedExe : Environment.ProcessPath!;

            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(runKey, true)!)
            {
                if (MenuStartup.IsChecked)
                {
                    key.SetValue("JustAStopwatch", path);
                }
                else
                {
                    key.DeleteValue("JustAStopwatch", false);
                }
            }
        }

        private void CheckStartupStatus()
        {
            string runKey = "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Run";
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(runKey, false)!)
            {
                MenuStartup.IsChecked = key.GetValue("JustAStopwatch") != null;
            }
        }

        private void MenuDonate_Click(object sender, RoutedEventArgs e)
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "https://ko-fi.com/auxetics",
                UseShellExecute = true
            });
        }

        private void MenuQuit_Click(object sender, RoutedEventArgs e)
        {
            Application.Current.Shutdown();
        }

        private async void CheckForUpdates()
        {
            try
            {
                using var client = new HttpClient();
                client.DefaultRequestHeaders.Add("User-Agent", "JustAStopwatch-Updater");
                var response = await client.GetStringAsync("https://api.github.com/repos/Auxetics/JustAStopwatch/releases/latest");
                var release = JsonSerializer.Deserialize<GitHubRelease>(response);

                if (release != null && release.tag_name != null)
                {
                    string latestVersion = release.tag_name.Replace("v", "");
                    if (Version.TryParse(latestVersion, out Version? latest) && Version.TryParse(AppVersion, out Version? current))
                    {
                        if (latest > current)
                        {
                            foreach (var asset in release.assets)
                            {
                                if (asset.name.EndsWith(".exe"))
                                {
                                    _downloadUrl = asset.browser_download_url;
                                    Dispatcher.Invoke(() =>
                                    {
                                        MenuUpdate.Header = "Update Now!";
                                    });
                                    break;
                                }
                            }
                        }
                        else
                        {
                            Dispatcher.Invoke(() =>
                            {
                                MenuUpdate.Header = $"Up to Date (v{AppVersion})";
                            });
                        }
                    }
                }
            }
            catch
            {
                // Ignore network errors silently
            }
        }

        private async void MenuUpdate_Click(object sender, RoutedEventArgs e)
        {
            if (_isRunning || _elapsedTime.TotalSeconds > 0)
            {
                MessageBox.Show("Please reset the stopwatch to 00:00 before applying an update to prevent losing your tracked time.", "Cannot Update", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            if (string.IsNullOrEmpty(_downloadUrl))
            {
                CheckForUpdates();
                return;
            }

            MenuUpdate.Header = "Downloading...";
            MenuUpdate.IsEnabled = false;

            try
            {
                using var client = new HttpClient();
                var exeBytes = await client.GetByteArrayAsync(_downloadUrl);
                
                string tempExe = Path.Combine(Path.GetTempPath(), "JustAStopwatch_Update.exe");
                await File.WriteAllBytesAsync(tempExe, exeBytes);

                string currentExe = Environment.ProcessPath!;
                string batchScript = Path.Combine(Path.GetTempPath(), "update_justastopwatch.bat");
                
                string scriptContent = $@"
@echo off
timeout /t 2 /nobreak > nul
del ""{currentExe}""
move /y ""{tempExe}"" ""{currentExe}""
start """" ""{currentExe}""
del ""%~f0""
";
                File.WriteAllText(batchScript, scriptContent);

                Process.Start(new ProcessStartInfo
                {
                    FileName = batchScript,
                    WindowStyle = ProcessWindowStyle.Hidden,
                    CreateNoWindow = true
                });

                Application.Current.Shutdown();
            }
            catch
            {
                MenuUpdate.Header = "Update Failed";
                MenuUpdate.IsEnabled = true;
            }
        }

        private class GitHubRelease
        {
            public string tag_name { get; set; } = "";
            public GitHubAsset[] assets { get; set; } = Array.Empty<GitHubAsset>();
        }

        private class GitHubAsset
        {
            public string name { get; set; } = "";
            public string browser_download_url { get; set; } = "";
        }
    }
}
