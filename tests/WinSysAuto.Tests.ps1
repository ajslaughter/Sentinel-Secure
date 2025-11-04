$moduleManifest = Join-Path -Path $PSScriptRoot -ChildPath '..\WinSysAuto.psd1'
Import-Module $moduleManifest -Force

$expectedFunctions = @(
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

Describe 'WinSysAuto module' {
    It 'exports the expected public functions' {
        $commands = Get-Command -Module WinSysAuto | Select-Object -ExpandProperty Name
        $commands | Should -ContainExactly $expectedFunctions
    }

    It 'supports ShouldProcess on all public functions' {
        foreach ($name in $expectedFunctions) {
            $cmd = Get-Command -Name $name
            $cmd | Should -Not -BeNullOrEmpty
            $cmd.CommandType | Should -Be 'Function'
            $cmd.ScriptBlock.Attributes.SupportsShouldProcess | Should -BeTrue
        }
    }

    It 'returns a structured object from Get-WsaHealth with -WhatIf' {
        $result = Get-WsaHealth -WhatIf
        $result | Should -Not -BeNullOrEmpty
        $result | Should -BeOfType 'System.Management.Automation.PSCustomObject'
        $result.PSObject.Properties.Name | Should -Contain 'Status'
        $result.PSObject.Properties.Name | Should -Contain 'Findings'
    }

    It 'creates a test snapshot with Invoke-WsaM3HealthReport -TestMode' {
        $result = Invoke-WsaM3HealthReport -RunNow -TestMode
        $result | Should -BeOfType 'System.Management.Automation.PSCustomObject'
        $result.Metrics.CpuTotal | Should -BeGreaterThan 0
        $result.Services.Services.Count | Should -BeGreaterThan 0
        $result.Analysis.HealthScore | Should -BeGreaterThan 0
    }

    It 'parses the default configuration file correctly' {
        $moduleRoot = Split-Path -Parent $PSCommandPath
        $resourceRoot = Join-Path -Path $moduleRoot -ChildPath '..\M3_automation_monitoring'
        $configPath = Join-Path -Path $resourceRoot -ChildPath 'config\default_config.yaml'
        $config = Get-WsaM3Configuration -Path $configPath -ResourceRoot $resourceRoot
        $config | Should -Not -BeNullOrEmpty
        $config.thresholds.cpu.critical | Should -Be 90
        $config.services.critical | Should -Contain 'LanmanServer'
    }
}
