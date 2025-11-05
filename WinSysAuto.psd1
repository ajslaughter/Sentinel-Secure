@{
    RootModule        = 'WinSysAuto.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = '4ef0f69a-0c8f-4a64-bdb4-9bb88f70f6e4'
    Author            = 'Austin Slaughter'
    CompanyName       = 'WinSysAuto'
    Copyright         = 'Copyright (c) Austin Slaughter. All rights reserved.'
    Description       = 'Automation toolkit for lab.local Windows Server environments.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-WsaHealth',
        'Ensure-WsaDnsForwarders',
        'Ensure-WsaDhcpScope',
        'Ensure-WsaOuModel',
        'New-WsaUsersFromCsv',
        'Ensure-WsaDeptShares',
        'Ensure-WsaDriveMappings',
        'Invoke-WsaSecurityBaseline',
        'Start-WsaDailyReport',
        'Backup-WsaConfig',
        'Invoke-WsaM3HealthReport'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{}
}
