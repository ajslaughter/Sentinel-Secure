@{
    RootModule        = 'WinSysAuto.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '4ef0f69a-0c8f-4a64-bdb4-9bb88f70f6e4'
    Author            = 'Austin Slaughter'
    CompanyName       = 'WinSysAuto'
    Copyright         = 'Copyright (c) Austin Slaughter. All rights reserved.'
    Description       = 'Production-ready automation toolkit for Windows Server environments. Works on any Windows domain.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Initialize-WsaEnvironment',
        'Get-WsaHealth',
        'Start-WsaDashboard',
        'New-WsaUsersFromCsv',
        'Backup-WsaConfig',
        'Invoke-WsaSecurityBaseline'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags = @('Windows', 'Server', 'Automation', 'ActiveDirectory', 'Monitoring', 'Dashboard')
            ProjectUri = 'https://github.com/ajslaughter/WinSysAuto'
            ReleaseNotes = @'
Version 1.0.0 - Production Ready Release
- Environment auto-detection with Initialize-WsaEnvironment
- Works on ANY Windows domain (no hardcoded values)
- Simplified to 6 essential functions
- Works on DC, member servers, and workstations
- Graceful degradation when modules unavailable
- Cyberpunk dashboard with real-time metrics
- No dependencies on M3 functions
'@
        }
    }
}
