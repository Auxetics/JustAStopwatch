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
using System.Windows.Media;
using Microsoft.Toolkit.Uwp.Notifications;

namespace JustAStopwatch
{
    public class AppSettings
    {
        public int WorkDuration { get; set; } = 25;
        public int BreakDuration { get; set; } = 5;
    }

    public enum AppMode { Stopwatch, Pomodoro }
    public enum PomodoroSession { Work, Break }

    public partial class MainWindow : Window
    {
        private DispatcherTimer _timer;
        private DispatcherTimer _positionTimer;
        private DateTime _startTime;
        private TimeSpan _elapsedTime = TimeSpan.Zero;
        private bool _isRunning = false;
        
        private AppMode _mode = AppMode.Stopwatch;
        private PomodoroSession _pomodoroSession = PomodoroSession.Work;
        private TimeSpan _pomodoroRemaining = TimeSpan.Zero;
        
        private AppSettings _settings;
        private string _settingsPath;
        
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
            
            _settingsPath = Path.Combine(appDataPath, "settings.json");
            LoadSettings();
            
            _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
            _timer.Tick += Timer_Tick;
            
            _positionTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
            _positionTimer.Tick += PositionTimer_Tick;
            
            CheckStartupStatus();
            CheckForUpdates();
            UpdateUI();
        }

