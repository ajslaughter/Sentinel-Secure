# WinSysAuto

**Production-ready automation toolkit for Windows Server environments**

WinSysAuto is a PowerShell 5.1+ automation module designed to work on **ANY** Windows domain environment. It provides essential tools for system health monitoring, user management, configuration backup, and security hardening—all with zero configuration required.

## Key Features

- **Environment Auto-Detection**: Automatically detects your domain, servers, and network configuration
- **Works Anywhere**: Domain controllers, member servers, and workstations
- **Graceful Degradation**: Functions work even when optional modules are unavailable
- **Live Dashboard**: Futuristic cyberpunk-style real-time monitoring interface
- **Zero Hardcoding**: No lab-specific references or hardcoded values
- **Production Ready**: Robust error handling and comprehensive logging

## Supported Environments

- Windows Server 2019, 2022 (and newer)
- Windows 10/11 with RSAT tools
- PowerShell 5.1 and PowerShell 7+
- Single and multi-domain forests
- Works on DCs, member servers, and standalone systems

## Quick Start

### Installation

```powershell
# Clone the repository
git clone https://github.com/ajslaughter/WinSysAuto.git
cd WinSysAuto

# Install for current user (no admin required)
.\install.ps1

# OR install system-wide (requires admin)
.\install.ps1 -Scope AllUsers
```

### First Run

```powershell
# Auto-detect your environment
Initialize-WsaEnvironment

# Launch the live dashboard
Start-WsaDashboard
```

That's it! Navigate to http://localhost:8080 in your browser to see the dashboard.

## Core Functions

WinSysAuto provides 6 essential functions:

### 1. Initialize-WsaEnvironment
Auto-detects and configures WinSysAuto for your environment.

```powershell
Initialize-WsaEnvironment
```

**Detects:**
- Current domain and forest
- Domain controllers
- DHCP and DNS servers
- Network configuration
- Available PowerShell modules

**Creates:**
- Configuration file at `$env:ProgramData\WinSysAuto\config.json`
- Directory structure for reports, backups, and logs

### 2. Start-WsaDashboard
Launches a real-time monitoring dashboard with cyberpunk aesthetics.

```powershell
# Default port 8080
Start-WsaDashboard

# Custom port
Start-WsaDashboard -Port 9090
```

**Features:**
- Real-time CPU, memory, and disk monitoring
- Service health tracking
- Security event monitoring
- Auto-refresh every 30 seconds
- JSON API at `/api/health`

**Dashboard Screenshot:**
- Futuristic cyberpunk UI with neon accents
- Hexagonal health score indicator
- Animated progress bars
- Color-coded status (green/yellow/red)
- Glass-morphism design

### 3. Get-WsaHealth
Comprehensive health check and reporting.

```powershell
Get-WsaHealth -Verbose
```

**Collects:**
- Active Directory domain info
- DNS forwarder configuration
- DHCP scope details
- Group Policy inventory
- File share enumeration
- Disk usage statistics
- Event log warnings/errors (last 24h)

**Outputs:**
- Summary report (TXT)
- Detailed CSV files
- Saved to `$env:ProgramData\WinSysAuto\Reports\Health-<timestamp>`

### 4. New-WsaUsersFromCsv
Bulk user creation from CSV with intelligent defaults.

```powershell
# Basic import
New-WsaUsersFromCsv -Path .\users.csv

# With auto-group creation
New-WsaUsersFromCsv -Path .\users.csv -AutoCreateGroups

# With custom default OU
New-WsaUsersFromCsv -Path .\users.csv -DefaultOU "OU=Employees,DC=contoso,DC=com"
```

**CSV Format:**
```csv
GivenName,Surname,SamAccountName,Department,OU,Password,Groups
John,Doe,jdoe,IT,,P@ssw0rd,Domain Admins;IT Support
Jane,Smith,jsmith,HR,,,HR Team
```

**Features:**
- Auto-detects domain from environment
- Creates users in specified or default OU
- Optional department-based security groups
- Handles existing users gracefully
- Optional password reset for existing users

### 5. Backup-WsaConfig
Creates comprehensive backup archives.

```powershell
Backup-WsaConfig -Verbose
```

**Backs Up:**
- Latest health reports
- WinSysAuto configuration
- All Group Policy Objects (if available)
- DHCP scope configuration (if DHCP server)
- DNS forwarder settings (if DNS server)

**Output:**
- ZIP archive at `$env:ProgramData\WinSysAuto\Backups\WsaBackup-<timestamp>.zip`

### 6. Invoke-WsaSecurityBaseline
Applies security hardening based on JSON configuration.

```powershell
# Apply baseline
Invoke-WsaSecurityBaseline -Verbose

# Rollback changes
Invoke-WsaSecurityBaseline -Rollback -Verbose
```

**Configures:**
- Windows Defender real-time protection
- Firewall profiles (Domain/Private)
- SMBv1 protocol (disable by default)
- Time synchronization (NTP servers)

**Configuration File:**
- Located at `baselines/security.json`
- Customizable for your environment

## Configuration

WinSysAuto stores its configuration at:
```
$env:ProgramData\WinSysAuto\
├── config.json          # Environment configuration
├── Reports\             # Health reports
├── Backups\             # Backup archives
└── Logs\                # Module logs
```

### Reinitialize Environment

If your environment changes (new DCs, IP changes, etc.):

```powershell
Initialize-WsaEnvironment -Force
```

## Directory Structure

