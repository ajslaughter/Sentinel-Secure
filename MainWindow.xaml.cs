using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ModernWpf.Controls;

namespace SentinelField
{
    public partial class MainWindow : Window, INotifyPropertyChanged
    {
        public ObservableCollection<CheckResult> SecurityChecks { get; set; } = new ObservableCollection<CheckResult>();
        public ObservableCollection<SecurityEngine.NetworkConnection> NetworkConnections { get; set; } = new ObservableCollection<SecurityEngine.NetworkConnection>();
        public ObservableCollection<AuditLogEntry> AuditLogs => AuditLogger.Logs;

        public SecurityEngine.SystemInfo SysInfo { get; set; }

        private double _hardeningScore;
        public double HardeningScore
        {
            get => _hardeningScore;
            set { _hardeningScore = value; OnPropertyChanged(nameof(HardeningScore)); OnPropertyChanged(nameof(HardeningScoreDisplay)); }
        }

        public string HardeningScoreDisplay => $"{HardeningScore}%";

        public MainWindow()
        {
            InitializeComponent();
            DataContext = this;
            
            // Initial data load
            RefreshDashboard();
            LoadAuditLogs(); // Bind logs
            
            NavView.SelectedItem = NavView.MenuItems[0]; // Select Dashboard by default
        }

        private void LoadAuditLogs()
        {
            // Already bound via property
        }

        private async void RefreshDashboard_Click(object sender, RoutedEventArgs e)
        {
            await Task.Run(() => RefreshDashboard());
        }

        private void RefreshDashboard()
        {
            Application.Current.Dispatcher.Invoke(() => {
                SysInfo = SecurityEngine.GetSystemInfo();
                OnPropertyChanged(nameof(SysInfo));
                
                // Checks
                SecurityChecks.Clear();
                AddCheck("RDP Status", SecurityEngine.CheckRDPStatus(), "RDP Disabled", "RDP Enabled (Unsafe)");
                AddCheck("SMBv1", SecurityEngine.CheckSMBv1(), "SMBv1 Disabled", "SMBv1 Enabled (Unsafe)");
                AddCheck("Guest Account", SecurityEngine.CheckGuestAccount(), "Disabled", "Enabled (Unsafe)");
                AddCheck("LSA Protection", SecurityEngine.CheckLSAProtection(), "Enabled", "Disabled (Unsafe)");
                AddCheck("Auto Logon", SecurityEngine.CheckAutoLogon(), "Disabled", "Enabled (Unsafe)");
                AddCheck("Credential Guard", SecurityEngine.CheckCredentialGuard(), "Enabled", "Disabled/Unknown");
                
                // Score
                HardeningScore = SecurityEngine.CalculateHardeningScore();
            });
        }

        private void AddCheck(string name, bool passed, string successMsg, string failMsg)
        {
            SecurityChecks.Add(new CheckResult
            {
                Name = name,
                Status = passed ? successMsg : failMsg,
                Result = passed ? "PASS" : "FAIL",
                ResultColor = passed ? (SolidColorBrush)FindResource("SafeBrush") : (SolidColorBrush)FindResource("WarningBrush")
            });
        }

        // Navigation Logic
        private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
        {
            if (args.SelectedItem is NavigationViewItem item)
            {
                DashboardGrid.Visibility = Visibility.Collapsed;
                HardeningGrid.Visibility = Visibility.Collapsed;
                NetworkGrid.Visibility = Visibility.Collapsed;
                ResolutionGrid.Visibility = Visibility.Collapsed;

                switch (item.Tag.ToString())
                {
                    case "Dashboard":
                        DashboardGrid.Visibility = Visibility.Visible;
                        break;
                    case "Hardening":
                        HardeningGrid.Visibility = Visibility.Visible;
                        break;
                    case "Network":
                        NetworkGrid.Visibility = Visibility.Visible;
                        RefreshNetwork_Click(null, null);
                        break;
                    case "Resolution":
                        ResolutionGrid.Visibility = Visibility.Visible;
                        break;
                }
            }
        }

        // Hardening Logic
        private async void ApplyHardening_Click(object sender, RoutedEventArgs e)
        {
            var result = MessageBox.Show("This will apply all security baselines (Disable RDP, SMBv1, Guest, Enable LSA). Continue?", "Confirm Hardening", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (result == MessageBoxResult.Yes)
            {
                await Task.Run(() => {
                    SecurityEngine.ApplyHardeningBaseline();
                    RefreshDashboard();
                });
                MessageBox.Show("Hardening complete.", "Success", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        // Network Logic
        private async void RefreshNetwork_Click(object sender, RoutedEventArgs e)
        {
            await Task.Run(() => {
                var conns = SecurityEngine.GetNetworkConnections();
                Application.Current.Dispatcher.Invoke(() => {
                    NetworkConnections.Clear();
                    bool hideLoopback = HideLoopbackCheck.IsChecked ?? true;
                    
                    foreach (var c in conns)
                    {
                        if (hideLoopback && (c.LocalAddress.StartsWith("127.0") || c.LocalAddress == "0.0.0.0" || c.LocalAddress == "::1"))
                            continue;
                        
                        NetworkConnections.Add(c);
                    }
                    ConnectionsGrid.ItemsSource = NetworkConnections;
                });
            });
        }

         // Resolution Logic
        private void FixDisplay_Click(object sender, RoutedEventArgs e)
        {
            if (MessageBox.Show("This will clear display cache. Your screen may flicker. Continue?", "Confirm", MessageBoxButton.YesNo) == MessageBoxResult.Yes)
            {
                SecurityEngine.FixDisplayResolution();
                MessageBox.Show("Display cache cleared. Please restart your system.", "Done", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }

        // INotifyPropertyChanged Implementation
        public event PropertyChangedEventHandler PropertyChanged;
        protected void OnPropertyChanged(string name)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
        }
    }

    public class CheckResult
    {
        public string Name { get; set; }
        public string Status { get; set; }
        public string Result { get; set; }
        public SolidColorBrush ResultColor { get; set; }
    }
}
