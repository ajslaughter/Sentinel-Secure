function Ensure-WsaDnsForwarders {
    <#
    .SYNOPSIS
        Ensures DNS forwarders are aligned with the WinSysAuto baseline.

    .DESCRIPTION
        Validates configured DNS forwarders on the local DNS server. Missing forwarders
        are added, unexpected entries are removed, and optional removal of root hints is
        supported. Designed for the DC01.lab.local DNS role.

    .PARAMETER Forwarders
        One or more IPv4 addresses that should be configured as forwarders. Defaults to
        Cloudflare (1.1.1.1) and Google (8.8.8.8).

    .PARAMETER DisableRootHints
        When supplied, root hints are removed to ensure queries are only resolved via the
        configured forwarders.

    .EXAMPLE
        Ensure-WsaDnsForwarders -Verbose

        Confirms DNS forwarders are set to the baseline values, reporting compliance.

    .EXAMPLE
        Ensure-WsaDnsForwarders -Forwarders '9.9.9.9','1.1.1.1' -DisableRootHints

        Updates the forwarders to Quad9 and Cloudflare and removes root hints.

    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d{2}|[1-9]?\d)){3}$')]
        [string[]]$Forwarders = @('1.1.1.1', '8.8.8.8'),

        [switch]$DisableRootHints
    )

    $component = 'Ensure-WsaDnsForwarders'
    Write-WsaLog -Component $component -Message 'Evaluating DNS forwarders.'

    if (-not (Get-Command -Name Get-DnsServerForwarder -ErrorAction SilentlyContinue)) {
        $message = 'DnsServer module not available on this system.'
        Write-WsaLog -Component $component -Message $message -Level 'ERROR'
        throw $message
    }

    $changes  = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]

    try {
        $current = Get-DnsServerForwarder -ErrorAction Stop
        $currentIPs = @()
        if ($current) {
            $currentIPs = $current | ForEach-Object { $_.IPAddress.IPAddressToString }
        }
    }
    catch {
        $message = "Failed to query DNS forwarders: $($_.Exception.Message)"
        Write-WsaLog -Component $component -Message $message -Level 'ERROR'
        throw $message
    }

    $missing = $Forwarders | Where-Object { $_ -notin $currentIPs }
    $unexpected = $currentIPs | Where-Object { $_ -notin $Forwarders }

    if ($missing.Count -eq 0 -and $unexpected.Count -eq 0) {
        Write-WsaLog -Component $component -Message 'DNS forwarders already compliant.'
        $findings.Add('Compliant') | Out-Null
    }

    if ($missing.Count -gt 0 -and $PSCmdlet.ShouldProcess('DNS Server', "Add forwarders: $($missing -join ', ')", 'Confirm forwarder configuration changes')) {
        foreach ($ip in $missing) {
            try {
                Add-DnsServerForwarder -IPAddress $ip -ErrorAction Stop | Out-Null
                $changes.Add("Added forwarder $ip") | Out-Null
                Write-WsaLog -Component $component -Message "Added DNS forwarder $ip."
            }
            catch {
                # FIXED: Wrapped $ip in ${} to avoid PowerShell misreading as drive path
                $msg = "Failed to add forwarder ${ip}: $($_.Exception.Message)"
                Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
                $findings.Add($msg) | Out-Null
            }
        }
    }

    if ($unexpected.Count -gt 0 -and $PSCmdlet.ShouldProcess('DNS Server', "Remove forwarders: $($unexpected -join ', ')", 'Confirm forwarder removal')) {
        foreach ($ip in $unexpected) {
            try {
                Remove-DnsServerForwarder -IPAddress $ip -Force -ErrorAction Stop
                $changes.Add("Removed forwarder $ip") | Out-Null
                Write-WsaLog -Component $component -Message "Removed DNS forwarder $ip."
            }
            catch {
                # FIXED: Wrapped $ip in ${} to avoid PowerShell misreading as drive path
                $msg = "Failed to remove forwarder ${ip}: $($_.Exception.Message)"
                Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
                $findings.Add($msg) | Out-Null
            }
        }
    }

    if ($DisableRootHints.IsPresent) {
        try {
            $rootHints = Get-DnsServerRootHint -ErrorAction Stop
            if ($rootHints.Count -gt 0) {
                if ($PSCmdlet.ShouldProcess('DNS Server', 'Remove root hints', 'Disable root hints')) {
                    $rootHints | Remove-DnsServerRootHint -Force -ErrorAction Stop
                    $changes.Add('Removed DNS root hints') | Out-Null
                    Write-WsaLog -Component $component -Message 'Removed DNS root hints.'
                }
            }
            else {
                Write-WsaLog -Component $component -Message 'Root hints already absent.'
            }
        }
        catch {
            $msg = "Failed to manage root hints: $($_.Exception.Message)"
            Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
            $findings.Add($msg) | Out-Null
        }
    }

    $status = if ($changes.Count -gt 0 -or $findings.Count -gt 0 -and -not $findings.Contains('Compliant')) { 'Changed' } else { 'Compliant' }
    if ($changes.Count -eq 0 -and $findings.Count -eq 0) {
        $status = 'Compliant'
    }

    return New-WsaResult -Status $status -Changes $changes.ToArray() -Findings $findings.ToArray() -Data @{ Forwarders = $Forwarders }
}
