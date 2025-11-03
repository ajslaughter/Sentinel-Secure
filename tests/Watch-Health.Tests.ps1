Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\WinSysAuto.psd1') -Force

Describe 'Watch-Health' {
    BeforeEach {
        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'New-BurntToastNotification' } -MockWith { $null }
        Mock -CommandName Get-Counter -MockWith {
            [pscustomobject]@{
                CounterSamples = @(
                    [pscustomobject]@{ CookedValue = 95 }
                )
            }
        }
        Mock -CommandName Start-Sleep
        Mock -CommandName Write-Host
    }

    It 'alerts when CPU exceeds threshold' {
        Watch-Health -CpuThreshold 90 -SampleIntervalSeconds 1 -MaxSamples 1
        Assert-MockCalled -CommandName Write-Host -Times 1
    }
}
