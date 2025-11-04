function Backup-WsaConfig {
    <#
    .SYNOPSIS
        Creates an archive of configuration data for the lab environment.

    .DESCRIPTION
        Collects the latest health reports, GPO backups, DHCP scope information, and DNS
        forwarder settings. Packages the data into C:\LabReports\Backups\WsaBackup-<date>.zip.

    .EXAMPLE
        Backup-WsaConfig -Verbose

        Creates a backup archive using the default settings.

    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param()

    $component = 'Backup-WsaConfig'
    Write-WsaLog -Component $component -Message 'Starting configuration backup.'

    $backupRoot = 'C:\LabReports\Backups'
    if (-not (Test-Path -Path $backupRoot)) {
        New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $archiveName = "WsaBackup-$timestamp.zip"
    $archivePath = Join-Path -Path $backupRoot -ChildPath $archiveName

    $changes  = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]

    if (-not $PSCmdlet.ShouldProcess($archivePath, 'Create configuration backup', 'Create backup archive')) {
        $findings.Add('Backup creation skipped due to -WhatIf.') | Out-Null
        return New-WsaResult -Status 'Compliant' -Changes $changes.ToArray() -Findings $findings.ToArray()
    }

    $tempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("WsaBackup-" + [Guid]::NewGuid())
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    try {
        # Latest report folder
        $reportsRoot = 'C:\LabReports'
        if (Test-Path -Path $reportsRoot) {
            $latest = Get-ChildItem -Path $reportsRoot -Directory -Filter 'Daily-*' | Sort-Object CreationTime -Descending | Select-Object -First 1
            if ($latest) {
                Copy-Item -Path $latest.FullName -Destination (Join-Path $tempDir 'Reports') -Recurse -Force
            }
            else {
                $findings.Add('No Daily-* reports located to include in backup.') | Out-Null
            }
        }
        else {
            $findings.Add('LabReports directory missing.') | Out-Null
        }

        # GPO backup
        if (Get-Command -Name Backup-Gpo -ErrorAction SilentlyContinue) {
            $gpoDir = Join-Path $tempDir 'GpoBackup'
            New-Item -Path $gpoDir -ItemType Directory -Force | Out-Null
            Backup-Gpo -All -Path $gpoDir -ErrorAction Stop | Out-Null
        }
        else {
            $findings.Add('GroupPolicy module unavailable - skipping GPO backup.') | Out-Null
        }

        # DHCP configuration
        if (Get-Command -Name Get-DhcpServerv4Scope -ErrorAction SilentlyContinue) {
            $dhcpDir = Join-Path $tempDir 'Dhcp'
            New-Item -Path $dhcpDir -ItemType Directory -Force | Out-Null
            Get-DhcpServerv4Scope | Export-Clixml -Path (Join-Path $dhcpDir 'Scopes.xml')
            Get-DhcpServerv4OptionValue | Export-Clixml -Path (Join-Path $dhcpDir 'Options.xml')
        }
        else {
            $findings.Add('DhcpServer module unavailable - skipping DHCP export.') | Out-Null
        }

        # DNS forwarders
        if (Get-Command -Name Get-DnsServerForwarder -ErrorAction SilentlyContinue) {
            $dnsDir = Join-Path $tempDir 'Dns'
            New-Item -Path $dnsDir -ItemType Directory -Force | Out-Null
            Get-DnsServerForwarder | Export-Clixml -Path (Join-Path $dnsDir 'Forwarders.xml')
        }
        else {
            $findings.Add('DnsServer module unavailable - skipping DNS export.') | Out-Null
        }

        Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $archivePath -Force
        $changes.Add("Created backup archive $archivePath") | Out-Null
    }
    catch {
        $msg = "Failed to create configuration backup: $($_.Exception.Message)"
        Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
        throw $msg
    }
    finally {
        try {
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        catch {
            # FIXED: Wrapped $tempDir in ${} to avoid PowerShell misreading as drive path
            Write-WsaLog -Component $component -Message "Failed to remove temp directory ${tempDir}: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    $status = if ($changes.Count -gt 0) { 'Changed' } else { 'Compliant' }
    if ($findings.Count -gt 0 -and $status -ne 'Changed') { $status = 'Changed' }

    return New-WsaResult -Status $status -Changes $changes.ToArray() -Findings $findings.ToArray() -Data @{ ArchivePath = $archivePath }
}
