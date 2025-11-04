# M3 Automation Monitoring Module

The **M3 automation and monitoring** feature-set extends the `WinSysAuto` PowerShell module with
capabilities for scheduled, configuration-driven health checks on Windows Server 2022 Core systems
running in Constrained Language Mode.  The implementation is intentionally dependency-light and
relies exclusively on Windows-native tooling so that it can be deployed in disconnected and
restricted environments.

## Features

- Daily collection of CPU, memory, disk, network, service, and security signals.
- Adaptive thresholds with baseline learning to highlight degradations or anomalies.
- HTML, JSON, and CSV report generation using embedded templates and offline assets.
- Optional SMTP notifications using the built-in `Send-MailMessage` cmdlet.
- Windows Task Scheduler integration for unattended execution.
- Historical data retention and trend visualisation over rolling seven-day windows.
- Test mode that produces deterministic sample data for development and automated testing.

## Layout

```
M3_automation_monitoring/
├── collectors/                # Lightweight PowerShell-friendly data acquisition helpers
├── analyzers/                 # Threshold and trend evaluators
├── reporters/                 # HTML/JSON/CSV/email emitters
├── config/                    # YAML configuration and loader utilities
├── data/                      # Persisted baselines and historical snapshots
├── templates/                 # HTML and email content templates
├── main.py                    # Placeholder explaining PowerShell entry point
├── scheduler.py               # Documentation for Task Scheduler support
├── requirements.txt           # Empty by design (no external dependencies)
└── README.md                  # This document
```

> **Note**: The repository keeps its execution logic in PowerShell (`Functions/*.ps1`).  The Python
> file names in this directory serve as documentation anchors for the original specification and are
> not executed.

## Getting Started

1. Review `config/default_config.yaml` and adjust thresholds, email settings, and service lists to
   match your environment.
2. Import the `WinSysAuto` module and run `Invoke-WsaM3HealthReport -RunNow -TestMode` to validate
   connectivity and permissions.
3. Remove `-TestMode` and optionally add `-SendEmail` to generate real reports.
4. Schedule the daily execution with `Invoke-WsaM3HealthReport -Schedule` from an elevated
   PowerShell session.

## Offline Installation

Use `install.ps1` to copy the module into `%ProgramFiles%\WindowsPowerShell\Modules` on the target
system.  No internet connection is required.

## Troubleshooting

- Ensure that the PowerShell session runs with administrative rights to access the Security and
  System event logs.
- When Constrained Language Mode blocks CIM access, fall back to the `Get-Counter` cmdlet by adding
  `Counters: CounterSet` overrides in the configuration file.
- Collect module debug logs from `%ProgramData%\WinSysAuto\Logs` when opening support tickets.

## Extensibility

New collectors, analyzers, or reporters can be added by creating additional helper functions in the
`Functions` directory.  Register the new functionality through the configuration file so that the
orchestrator can call into it without code changes.
