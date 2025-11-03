$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleRoot = Split-Path -Parent $here
$scriptPath = Join-Path $moduleRoot 'functions/Get-Inventory.ps1'

BeforeAll {
    $script:previousEnv = $env:WINSA_DISABLE_PARALLEL
    $env:WINSA_DISABLE_PARALLEL = '1'
    . $scriptPath
}

AfterAll {
    $env:WINSA_DISABLE_PARALLEL = $script:previousEnv
}

Describe 'Get-Inventory' {
    BeforeEach {
        $script:captured = @()
    }

    Context 'default execution' {
        It 'falls back to the local computer when no name is provided' {
            Mock -CommandName Invoke-InventoryCollection -MockWith {
                param(
                    [string]$ComputerName,
                    [System.Management.Automation.PSCredential]$Credential,
                    [switch]$IncludeApplications
                )

                $script:captured += [pscustomobject]@{
                    ComputerName       = $ComputerName
                    IncludeApplications = $IncludeApplications.IsPresent
                }

                [pscustomobject]@{
                    ComputerName    = $ComputerName
                    Timestamp       = Get-Date
                    OperatingSystem = @{ Caption = 'Test OS' }
                    Hardware        = @{ Manufacturer = 'Test' }
                    Applications    = $null
                    Errors          = $null
                }
            }

            $result = Get-Inventory
            $result | Should -HaveCount 1
            $result[0].ComputerName | Should -Be $env:COMPUTERNAME
            $script:captured[0].IncludeApplications | Should -BeFalse
        }
    }

    Context 'parameter handling' {
        It 'passes IncludeApplications switch through to the collector' {
            Mock -CommandName Invoke-InventoryCollection -Verifiable -MockWith {
                param(
                    [string]$ComputerName,
                    [System.Management.Automation.PSCredential]$Credential,
                    [switch]$IncludeApplications
                )

                $script:captured += $IncludeApplications.IsPresent

                [pscustomobject]@{
                    ComputerName    = $ComputerName
                    Timestamp       = Get-Date
                    OperatingSystem = @{ Caption = 'Test OS' }
                    Hardware        = @{ Manufacturer = 'Test' }
                    Applications    = if ($IncludeApplications) { @('App') } else { $null }
                    Errors          = $null
                }
            }

            $output = Get-Inventory -ComputerName 'Server01' -IncludeApplications
            $output | Should -HaveCount 1
            $script:captured | Should -Contain $true
            Assert-VerifiableMocks
        }
    }

    Context 'collector behavior' {
        It 'returns inventory data structure from Invoke-InventoryCollection' {
            $timestamp = Get-Date

            Mock -CommandName Get-CimInstance -MockWith {
                param(
                    [Parameter(Mandatory=$true)]
                    [string]$ClassName,
                    [string]$ComputerName
                )

                switch ($ClassName) {
                    'Win32_OperatingSystem' {
                        return [pscustomobject]@{
                            Caption        = 'Mock OS'
                            Version        = '1.0'
                            BuildNumber    = '12345'
                            LastBootUpTime = (Get-Date).AddDays(-1)
                        }
                    }
                    'Win32_ComputerSystem' {
                        return [pscustomobject]@{
                            Manufacturer        = 'Contoso'
                            Model               = 'Virtual'
                            TotalPhysicalMemory = 4096
                            NumberOfProcessors  = 2
                        }
                    }
                    'Win32_BIOS' {
                        return [pscustomobject]@{
                            SerialNumber = 'ABC123'
                        }
                    }
                }
            }

            Mock -CommandName Test-Path -MockWith { $true }
            Mock -CommandName Get-ItemProperty -MockWith {
                [pscustomobject]@{
                    DisplayName    = 'Mock App'
                    DisplayVersion = '2.0'
                    Publisher      = 'Fabrikam'
                    InstallDate    = '20230101'
                }
            }

            $result = Invoke-InventoryCollection -ComputerName 'Server02' -IncludeApplications

            $result.ComputerName | Should -Be 'Server02'
            $result.Timestamp | Should -BeGreaterOrEqual $timestamp
            $result.OperatingSystem.Caption | Should -Be 'Mock OS'
            $result.Hardware.Manufacturer | Should -Be 'Contoso'
            $result.Hardware.SerialNumber | Should -Be 'ABC123'
            $result.Applications | Should -Not -BeNullOrEmpty
            $result.Applications[0].Name | Should -Be 'Mock App'
        }
    }
}
