@{
    RootModule        = 'WinSysAuto.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '3f733915-59f0-4e58-add1-8998291f43d4'
    Author            = 'WinSysAuto Maintainers'
    CompanyName       = 'WinSysAuto'
    Copyright         = "$(Get-Date -Format yyyy) WinSysAuto. All rights reserved."
    Description       = 'Automation utilities for Windows systems.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @()
    CmdletsToExport   = @()
    AliasesToExport   = @()
    VariablesToExport = @()

    FileList          = @('WinSysAuto.psm1')

    PrivateData       = @{}
}
