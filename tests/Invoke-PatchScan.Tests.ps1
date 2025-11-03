Import-Module Pester -ErrorAction SilentlyContinue | Out-Null

$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
. (Join-Path -Path $moduleRoot -ChildPath 'functions/Invoke-PatchScan.ps1')

Describe 'Format-PatchScanResult' {
    It 'populates severity and classification metadata' {
        $update = [pscustomobject]@{
            Title        = 'Security Update for Windows'
            KBArticleIDs = @('KB123456')
            MsrcSeverity = 'Critical'
            Categories   = @([pscustomobject]@{ Name = 'Security Updates' })
        }

        $result = Format-PatchScanResult -Update $update -ComputerName 'Server01'

        $result.ComputerName | Should -Be 'Server01'
        $result.KB | Should -Be 'KB123456'
        $result.Severity | Should -Be 'Critical'
        $result.Classification | Should -Be 'Security Updates'
    }

    It 'defaults severity and classification when missing' {
        $update = [pscustomobject]@{
            Title = 'Cumulative Update'
        }

        $result = Format-PatchScanResult -Update $update -ComputerName 'Server02'

        $result.Severity | Should -Be 'Unspecified'
        $result.Classification | Should -Be 'Unspecified'
    }
}

Describe 'Get-PendingUpdatesFromPSWindowsUpdate' {
    It 'filters out installed updates' {
        Mock -CommandName Get-WindowsUpdate -MockWith {
            @(
                [pscustomobject]@{ Title = 'Pending'; IsInstalled = $false },
                [pscustomobject]@{ Title = 'Installed'; IsInstalled = $true }
            )
        }

        $pending = Get-PendingUpdatesFromPSWindowsUpdate

        $pending | Should -HaveCount 1
        $pending[0].Title | Should -Be 'Pending'
    }
}

Describe 'Invoke-PatchScanCore' {
    It 'uses PSWindowsUpdate path when available' {
        Mock -CommandName Test-PSWindowsUpdateAvailable -MockWith { $true }
        Mock -CommandName Get-PendingUpdatesFromPSWindowsUpdate -MockWith {
            @([pscustomobject]@{
                Title        = 'Security Update'
                KBArticleIDs = @('KB999999')
                MsrcSeverity = 'Important'
                Categories   = @([pscustomobject]@{ Name = 'Security Updates' })
            })
        }
        Mock -CommandName Get-PendingUpdatesFromCom -MockWith {
            throw 'COM fallback should not be used.'
        }

        $results = Invoke-PatchScanCore -TargetComputer 'Server03'

        $results | Should -HaveCount 1
        $results[0].ComputerName | Should -Be 'Server03'
        $results[0].KB | Should -Be 'KB999999'
        $results[0].Classification | Should -Be 'Security Updates'
    }

    It 'uses COM fallback when PSWindowsUpdate is unavailable' {
        Mock -CommandName Test-PSWindowsUpdateAvailable -MockWith { $false }
        Mock -CommandName Get-PendingUpdatesFromPSWindowsUpdate -MockWith {
            throw 'PSWindowsUpdate should not be used.'
        }
        Mock -CommandName Get-PendingUpdatesFromCom -MockWith {
            @([pscustomobject]@{
                Title        = 'Definition Update'
                KBArticleIDs = @('KB111111')
                Categories   = @([pscustomobject]@{ Name = 'Definition Updates' })
            })
        }

        $results = Invoke-PatchScanCore -TargetComputer 'Server04'

        $results | Should -HaveCount 1
        $results[0].Classification | Should -Be 'Definition Updates'
    }
}

Describe 'Invoke-PatchScan' {
    It 'invokes remoting for remote computer and maps ComputerName' {
        Mock -CommandName Invoke-Command -MockWith {
            @([pscustomobject]@{
                ComputerName  = 'Server05'
                KB            = 'KB222222'
                Title         = 'Remote Update'
                Severity      = 'Moderate'
                Classification = 'Security Updates'
            })
        }

        $results = Invoke-PatchScan -ComputerName 'Server05'

        Assert-MockCalled Invoke-Command -Times 1
        $results | Should -HaveCount 1
        $results[0].ComputerName | Should -Be 'Server05'
    }
}
