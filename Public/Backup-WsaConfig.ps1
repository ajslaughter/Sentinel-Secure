function Backup-WsaConfig {
    <#
    .SYNOPSIS
        Creates an archive of configuration data for the Windows environment.

    .DESCRIPTION
        Collects the latest health reports, GPO backups, DHCP scope information, and DNS
        forwarder settings. Packages the data into a timestamped ZIP archive in the configured
        backups directory. Works on both domain controllers and member servers.

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

    # Get environment configuration
    $config = Get-WsaConfig
    $backupRoot = $config.paths.backups
    $reportsRoot = $config.paths.reports

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
        # Latest health report folder
        if (Test-Path -Path $reportsRoot) {
            $latest = Get-ChildItem -Path $reportsRoot -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1
            if ($latest) {
                Copy-Item -Path $latest.FullName -Destination (Join-Path $tempDir 'Reports') -Recurse -Force
                $changes.Add("Included health report: $($latest.Name)") | Out-Null
            }
            else {
                $findings.Add('No health reports found to include in backup.') | Out-Null
            }
        }
        else {
            $findings.Add('Reports directory not found.') | Out-Null
        }

        # WinSysAuto config file
        $wsaConfigPath = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\config.json'
        if (Test-Path -Path $wsaConfigPath) {
            $configDir = Join-Path $tempDir 'Config'
            New-Item -Path $configDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path $wsaConfigPath -Destination $configDir -Force
            $changes.Add("Included WinSysAuto configuration") | Out-Null
        }

        # GPO backup
        if (Get-Command -Name Backup-Gpo -ErrorAction SilentlyContinue) {
            try {
                $gpoDir = Join-Path $tempDir 'GpoBackup'
                New-Item -Path $gpoDir -ItemType Directory -Force | Out-Null
                $gpoBackupResult = Backup-Gpo -All -Path $gpoDir -ErrorAction Stop
                $changes.Add("Backed up $(@($gpoBackupResult).Count) GPOs") | Out-Null
            }
            catch {
                $findings.Add("GPO backup failed: $($_.Exception.Message)") | Out-Null
            }
        }
        else {
            $findings.Add('GroupPolicy module unavailable - skipping GPO backup.') | Out-Null
        }

        # DHCP configuration
        if (Get-Command -Name Get-DhcpServerv4Scope -ErrorAction SilentlyContinue) {
            try {
                $dhcpScopes = Get-DhcpServerv4Scope -ErrorAction Stop
                if ($dhcpScopes) {
                    $dhcpDir = Join-Path $tempDir 'Dhcp'
                    New-Item -Path $dhcpDir -ItemType Directory -Force | Out-Null
                    $dhcpScopes | Export-Clixml -Path (Join-Path $dhcpDir 'Scopes.xml')
                    Get-DhcpServerv4OptionValue -ErrorAction SilentlyContinue | Export-Clixml -Path (Join-Path $dhcpDir 'Options.xml')
                    $changes.Add("Backed up DHCP configuration") | Out-Null
                }
            }
            catch {
                $findings.Add("DHCP backup skipped: $($_.Exception.Message)") | Out-Null
            }
        }
        else {
            $findings.Add('DhcpServer module unavailable - skipping DHCP export.') | Out-Null
        }

        # DNS forwarders
        if (Get-Command -Name Get-DnsServerForwarder -ErrorAction SilentlyContinue) {
            try {
                $dnsForwarders = Get-DnsServerForwarder -ErrorAction Stop
                if ($dnsForwarders) {
                    $dnsDir = Join-Path $tempDir 'Dns'
                    New-Item -Path $dnsDir -ItemType Directory -Force | Out-Null
                    $dnsForwarders | Export-Clixml -Path (Join-Path $dnsDir 'Forwarders.xml')
                    $changes.Add("Backed up DNS forwarders") | Out-Null
                }
            }
            catch {
                $findings.Add("DNS backup skipped: $($_.Exception.Message)") | Out-Null
            }
        }
        else {
            $findings.Add('DnsServer module unavailable - skipping DNS export.') | Out-Null
        }

        # Create the archive
        Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $archivePath -Force
        $changes.Add("Created backup archive: $archivePath") | Out-Null
        Write-Host "`nBackup archive created: $archivePath" -ForegroundColor Green
    }
    catch {
        $msg = "Failed to create configuration backup: $($_.Exception.Message)"
        Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
        throw $msg
    }
    finally {
        try {
            if (Test-Path -Path $tempDir) {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-WsaLog -Component $component -Message "Failed to remove temp directory: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    $status = if ($changes.Count -gt 0) { 'Changed' } else { 'Compliant' }
    if ($findings.Count -gt 0 -and $status -ne 'Changed') { $status = 'Changed' }

    return New-WsaResult -Status $status -Changes $changes.ToArray() -Findings $findings.ToArray() -Data @{ ArchivePath = $archivePath }
}
