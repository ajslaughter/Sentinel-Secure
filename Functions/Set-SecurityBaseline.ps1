function Set-SecurityBaseline {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $guestDisabled = $false
    try {
        $disableCommand = Get-Command -Name 'Disable-LocalUser' -ErrorAction SilentlyContinue
        if ($disableCommand) {
            if ($PSCmdlet.ShouldProcess('Guest account', 'Disable')) {
                Disable-LocalUser -Name 'Guest' -ErrorAction Stop
            }
        }
        else {
            $guestAccount = [ADSI]"WinNT://./Guest,user"
            if ($guestAccount -and $PSCmdlet.ShouldProcess('Guest account', 'Disable')) {
                $guestAccount.psbase.InvokeSet('AccountDisabled', $true)
                $guestAccount.SetInfo()
            }
        }

        try {
            $guestInfo = Get-CimInstance -ClassName Win32_UserAccount -Filter "Name='Guest' AND LocalAccount=True" -ErrorAction Stop
            $guestDisabled = [bool]$guestInfo.Disabled
        }
        catch {
            $guestDisabled = $true
        }
    }
    catch {
        $guestDisabled = $false
    }

    $smbServerPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
    $smbClientPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10'
    $lsaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'

    if (-not (Test-Path -Path $smbServerPath)) {
        New-Item -Path $smbServerPath -Force | Out-Null
    }
    if (-not (Test-Path -Path $smbClientPath)) {
        New-Item -Path $smbClientPath -Force | Out-Null
    }
    if (-not (Test-Path -Path $lsaPath)) {
        New-Item -Path $lsaPath -Force | Out-Null
    }

    if ($PSCmdlet.ShouldProcess($smbServerPath, 'Disable SMBv1 server protocol')) {
        Set-ItemProperty -Path $smbServerPath -Name 'SMB1' -Value 0 -Type DWord -Force
    }

    if ($PSCmdlet.ShouldProcess($smbClientPath, 'Disable SMBv1 client protocol')) {
        Set-ItemProperty -Path $smbClientPath -Name 'Start' -Value 4 -Type DWord -Force
    }

    if ($PSCmdlet.ShouldProcess($lsaPath, 'Enable password complexity')) {
        Set-ItemProperty -Path $lsaPath -Name 'PasswordComplexity' -Value 1 -Type DWord -Force
    }

    $smbServerDisabled = $false
    $smbClientDisabled = $false
    $passwordComplexity = $false

    try {
        $smbServerDisabled = ((Get-ItemProperty -Path $smbServerPath -Name 'SMB1' -ErrorAction Stop).SMB1 -eq 0)
    }
    catch {
        $smbServerDisabled = $false
    }

    try {
        $smbClientDisabled = ((Get-ItemProperty -Path $smbClientPath -Name 'Start' -ErrorAction Stop).Start -eq 4)
    }
    catch {
        $smbClientDisabled = $false
    }

    try {
        $passwordComplexity = ((Get-ItemProperty -Path $lsaPath -Name 'PasswordComplexity' -ErrorAction Stop).PasswordComplexity -eq 1)
    }
    catch {
        $passwordComplexity = $false
    }

    [pscustomobject]@{
        GuestAccountDisabled     = $guestDisabled
        Smbv1ServerDisabled      = $smbServerDisabled
        Smbv1ClientDisabled      = $smbClientDisabled
        PasswordComplexityEnabled = $passwordComplexity
    }
}
