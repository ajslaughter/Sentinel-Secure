BeforeAll {
    . (Join-Path $PSScriptRoot '..' 'functions' 'Watch-Health.ps1')
}

Describe 'Watch-Health' {
    BeforeEach {
        Mock -CommandName Start-Sleep -MockWith {}
    }

    Context 'when BurntToast is available' {
        BeforeEach {
            Mock -CommandName Get-Module -MockWith { [pscustomobject]@{ Name = 'BurntToast' } } -ParameterFilter { $ListAvailable -and $Name -eq 'BurntToast' }
            Mock -CommandName Import-Module -MockWith {}
            Mock -CommandName Get-Command -MockWith { [pscustomobject]@{ Name = 'New-BurntToastNotification' } } -ParameterFilter { $Name -eq 'New-BurntToastNotification' }
            Mock -CommandName New-BurntToastNotification -MockWith {}
        }

        It 'sends a toast when CPU utilisation exceeds the threshold' {
            Mock -CommandName Get-Counter -ParameterFilter { $Counter -is [Array] } -MockWith {
                [pscustomobject]@{
                    CounterSamples = @(
                        [pscustomobject]@{ Path = '\Processor(_Total)\% Processor Time'; CookedValue = 92 },
                        [pscustomobject]@{ Path = '\Memory\% Committed Bytes In Use'; CookedValue = 55 }
                    )
                }
            }

            Mock -CommandName Get-Counter -ParameterFilter { $Counter -eq '\LogicalDisk(_Total)\% Free Space' } -MockWith {
                [pscustomobject]@{
                    CounterSamples = @([pscustomobject]@{ Path = '\LogicalDisk(_Total)\% Free Space'; CookedValue = 40 })
                }
            }

            Watch-Health -CpuThreshold 80 -MemoryThreshold 90 -DiskFreeThreshold 10 -MaxIterations 1 -Verbose:$false

            Assert-MockCalled -CommandName New-BurntToastNotification -Exactly 1 -ParameterFilter {
                $Text[0] -eq 'CPU utilisation alert' -and $Text[1] -like 'CPU usage is at 92*'
            }
        }

        It 'alerts when a monitored service is not running' {
            Mock -CommandName Get-Counter -ParameterFilter { $Counter -is [Array] } -MockWith {
                [pscustomobject]@{
                    CounterSamples = @(
                        [pscustomobject]@{ Path = '\Processor(_Total)\% Processor Time'; CookedValue = 25 },
                        [pscustomobject]@{ Path = '\Memory\% Committed Bytes In Use'; CookedValue = 30 }
                    )
                }
            }

            Mock -CommandName Get-Counter -ParameterFilter { $Counter -eq '\LogicalDisk(_Total)\% Free Space' } -MockWith {
                [pscustomobject]@{
                    CounterSamples = @([pscustomobject]@{ Path = '\LogicalDisk(_Total)\% Free Space'; CookedValue = 70 })
                }
            }

            Mock -CommandName Get-Service -MockWith {
                [pscustomobject]@{ Name = $Name; Status = 'Stopped' }
            }

            Watch-Health -Services 'Spooler' -MaxIterations 1 -Verbose:$false

            Assert-MockCalled -CommandName New-BurntToastNotification -Exactly 1 -ParameterFilter {
                $Text[0] -eq 'Service state alert' -and $Text[1] -like "Service 'Spooler' is Stopped"
            }
        }
    }

    Context 'when BurntToast is not installed' {
        BeforeEach {
            Mock -CommandName Get-Module -MockWith { $null } -ParameterFilter { $ListAvailable -and $Name -eq 'BurntToast' }
            Mock -CommandName Import-Module -MockWith {}
        }

        It 'falls back to warnings when notifications are unavailable' {
            Mock -CommandName Get-Counter -ParameterFilter { $Counter -is [Array] } -MockWith {
                [pscustomobject]@{
                    CounterSamples = @(
                        [pscustomobject]@{ Path = '\Processor(_Total)\% Processor Time'; CookedValue = 85 },
                        [pscustomobject]@{ Path = '\Memory\% Committed Bytes In Use'; CookedValue = 40 }
                    )
                }
            }

            Mock -CommandName Get-Counter -ParameterFilter { $Counter -eq '\LogicalDisk(_Total)\% Free Space' } -MockWith {
                [pscustomobject]@{
                    CounterSamples = @([pscustomobject]@{ Path = '\LogicalDisk(_Total)\% Free Space'; CookedValue = 60 })
                }
            }

            Mock -CommandName Write-Warning -MockWith {}

            Watch-Health -CpuThreshold 80 -MemoryThreshold 90 -DiskFreeThreshold 10 -MaxIterations 1 -Verbose:$false

            Assert-MockCalled -CommandName Write-Warning -ParameterFilter {
                $Message -like 'CPU utilisation alert*'
            }
        }
    }
}
