function Invoke-WsaSecurityBaseline {
    <#
    .SYNOPSIS
        Applies or rolls back the WinSysAuto security baseline.

    .DESCRIPTION
        Reads configuration from baselines/security.json and enforces Windows Defender,
        firewall, SMBv1, and time service settings. Supports rollback using the same
        definition file.

    .PARAMETER Rollback
        When supplied, applies the rollback settings defined in the JSON file instead of
        the standard baseline.

    .EXAMPLE
        Invoke-WsaSecurityBaseline -Verbose

        Applies the security baseline using the default configuration file.

    .EXAMPLE
        Invoke-WsaSecurityBaseline -Rollback -Verbose

        Applies the rollback posture.

    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [switch]$Rollback
    )

    $component = 'Invoke-WsaSecurityBaseline'
    Write-WsaLog -Component $component -Message 'Starting security baseline enforcement.'

    $configPath = Join-Path -Path $PSScriptRoot -ChildPath '..\baselines\security.json'
    $configPath = (Resolve-Path -Path $configPath).Path

    if (-not (Test-Path -Path $configPath)) {
        $message = "Baseline file not found at $configPath"
        Write-WsaLog -Component $component -Message $message -Level 'ERROR'
        throw $message
    }

    try {
        $json = Get-Content -Path $configPath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $message = "Failed to parse baseline: $($_.Exception.Message)"
        Write-WsaLog -Component $component -Message $message -Level 'ERROR'
        throw $message
    }

    $mode = if ($Rollback.IsPresent) { 'Rollback' } else { 'Apply' }
    if (-not $json.$mode) {
        $message = "Configuration missing '$mode' section."
        Write-WsaLog -Component $component -Message $message -Level 'ERROR'
        throw $message
    }

    $settings = $json.$mode
    $changes  = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]

    # Defender
    if ($settings.Defender) {
        try {
            $status = Get-MpComputerStatus -ErrorAction Stop
            $desired = -not [bool]$settings.Defender.DisableRealtimeMonitoring
            $current = $status.RealTimeProtectionEnabled
            if ($current -ne $desired) {
                if ($PSCmdlet.ShouldProcess('Windows Defender', "Set realtime monitoring to $desired", 'Update Defender preferences')) {
                    Set-MpPreference -DisableRealtimeMonitoring:(!$desired) -ErrorAction Stop
                    $changes.Add("Set Defender realtime monitoring to $desired") | Out-Null
                }
            }
        }
        catch {
            $msg = "Failed to adjust Defender settings: $($_.Exception.Message)"
            Write-WsaLog -Component $component -Message $msg -Level 'WARN'
            $findings.Add($msg) | Out-Null
        }
    }

    # Firewall
    if ($settings.Firewall) {
        try {
            $profiles = Get-NetFirewallProfile -Profile Domain, Private -ErrorAction Stop
            foreach ($profile in $profiles) {
                $desired = if ($profile.Name -eq 'Domain') { $settings.Firewall.DomainProfile } else { $settings.Firewall.PrivateProfile }
                if ($null -ne $desired) {
                    $shouldEnable = [bool]$desired
                    if ($profile.Enabled -ne $shouldEnable) {
                        if ($PSCmdlet.ShouldProcess("Firewall profile $($profile.Name)", "Set Enabled=$shouldEnable", 'Update firewall profile')) {
                            Set-NetFirewallProfile -Profile $profile.Name -Enabled:($shouldEnable) -ErrorAction Stop
                            $changes.Add("Set firewall $($profile.Name) profile to $shouldEnable") | Out-Null
                        }
                    }
                }
            }
        }
        catch {
            $msg = "Failed to adjust firewall profiles: $($_.Exception.Message)"
            Write-WsaLog -Component $component -Message $msg -Level 'WARN'
            $findings.Add($msg) | Out-Null
        }
    }

    # SMBv1
    if ($settings.SMB1) {
        try {
            $config = Get-SmbServerConfiguration -ErrorAction Stop
            $desired = [bool]$settings.SMB1.Enable
            if ($config.EnableSMB1Protocol -ne $desired) {
                if ($PSCmdlet.ShouldProcess('SMB Server', "Set SMB1 protocol to $desired", 'Configure SMB1')) {
                    Set-SmbServerConfiguration -EnableSMB1Protocol $desired -Force -ErrorAction Stop
                    $changes.Add("Set SMB1 protocol to $desired") | Out-Null
                }
            }
        }
        catch {
            $msg = "Failed to manage SMB1: $($_.Exception.Message)"
            Write-WsaLog -Component $component -Message $msg -Level 'WARN'
            $findings.Add($msg) | Out-Null
        }
    }

    # Time service
    if ($settings.Time) {
        $ntpServer = $settings.Time.NtpServer
        if ($ntpServer) {
            try {
                $paramsPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'
                $currentNtp = (Get-ItemProperty -Path $paramsPath -Name NtpServer -ErrorAction Stop).NtpServer
                if ($currentNtp -ne $ntpServer) {
                    if ($PSCmdlet.ShouldProcess('W32Time', "Set NTP server to $ntpServer", 'Configure time synchronisation')) {
                        Set-ItemProperty -Path $paramsPath -Name NtpServer -Value $ntpServer -ErrorAction Stop
                        Set-ItemProperty -Path $paramsPath -Name Type -Value 'NTP' -ErrorAction Stop
                        & w32tm /config /update | Out-Null
                        $changes.Add("Updated NTP server to $ntpServer") | Out-Null
                    }
                }
            }
            catch {
                $msg = "Failed to configure time service: $($_.Exception.Message)"
                Write-WsaLog -Component $component -Message $msg -Level 'WARN'
                $findings.Add($msg) | Out-Null
            }
        }
    }

    if ($changes.Count -eq 0 -and $findings.Count -eq 0) {
        $findings.Add('Compliant') | Out-Null
    }

    $status = if ($changes.Count -gt 0) { 'Changed' } else { 'Compliant' }
    if ($findings.Count -gt 0 -and -not $findings.Contains('Compliant')) { $status = 'Changed' }

    return New-WsaResult -Status $status -Changes $changes.ToArray() -Findings $findings.ToArray() -Data @{ Mode = $mode; ConfigPath = $configPath }
}
