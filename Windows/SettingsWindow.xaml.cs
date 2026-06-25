using System.Windows;

namespace WFHTimer
{
    public partial class SettingsWindow : Window
    {
        public AppSettings CurrentSettings { get; private set; }

        public SettingsWindow(AppSettings settings)
        {
            InitializeComponent();
            CurrentSettings = settings;
            WorkBox.Text = settings.WorkDuration.ToString();
            BreakBox.Text = settings.BreakDuration.ToString();
        }

        private void Save_Click(object sender, RoutedEventArgs e)
        {
            if (int.TryParse(WorkBox.Text, out int w) && w > 0) CurrentSettings.WorkDuration = w;
            if (int.TryParse(BreakBox.Text, out int b) && b > 0) CurrentSettings.BreakDuration = b;
            DialogResult = true;
            Close();
        }

        private void Cancel_Click(object sender, RoutedEventArgs e)
        {
            DialogResult = false;
            Close();
        }
    }
}
