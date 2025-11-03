Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\WinSysAuto.psd1') -Force

Describe 'Invoke-PatchScan' {
    BeforeAll {
        $script:fakeUpdates = @(
            (New-Object psobject -Property @{
                Title        = 'Update 1'
                KBArticleIDs = @('KB123456')
                MsrcSeverity = 'Critical'
                Categories   = @([pscustomobject]@{ Name = 'Security Updates' })
                IsDownloaded = $false
                IsMandatory  = $true
            })
        )

        $script:fakeUpdatesCollection = New-Object psobject -Property @{ Count = $script:fakeUpdates.Count }
        Add-Member -InputObject $script:fakeUpdatesCollection -MemberType ScriptMethod -Name Item -Value {
            param($index)
            return $script:fakeUpdates[$index]
        } | Out-Null

        $script:fakeSearcher = New-Object psobject
        Add-Member -InputObject $script:fakeSearcher -MemberType ScriptMethod -Name Search -Value {
            param($criteria)
            [pscustomobject]@{ Updates = $script:fakeUpdatesCollection }
        } | Out-Null

        Mock -CommandName New-Object -ParameterFilter { $ComObject -eq 'Microsoft.Update.Session' } -MockWith {
            $session = New-Object psobject
            Add-Member -InputObject $session -MemberType ScriptMethod -Name CreateUpdateSearcher -Value {
                param()
                return $script:fakeSearcher
            } | Out-Null
            return $session
        }
    }

    It 'returns pending updates from the searcher' {
        $result = Invoke-PatchScan
        $result | Should -Not -BeNullOrEmpty
        $result[0].KB | Should -Be 'KB123456'
        $result[0].Severity | Should -Be 'Critical'
        $result[0].Categories | Should -Be 'Security Updates'
    }
}
