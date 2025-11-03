<#
.SYNOPSIS
Applies a security baseline defined in the module's baselines directory.

.DESCRIPTION
Reads a JSON baseline definition from the baselines directory and applies the
settings to the local system. Supported settings include Windows Firewall
profiles, Remote Desktop configuration, password policies (via secedit) and
Microsoft Defender preferences. The function records the baseline that was
applied so that Get-SecurityBaseline can report the current state.

.PARAMETER Baseline
Name of the baseline to apply. The value can match the friendly Name property or
file name (without the .json extension) of a baseline stored in the baselines
folder.

.EXAMPLE
Set-SecurityBaseline -Baseline 'SampleBaseline'
Applies the SampleBaseline.json definition from the baselines directory.

.NOTES
Requires administrative privileges.
#>
function Set-SecurityBaseline {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Baseline
    )

    $baselineInfo = Get-SecurityBaseline -BaselineName $Baseline
    if (-not $baselineInfo) {
        return
    }

    $settings = $baselineInfo.Settings
    if (-not $settings) {
        Write-Error "Baseline '$Baseline' does not contain any settings to apply."
        return
    }

    $baselineDirectory = Join-Path -Path $script:ModuleRoot -ChildPath 'baselines'

    $overallSuccess = $true
    $firewallResults = @()
    $remoteDesktopResult = $null
    $passwordPolicyResult = $null
    $defenderResult = $null

    if ($settings.PSObject.Properties['Firewall']) {
        $firewallConfig = $settings.Firewall
        $firewallCommand = Get-Command -Name 'Set-NetFirewallProfile' -ErrorAction SilentlyContinue
        if (-not $firewallCommand) {
            $overallSuccess = $false
            foreach ($profileName in 'Domain', 'Private', 'Public') {
                $firewallResults += [pscustomobject]@{
                    Profile               = $profileName
                    Enabled               = $null
                    DefaultInboundAction  = $null
                    DefaultOutboundAction = $null
                    Status                = 'Failed'
                    Message               = 'Set-NetFirewallProfile cmdlet is unavailable.'
                }
            }
        }
        else {
            foreach ($profileName in 'Domain', 'Private', 'Public') {
                if (-not $firewallConfig.PSObject.Properties[$profileName]) {
                    continue
                }

                $profileSettings = $firewallConfig.$profileName
                $firewallParams = @{ Profile = $profileName }

                if ($profileSettings.PSObject.Properties['Enabled']) {
                    $firewallParams['Enabled'] = if ($profileSettings.Enabled) { 'True' } else { 'False' }
                }
                if ($profileSettings.PSObject.Properties['DefaultInboundAction']) {
                    $firewallParams['DefaultInboundAction'] = [string]$profileSettings.DefaultInboundAction
                }
                if ($profileSettings.PSObject.Properties['DefaultOutboundAction']) {
                    $firewallParams['DefaultOutboundAction'] = [string]$profileSettings.DefaultOutboundAction
                }

                $status = 'Skipped'
                $message = $null

                if ($PSCmdlet.ShouldProcess("Firewall profile $profileName", "Apply baseline '$($baselineInfo.Name)'")) {
                    try {
                        Set-NetFirewallProfile @firewallParams -ErrorAction Stop
                        $status = 'Applied'
                    }
                    catch {
                        $status = 'Failed'
                        $message = $_.Exception.Message
                        $overallSuccess = $false
                    }
                }

                $firewallResults += [pscustomobject]@{
                    Profile               = $profileName
                    Enabled               = if ($profileSettings.PSObject.Properties['Enabled']) { [bool]$profileSettings.Enabled } else { $null }
                    DefaultInboundAction  = if ($profileSettings.PSObject.Properties['DefaultInboundAction']) { [string]$profileSettings.DefaultInboundAction } else { $null }
                    DefaultOutboundAction = if ($profileSettings.PSObject.Properties['DefaultOutboundAction']) { [string]$profileSettings.DefaultOutboundAction } else { $null }
                    Status                = $status
                    Message               = $message
                }
            }
        }
    }

    if ($settings.PSObject.Properties['RemoteDesktop']) {
        $remoteDesktopPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
        $rdpTcpPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
        $remoteDesktopSettings = $settings.RemoteDesktop

        $status = 'Skipped'
        $message = $null

        if ($PSCmdlet.ShouldProcess('Remote Desktop configuration', "Apply baseline '$($baselineInfo.Name)'")) {
            try {
                $denyConnections = if ($remoteDesktopSettings.Enable) { 0 } else { 1 }
                Set-ItemProperty -Path $remoteDesktopPath -Name 'fDenyTSConnections' -Value ([int]$denyConnections) -Force

                if ($remoteDesktopSettings.PSObject.Properties['AllowOnlySecureConnections']) {
                    $secureValue = if ($remoteDesktopSettings.AllowOnlySecureConnections) { 1 } else { 0 }
                    Set-ItemProperty -Path $rdpTcpPath -Name 'UserAuthentication' -Value ([int]$secureValue) -Force
                }

                $status = 'Applied'
            }
            catch {
                $status = 'Failed'
                $message = $_.Exception.Message
                $overallSuccess = $false
            }
        }

        $remoteDesktopResult = [pscustomobject]@{
            Enable                     = if ($remoteDesktopSettings.PSObject.Properties['Enable']) { [bool]$remoteDesktopSettings.Enable } else { $null }
            AllowOnlySecureConnections = if ($remoteDesktopSettings.PSObject.Properties['AllowOnlySecureConnections']) { [bool]$remoteDesktopSettings.AllowOnlySecureConnections } else { $null }
            Status                     = $status
            Message                    = $message
        }
    }

    if ($settings.PSObject.Properties['PasswordPolicy']) {
        $passwordSettings = $settings.PasswordPolicy
        $systemAccessValues = @{}

        if ($passwordSettings.PSObject.Properties['MinimumPasswordLength']) {
            $systemAccessValues['MinimumPasswordLength'] = [int]$passwordSettings.MinimumPasswordLength
        }
        if ($passwordSettings.PSObject.Properties['MaximumPasswordAgeDays']) {
            $systemAccessValues['MaximumPasswordAge'] = [int]$passwordSettings.MaximumPasswordAgeDays
        }
        if ($passwordSettings.PSObject.Properties['MinimumPasswordAgeDays']) {
            $systemAccessValues['MinimumPasswordAge'] = [int]$passwordSettings.MinimumPasswordAgeDays
        }
        if ($passwordSettings.PSObject.Properties['PasswordHistorySize']) {
            $systemAccessValues['PasswordHistorySize'] = [int]$passwordSettings.PasswordHistorySize
        }
        if ($passwordSettings.PSObject.Properties['ComplexityEnabled']) {
            $systemAccessValues['PasswordComplexity'] = if ($passwordSettings.ComplexityEnabled) { 1 } else { 0 }
        }
        if ($passwordSettings.PSObject.Properties['LockoutThreshold']) {
            $systemAccessValues['LockoutBadCount'] = [int]$passwordSettings.LockoutThreshold
        }
        if ($passwordSettings.PSObject.Properties['LockoutDurationMinutes']) {
            $systemAccessValues['LockoutDuration'] = [int]$passwordSettings.LockoutDurationMinutes
        }
        if ($passwordSettings.PSObject.Properties['ResetLockoutCounterMinutes']) {
            $systemAccessValues['ResetLockoutCount'] = [int]$passwordSettings.ResetLockoutCounterMinutes
        }

        $status = 'Skipped'
        $message = $null

        if ($systemAccessValues.Count -gt 0) {
            $seceditCommand = Get-Command -Name 'secedit.exe' -ErrorAction SilentlyContinue
            if (-not $seceditCommand) {
                $status = 'Failed'
                $message = 'secedit.exe is not available on this system.'
                $overallSuccess = $false
            }
            else {
                $seceditPath = $seceditCommand.Source
                if (-not $seceditPath) {
                    $seceditPath = $seceditCommand.Definition
                }
                if (-not $seceditPath) {
                    $seceditPath = $seceditCommand.Path
                }

                $tempFile = New-TemporaryFile
                $infPath = $tempFile.FullName
                $dbPath = [System.IO.Path]::ChangeExtension($infPath, '.sdb')

                $infContent = @('[Unicode]', 'Unicode=yes', '[System Access]')
                foreach ($key in $systemAccessValues.Keys) {
                    $infContent += ("{0} = {1}" -f $key, $systemAccessValues[$key])
                }

                Set-Content -Path $infPath -Value $infContent -Encoding Unicode

                if ($PSCmdlet.ShouldProcess('Local Security Policy', "Apply password policy from baseline '$($baselineInfo.Name)'")) {
                    try {
                        & $seceditPath '/configure', '/db', $dbPath, '/cfg', $infPath, '/areas', 'SECURITYPOLICY' | Out-Null
                        if ($LASTEXITCODE -ne 0) {
                            throw "secedit.exe exited with code $LASTEXITCODE."
                        }
                        $status = 'Applied'
                    }
                    catch {
                        $status = 'Failed'
                        $message = $_.Exception.Message
                        $overallSuccess = $false
                    }
                    finally {
                        Remove-Item -Path $infPath -Force -ErrorAction SilentlyContinue
                        Remove-Item -Path $dbPath -Force -ErrorAction SilentlyContinue
                    }
                }
                else {
                    Remove-Item -Path $infPath -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path $dbPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        else {
            $status = 'NotConfigured'
        }

        $passwordPolicyResult = [pscustomobject]@{
            Settings = $systemAccessValues
            Status   = $status
            Message  = $message
        }
    }

    if ($settings.PSObject.Properties['Defender']) {
        $defenderSettings = $settings.Defender
        $mpPreferenceCommand = Get-Command -Name 'Set-MpPreference' -ErrorAction SilentlyContinue
        $status = 'Skipped'
        $message = $null
        $mpParams = @{}

        if (-not $mpPreferenceCommand) {
            $status = 'Failed'
            $message = 'Set-MpPreference cmdlet is not available.'
            $overallSuccess = $false
        }
        else {
            if ($defenderSettings.PSObject.Properties['RealTimeMonitoring']) {
                $mpParams['DisableRealtimeMonitoring'] = -not [bool]$defenderSettings.RealTimeMonitoring
            }
            if ($defenderSettings.PSObject.Properties['CloudProtection']) {
                $cloudMode = [string]$defenderSettings.CloudProtection
                switch ($cloudMode.ToLowerInvariant()) {
                    'advanced' { $mpParams['MAPSReporting'] = 2 }
                    'basic'    { $mpParams['MAPSReporting'] = 1 }
                    'disabled' { $mpParams['MAPSReporting'] = 0 }
                    default    { $mpParams['MAPSReporting'] = 0 }
                }
            }
            if ($defenderSettings.PSObject.Properties['SampleSubmission']) {
                $submission = [string]$defenderSettings.SampleSubmission
                switch ($submission.ToLowerInvariant()) {
                    'allsamples' { $mpParams['SubmitSamplesConsent'] = 3 }
                    'allsample'  { $mpParams['SubmitSamplesConsent'] = 3 }
                    'safe'       { $mpParams['SubmitSamplesConsent'] = 1 }
                    'safesamples'{ $mpParams['SubmitSamplesConsent'] = 1 }
                    'neversend'  { $mpParams['SubmitSamplesConsent'] = 2 }
                    'never'      { $mpParams['SubmitSamplesConsent'] = 2 }
                    default      { $mpParams['SubmitSamplesConsent'] = 1 }
                }
            }
            if ($defenderSettings.PSObject.Properties['SignatureUpdateIntervalHours']) {
                $mpParams['SignatureSchedule'] = [int]$defenderSettings.SignatureUpdateIntervalHours
            }

            if ($mpParams.Count -gt 0) {
                if ($PSCmdlet.ShouldProcess('Windows Defender preferences', "Apply baseline '$($baselineInfo.Name)'")) {
                    try {
                        Set-MpPreference @mpParams -ErrorAction Stop
                        $status = 'Applied'
                    }
                    catch {
                        $status = 'Failed'
                        $message = $_.Exception.Message
                        $overallSuccess = $false
                    }
                }
            }
            else {
                $status = 'NotConfigured'
            }
        }

        $defenderResult = [pscustomobject]@{
            Parameters = $mpParams
            Status     = $status
            Message    = $message
        }
    }

    $appliedSettings = [pscustomobject]@{
        Firewall       = $firewallResults
        RemoteDesktop  = $remoteDesktopResult
        PasswordPolicy = $passwordPolicyResult
        Defender       = $defenderResult
    }

    $result = [pscustomobject]@{
        BaselineName    = $baselineInfo.Name
        BaselineVersion = $baselineInfo.Version
        BaselinePath    = $baselineInfo.Path
        AppliedSettings = $appliedSettings
        Success         = $overallSuccess -and
            (@($firewallResults | Where-Object { $_.Status -eq 'Failed' }).Count -eq 0) -and
            (-not $remoteDesktopResult -or $remoteDesktopResult.Status -ne 'Failed') -and
            (-not $passwordPolicyResult -or $passwordPolicyResult.Status -ne 'Failed') -and
            (-not $defenderResult -or $defenderResult.Status -ne 'Failed')
    }

    if ($result.Success) {
        $currentTextPath = Join-Path -Path $baselineDirectory -ChildPath 'CurrentBaseline.txt'
        $currentJsonPath = Join-Path -Path $baselineDirectory -ChildPath 'CurrentBaseline.json'

        try {
            Set-Content -Path $currentTextPath -Value $baselineInfo.Name -Encoding UTF8
        }
        catch {
            Write-Warning "Failed to write baseline marker '$currentTextPath'. $_"
        }

        try {
            $marker = [pscustomobject]@{
                Name      = $baselineInfo.Name
                Version   = $baselineInfo.Version
                Path      = $baselineInfo.Path
                AppliedOn = (Get-Date).ToString('o')
                Settings  = $settings
            }
            $marker | ConvertTo-Json -Depth 10 | Set-Content -Path $currentJsonPath -Encoding UTF8
        }
        catch {
            Write-Warning "Failed to write baseline marker '$currentJsonPath'. $_"
        }
    }

    $result
}
