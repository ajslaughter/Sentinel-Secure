@{
    RootModule        = 'WinSysAuto.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '3f733915-59f0-4e58-add1-8998291f43d4'
    Author            = 'WinSysAuto Maintainers'
    CompanyName       = 'WinSysAuto'
    Copyright         = '2024 WinSysAuto. All rights reserved.'
    Description       = 'Automation utilities for Windows systems.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-Inventory',
        'Invoke-PatchScan',
        'Set-SecurityBaseline',
        'Watch-Health',
        'Export-InventoryReport'
    )
    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()

    FileList          = @(
        'WinSysAuto.psm1',
        'Functions/Get-Inventory.ps1',
        'Functions/Invoke-PatchScan.ps1',
        'Functions/Set-SecurityBaseline.ps1',
        'Functions/Watch-Health.ps1',
        'Functions/Export-InventoryReport.ps1'
    )

    PrivateData       = @{}
}