```
WinSysAuto/
├── WinSysAuto.psd1      # Module manifest
├── WinSysAuto.psm1      # Module loader
├── install.ps1          # Installation script
├── Config/              # Initialization functions
│   └── Initialize-WsaEnvironment.ps1
├── Public/              # Public functions
│   ├── Get-WsaHealth.ps1
│   ├── Start-WsaDashboard.ps1
│   ├── New-WsaUsersFromCsv.ps1
│   ├── Backup-WsaConfig.ps1
│   └── Invoke-WsaSecurityBaseline.ps1
├── Private/             # Helper functions
│   ├── Get-WsaConfig.ps1
│   ├── Write-WsaLog.ps1
│   ├── New-WsaResult.ps1
│   └── Get-WsaDashboardData.ps1
├── Dashboard/           # Dashboard HTML
│   └── dashboard.html
└── baselines/           # Security baselines
    └── security.json
```

## Requirements

**Minimum:**
- Windows Server 2019+ or Windows 10/11
- PowerShell 5.1 or newer
- No specific modules required

**Optional Modules (for full functionality):**
- ActiveDirectory (user management, domain info)
- DhcpServer (DHCP configuration)
- DnsServer (DNS configuration)
- GroupPolicy (GPO backup/inventory)

WinSysAuto gracefully handles missing modules by skipping unavailable features.

## Examples

### Complete Setup Workflow

```powershell
# 1. Install module
.\install.ps1

# 2. Initialize environment
Initialize-WsaEnvironment

# 3. Run health check
Get-WsaHealth

# 4. Create backup
Backup-WsaConfig

# 5. Launch dashboard
Start-WsaDashboard
```

### User Management Workflow

```powershell
# Create CSV file: users.csv
@"
GivenName,Surname,SamAccountName,Department,Groups
Alice,Johnson,ajohnson,Engineering,Engineers
Bob,Williams,bwilliams,Sales,Sales Team
"@ | Out-File users.csv

# Import users with auto-group creation
New-WsaUsersFromCsv -Path .\users.csv -AutoCreateGroups -Verbose
```

### Security Hardening Workflow

```powershell
# Review current baseline
Get-Content .\baselines\security.json

# Apply security baseline
Invoke-WsaSecurityBaseline -Verbose -WhatIf  # Test first
Invoke-WsaSecurityBaseline -Verbose           # Apply

# If needed, rollback
Invoke-WsaSecurityBaseline -Rollback -Verbose
```

## Dashboard API

The dashboard provides a JSON API for integration:

```powershell
# While dashboard is running, fetch data
Invoke-RestMethod -Uri http://localhost:8080/api/health
```

**Response includes:**
- Health score (0-100)
- CPU/Memory/Disk metrics
- Service status
- Event log summaries
- System uptime and process count

## Logging

All operations are logged to:
```
$env:ProgramData\WinSysAuto\Logs\WinSysAuto-<date>.log
```

Logs are JSON-formatted for easy parsing:
```json
{"Timestamp":"2025-11-05T10:30:00","Level":"INFO","Component":"Get-WsaHealth","Message":"Starting health inventory."}
```

## Best Practices

1. **Run Initialize-WsaEnvironment after major infrastructure changes**
2. **Use -WhatIf with functions that make changes** (user creation, security baseline)
3. **Schedule Get-WsaHealth and Backup-WsaConfig** using Windows Task Scheduler
4. **Customize baselines/security.json** for your organization's requirements
5. **Review logs regularly** at `$env:ProgramData\WinSysAuto\Logs`

## Compatibility Notes

### PowerShell 5.1 vs 7+
The module works on both but installation paths differ:
- **5.1**: `Documents\WindowsPowerShell\Modules`
- **7+**: `Documents\PowerShell\Modules`

The installer handles this automatically.

### Domain vs Workgroup
- **Domain-joined**: Full functionality with AD, DNS, DHCP
- **Workgroup**: Health monitoring and dashboard still work

### Permissions
- Most functions work with **read-only access**
- User creation and security baseline require **administrative privileges**
- Dashboard can run **without admin** (unless port < 1024)

## Troubleshooting

### "Module commands not found after installation"
```powershell
# Restart PowerShell or manually import
Import-Module WinSysAuto -Force
```

### "Configuration not found" errors
```powershell
# Run initialization
Initialize-WsaEnvironment
```

### Dashboard won't start
```powershell
# Check if port is in use
netstat -ano | findstr :8080

# Use different port
Start-WsaDashboard -Port 9090
```

### "Access Denied" errors
```powershell
# Run as Administrator for privileged operations
# Or use -WhatIf to see what would change
Get-WsaHealth -WhatIf
```

## Version History

**v1.0.0 - Production Ready Release**
- Environment auto-detection with `Initialize-WsaEnvironment`
- Removed all hardcoded lab-specific values
- Simplified to 6 essential functions
- Works on any Windows domain
- Graceful degradation when modules unavailable
- Production-ready install script
- Comprehensive error handling

**v0.2.0 - M4 Dashboard Release**
- Added live health dashboard
- Lab-specific implementation

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Test on multiple environments
4. Submit a pull request

## License

Copyright (c) Austin Slaughter. All rights reserved.

## Support

- Issues: https://github.com/ajslaughter/WinSysAuto/issues
- Documentation: See `Docs/` folder for detailed guides

## Acknowledgments

Special thanks to the PowerShell community for inspiration and best practices.
