Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..\WinSysAuto.psd1') -Force

Describe 'Set-SecurityBaseline' {
    BeforeEach {
        Mock -CommandName Get-Command -ParameterFilter { $Name -eq 'Disable-LocalUser' } -MockWith {
            [pscustomobject]@{ Name = 'Disable-LocalUser' }
        }
        Mock -CommandName Disable-LocalUser
        Mock -CommandName Get-CimInstance -ParameterFilter { $ClassName -eq 'Win32_UserAccount' } -MockWith {
            [pscustomobject]@{ Disabled = $true }
        }
        Mock -CommandName Test-Path -MockWith { $true }
        Mock -CommandName New-Item
        Mock -CommandName Set-ItemProperty
        Mock -CommandName Get-ItemProperty -ParameterFilter { $Path -like '*LanmanServer*' -and $Name -eq 'SMB1' } -MockWith {
            [pscustomobject]@{ SMB1 = 0 }
        }
        Mock -CommandName Get-ItemProperty -ParameterFilter { $Path -like '*mrxsmb10*' -and $Name -eq 'Start' } -MockWith {
            [pscustomobject]@{ Start = 4 }
        }
        Mock -CommandName Get-ItemProperty -ParameterFilter { $Path -like '*Control\\Lsa*' -and $Name -eq 'PasswordComplexity' } -MockWith {
            [pscustomobject]@{ PasswordComplexity = 1 }
        }
    }

    It 'enforces baseline settings' {
        $result = Set-SecurityBaseline -Confirm:$false
        Assert-MockCalled -CommandName Disable-LocalUser -Times 1 -Exactly
        Assert-MockCalled -CommandName Set-ItemProperty -Times 3
        $result.GuestAccountDisabled | Should -BeTrue
        $result.Smbv1ServerDisabled | Should -BeTrue
        $result.Smbv1ClientDisabled | Should -BeTrue
        $result.PasswordComplexityEnabled | Should -BeTrue
    }
}