        private void LoadSettings()
        {
            if (File.Exists(_settingsPath))
            {
                try { _settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(_settingsPath)) ?? new AppSettings(); }
                catch { _settings = new AppSettings(); }
            }
            else
            {
                _settings = new AppSettings();
            }
        }

        private void SaveSettings()
        {
            File.WriteAllText(_settingsPath, JsonSerializer.Serialize(_settings));
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            _positionTimer.Start();
            UpdatePosition();
        }

        private void Timer_Tick(object? sender, EventArgs e)
        {
            if (_mode == AppMode.Stopwatch)
            {
                var totalElapsed = _elapsedTime + (DateTime.Now - _startTime);
                TimeText.Text = FormatTime(totalElapsed);
            }
            else
            {
                var remaining = _pomodoroRemaining - (DateTime.Now - _startTime);
                if (remaining.TotalSeconds <= 0)
                {
                    HandlePomodoroEnd();
                    return;
                }
                TimeText.Text = FormatTime(remaining);
            }
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
                ResetTimer();
            }
            else
            {
                if (_isRunning) PauseTimer();
                else StartTimer();
            }
        }
        
        private void StartTimer()
        {
            if (_isRunning) return;
            _isRunning = true;
            _startTime = DateTime.Now;
            
            if (_mode == AppMode.Pomodoro && _pomodoroRemaining.TotalSeconds <= 0)
            {
                _pomodoroRemaining = TimeSpan.FromMinutes(_settings.WorkDuration);
                _pomodoroSession = PomodoroSession.Work;
                TimeText.Text = FormatTime(_pomodoroRemaining);
            }
            
            _timer.Start();
            UpdateUI();
        }
        
        private void PauseTimer()
        {
            if (!_isRunning) return;
            _isRunning = false;
            _timer.Stop();
            
            if (_mode == AppMode.Stopwatch)
            {
                _elapsedTime += DateTime.Now - _startTime;
            }
            else
            {
                _pomodoroRemaining -= DateTime.Now - _startTime;
            }
            UpdateUI();
        }
        
        private void ResetTimer()
        {
            _isRunning = false;
            _timer.Stop();
            
            if (_mode == AppMode.Stopwatch)
            {
                _elapsedTime = TimeSpan.Zero;
                TimeText.Text = "00:00";
            }
            else
            {
                _pomodoroRemaining = TimeSpan.FromMinutes(_settings.WorkDuration);
                _pomodoroSession = PomodoroSession.Work;
                TimeText.Text = FormatTime(_pomodoroRemaining);
            }
            UpdateUI();
        }

        private void HandlePomodoroEnd()
        {
            _isRunning = false;
            _timer.Stop();
            
            if (_pomodoroSession == PomodoroSession.Work)
            {
                _pomodoroSession = PomodoroSession.Break;
                _pomodoroRemaining = TimeSpan.FromMinutes(_settings.BreakDuration);
                new ToastContentBuilder()
                    .AddText("Work Session Complete!")
                    .AddText("Time for a break.")
                    .Show();
            }
            else
            {
                _pomodoroSession = PomodoroSession.Work;
                _pomodoroRemaining = TimeSpan.FromMinutes(_settings.WorkDuration);
                new ToastContentBuilder()
                    .AddText("Break Over!")
                    .AddText("Back to work.")
                    .Show();
            }
            
            // Auto start next phase
            _startTime = DateTime.Now;
            _timer.Start();
            _isRunning = true;
            UpdateUI();
        }

        private void UpdateUI()
        {
            bool hasStartedStopwatch = _mode == AppMode.Stopwatch && (_elapsedTime.TotalSeconds > 0 || _isRunning);
            bool hasStartedPomodoro = _mode == AppMode.Pomodoro && (_pomodoroRemaining < TimeSpan.FromMinutes(_settings.WorkDuration) || _isRunning);
            
            StatusDot.Visibility = (hasStartedStopwatch || hasStartedPomodoro) ? Visibility.Visible : Visibility.Collapsed;
            StatusDot.Fill = _isRunning ? Brushes.LimeGreen : Brushes.Orange;
            TimeText.Foreground = (_mode == AppMode.Pomodoro && _pomodoroSession == PomodoroSession.Break) ? Brushes.Orange : Brushes.White;
        }

        private void MenuMode_Click(object sender, RoutedEventArgs e)
        {
            PauseTimer();
            _mode = _mode == AppMode.Stopwatch ? AppMode.Pomodoro : AppMode.Stopwatch;
            MenuMode.Header = _mode == AppMode.Stopwatch ? "Switch to Pomodoro Mode" : "Switch to Stopwatch Mode";
            ResetTimer();
        }

        private void MenuSettings_Click(object sender, RoutedEventArgs e)
        {
            _positionTimer.Stop();
            var settingsWindow = new SettingsWindow(_settings) { Owner = this };
            bool? result = settingsWindow.ShowDialog();
            _positionTimer.Start();
            
            if (result == true)
            {
                SaveSettings();
                if (_mode == AppMode.Pomodoro && !_isRunning)
                {
                    ResetTimer();
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
                        var source = PresentationSource.FromVisual(this);
                        double scaleX = source?.CompositionTarget?.TransformToDevice.M11 ?? 1.0;
                        double scaleY = source?.CompositionTarget?.TransformToDevice.M22 ?? 1.0;

                        double logicalLeft = rect.Left / scaleX;
                        double logicalTop = rect.Top / scaleY;

                        this.Left = logicalLeft - this.Width - 10;
                        this.Top = logicalTop + ((rect.Bottom - rect.Top) / scaleY - this.Height) / 2.0;
                        return;
                    }
                }
            }
            
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
                if (hwnd != IntPtr.Zero) SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);
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
                if (MenuStartup.IsChecked) key.SetValue("JustAStopwatch", path);
                else key.DeleteValue("JustAStopwatch", false);
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
            Process.Start(new ProcessStartInfo { FileName = "https://ko-fi.com/auxetics", UseShellExecute = true });
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
                                    Dispatcher.Invoke(() => MenuUpdate.Header = "Update Now!");
                                    break;
                                }
                            }
                        }
                        else
                        {
                            Dispatcher.Invoke(() => MenuUpdate.Header = $"Up to Date (v{AppVersion})");
                        }
                    }
                }
            }
            catch { }
        }

        private async void MenuUpdate_Click(object sender, RoutedEventArgs e)
        {
            bool hasTime = _mode == AppMode.Stopwatch ? _elapsedTime.TotalSeconds > 0 : _pomodoroRemaining < TimeSpan.FromMinutes(_settings.WorkDuration);
            if (_isRunning || hasTime)
            {
                MessageBox.Show("Please reset the timer before applying an update to prevent losing your tracked time.", "Cannot Update", MessageBoxButton.OK, MessageBoxImage.Warning);
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

                Process.Start(new ProcessStartInfo { FileName = batchScript, WindowStyle = ProcessWindowStyle.Hidden, CreateNoWindow = true });
                Application.Current.Shutdown();
            }
            catch
            {
                MenuUpdate.Header = "Update Failed";
                MenuUpdate.IsEnabled = true;
            }
        }

        private class GitHubRelease { public string tag_name { get; set; } = ""; public GitHubAsset[] assets { get; set; } = Array.Empty<GitHubAsset>(); }
        private class GitHubAsset { public string name { get; set; } = ""; public string browser_download_url { get; set; } = ""; }
    }
}
