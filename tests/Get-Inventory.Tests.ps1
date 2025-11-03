Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\WinSysAuto.psd1') -Force

Describe 'Get-Inventory' {
    BeforeEach {
        $script:osObject = [pscustomobject]@{
            Caption               = 'Windows Server 2022'
            Version               = '10.0.20348'
            BuildNumber           = '20348'
            TotalVisibleMemorySize = 8388608
            LastBootUpTime        = (Get-Date).AddHours(-8)
        }

        $script:cpuObjects = @(
            [pscustomobject]@{
                Name                      = 'Test CPU'
                NumberOfCores             = 4
                NumberOfLogicalProcessors = 8
                MaxClockSpeed             = 3200
            }
        )

        $script:diskObjects = @(
            [pscustomobject]@{
                DeviceID   = 'C:'
                Size       = 107374182400
                FreeSpace  = 53687091200
            }
        )

        $script:hotFixes = @(
            [pscustomobject]@{ HotFixID = 'KB000001'; InstalledOn = (Get-Date).AddDays(-1); Description = 'Security Update' },
            [pscustomobject]@{ HotFixID = 'KB000002'; InstalledOn = (Get-Date).AddDays(-2); Description = 'Update' }
        )

        Mock -CommandName Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_OperatingSystem' } -MockWith { $script:osObject }
        Mock -CommandName Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_Processor' } -MockWith { $script:cpuObjects }
        Mock -CommandName Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_LogicalDisk' } -MockWith { $script:diskObjects }
        Mock -CommandName Get-HotFix -MockWith { $script:hotFixes }
    }

    It 'returns operating system information' {
        $result = Get-Inventory -ComputerName 'TestHost'
        $result.OperatingSystem.Caption | Should -Be 'Windows Server 2022'
        $result.MemoryGB | Should -BeGreaterThan 0
        $result.Processors[0].Name | Should -Be 'Test CPU'
        $result.Disks[0].Name | Should -Be 'C:'
        $result.Last5Patches.Count | Should -Be 2
    }
}
