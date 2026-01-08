using System;
using System.Collections.ObjectModel;
using System.Windows.Data;

namespace SentinelField
{
    public class AuditLogEntry
    {
        public string Timestamp { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
        public string Type { get; set; } = "INFO"; // INFO, WARN, ERROR, SUCCESS
    }

    public static class AuditLogger
    {
        private static readonly object _lock = new object();
        public static ObservableCollection<AuditLogEntry> Logs { get; } = new ObservableCollection<AuditLogEntry>();

        static AuditLogger()
        {
            // Enable collection synchronization for cross-thread access
            BindingOperations.EnableCollectionSynchronization(Logs, _lock);
        }

        public static void Log(string message, string type = "INFO")
        {
            lock (_lock)
            {
                Logs.Add(new AuditLogEntry
                {
                    Timestamp = DateTime.Now.ToString("HH:mm:ss"),
                    Message = message,
                    Type = type
                });
            }
        }
    }
}
