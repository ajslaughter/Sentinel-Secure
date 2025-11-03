Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\WinSysAuto.psd1') -Force

Describe 'Export-InventoryReport' {
    BeforeEach {
        Mock -CommandName Get-Inventory -MockWith {
            [pscustomobject]@{
                ComputerName    = 'TestHost'
                OperatingSystem = [pscustomobject]@{ Caption = 'Windows'; Version = '10'; BuildNumber = '19045' }
                MemoryGB        = 8
                Uptime          = [TimeSpan]::FromHours(12)
                Processors      = @([pscustomobject]@{ Name = 'CPU'; NumberOfCores = 4; NumberOfLogicalProcessors = 8; MaxClockSpeedMHz = 3200 })
                Disks           = @([pscustomobject]@{ Name = 'C:'; SizeGB = 100; FreeGB = 50; PercentFree = 50 })
                Last5Patches    = @([pscustomobject]@{ HotFixID = 'KB1'; InstalledOn = (Get-Date); Description = 'Patch' })
            }
        }
        Mock -CommandName Test-Path -MockWith { $false }
        Mock -CommandName New-Item
        Mock -CommandName Set-Content
        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'notepad.exe' } -MockWith { $null }
        Mock -CommandName Write-Host
    }

    It 'creates the report and returns the path' {
        $path = Export-InventoryReport -ComputerName 'TestHost' -OutputDirectory 'C:\\Reports'
        $path | Should -Be 'C:\\Reports\\TestHost-Inventory.html'
        Assert-MockCalled -CommandName New-Item -Times 1
        Assert-MockCalled -CommandName Set-Content -Times 1
        Assert-MockCalled -CommandName Write-Host -Times 1
    }
}
