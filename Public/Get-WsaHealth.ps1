function Get-WsaHealth {
    <#
    .SYNOPSIS
        Collects an operational health summary for core Windows services.

    .DESCRIPTION
        Gathers inventory for Active Directory, DNS, DHCP, Group Policy, file shares,
        disk utilization, and recent warning/error events. The function exports a
        Summary.txt and supporting CSV files to the configured reports directory and
        returns a structured object describing the results. Safe to run repeatedly.

        Works on both domain controllers and member servers. Gracefully handles
        missing modules and permissions.

    .EXAMPLE
        Get-WsaHealth -Verbose

        Runs the health check, writes verbose details, and exports the reports.

    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param()

    $component = 'Get-WsaHealth'
    Write-WsaLog -Component $component -Message 'Starting health inventory.'

    $changes  = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]

    # Get environment configuration
    $config = Get-WsaConfig
    $exportRoot = $config.paths.reports

    if (-not $PSCmdlet.ShouldProcess('Windows environment', 'Collect health data')) {
        Write-WsaLog -Component $component -Message 'WhatIf specified - skipping health run.' -Level 'WARN'
        $findings.Add('WhatIf: Health check was not executed.') | Out-Null
        return New-WsaResult -Status 'Compliant' -Findings $findings.ToArray()
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $exportPath = Join-Path -Path $exportRoot -ChildPath "Health-$timestamp"

    try {
        if (-not (Test-Path -Path $exportPath)) {
            New-Item -Path $exportPath -ItemType Directory -Force | Out-Null
            $changes.Add("Created report directory $exportPath") | Out-Null
        }
    }
    catch {
        $message = "Failed to prepare export directory: $($_.Exception.Message)"
        Write-WsaLog -Component $component -Message $message -Level 'ERROR'
        throw $message
    }

    $summaryLines = New-Object System.Collections.Generic.List[string]

    # Add system info
    $summaryLines.Add("=" * 60) | Out-Null
    $summaryLines.Add("WinSysAuto Health Report") | Out-Null
    $summaryLines.Add("=" * 60) | Out-Null
    $summaryLines.Add("Computer: $($config.computerName)") | Out-Null
    if ($config.isDomainJoined) {
        $summaryLines.Add("Domain: $($config.domain)") | Out-Null
    }
    else {
        $summaryLines.Add("Domain: Not domain-joined") | Out-Null
    }
    $summaryLines.Add("Generated: $(Get-Date -Format 's')") | Out-Null
    $summaryLines.Add("") | Out-Null

    # Active Directory
    if (Get-Command -Name Get-ADDomain -ErrorAction SilentlyContinue) {
        try {
            $adDomain = Get-ADDomain -ErrorAction Stop
            $adForest = Get-ADForest -ErrorAction Stop
            $summaryLines.Add("Active Directory Domain: $($adDomain.DNSRoot) (Mode: $($adDomain.DomainMode))") | Out-Null
            $summaryLines.Add("Forest Mode: $($adForest.ForestMode); GC: $($adForest.GlobalCatalogs -join ', ')") | Out-Null
            $domainCsv = Join-Path -Path $exportPath -ChildPath 'ActiveDirectory.csv'
            $adDomain | Select-Object Name, DNSRoot, DomainMode, InfrastructureMaster, RIDMaster, PDCEmulator |
                Export-Csv -Path $domainCsv -NoTypeInformation
        }
        catch {
            $msg = "Unable to query Active Directory: $($_.Exception.Message)"
            Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
            $findings.Add($msg) | Out-Null
        }
    }
    else {
        $findings.Add('ActiveDirectory module unavailable - skipping AD inventory.') | Out-Null
        $summaryLines.Add("Active Directory: Module not available") | Out-Null
    }

    # DNS Forwarders
    if (Get-Command -Name Get-DnsServerForwarder -ErrorAction SilentlyContinue) {
        try {
            $dnsForwarders = Get-DnsServerForwarder -ErrorAction Stop
            if ($dnsForwarders -and $dnsForwarders.IPAddress) {
                $summaryLines.Add('DNS Forwarders: ' + ($dnsForwarders.IPAddress.IPAddressToString -join ', ')) | Out-Null
                $dnsCsv = Join-Path -Path $exportPath -ChildPath 'DnsForwarders.csv'
                $dnsForwarders | Select-Object IPAddress, TimeOut, Retries | Export-Csv -Path $dnsCsv -NoTypeInformation
            }
            else {
                $summaryLines.Add('DNS Forwarders: None configured') | Out-Null
            }
        }
        catch {
            $msg = "Unable to query DNS forwarders: $($_.Exception.Message)"
            Write-WsaLog -Component $component -Message $msg -Level 'WARN'
            $summaryLines.Add('DNS Forwarders: Not a DNS server or access denied') | Out-Null
        }
    }
    else {
        $summaryLines.Add('DNS Server: Module not available') | Out-Null
    }

    # DHCP scope
    if (Get-Command -Name Get-DhcpServerv4Scope -ErrorAction SilentlyContinue) {
        try {
            $dhcpScopes = Get-DhcpServerv4Scope -ErrorAction Stop
            $summaryLines.Add("DHCP Scopes: $($dhcpScopes.Count)") | Out-Null
            $dhcpCsv = Join-Path -Path $exportPath -ChildPath 'DhcpScopes.csv'
            $dhcpScopes | Select-Object ScopeId, Name, StartRange, EndRange, State | Export-Csv -Path $dhcpCsv -NoTypeInformation
        }
        catch {
            $msg = "Unable to query DHCP scopes: $($_.Exception.Message)"
            Write-WsaLog -Component $component -Message $msg -Level 'WARN'
            $summaryLines.Add('DHCP Scopes: Not a DHCP server or access denied') | Out-Null
        }
    }
    else {
        $summaryLines.Add('DHCP Server: Module not available') | Out-Null
    }

    # Group Policy
    if (Get-Command -Name Get-GPO -ErrorAction SilentlyContinue) {
        try {
            $gpos = Get-GPO -All -ErrorAction Stop
            $summaryLines.Add("GPO Count: $($gpos.Count)") | Out-Null
            $gpoCsv = Join-Path -Path $exportPath -ChildPath 'GroupPolicy.csv'
            $gpos | Select-Object DisplayName, Id, CreationTime, ModificationTime | Export-Csv -Path $gpoCsv -NoTypeInformation
        }
        catch {
            $msg = "Unable to query Group Policy: $($_.Exception.Message)"
            Write-WsaLog -Component $component -Message $msg -Level 'WARN'
            $summaryLines.Add('Group Policy: Access denied or not available') | Out-Null
        }
    }
    else {
        $summaryLines.Add('Group Policy: Module not available') | Out-Null
    }

    # Shares and disks
    if (Get-Command -Name Get-SmbShare -ErrorAction SilentlyContinue) {
        try {
            $shares = Get-SmbShare -Special $false -ErrorAction Stop
            $shareCsv = Join-Path -Path $exportPath -ChildPath 'FileShares.csv'
            $shares | Select-Object Name, Path, Description, FolderEnumerationMode | Export-Csv -Path $shareCsv -NoTypeInformation
            $summaryLines.Add("File Shares: $($shares.Count)") | Out-Null
        }
        catch {
            $msg = "Unable to query SMB shares: $($_.Exception.Message)"
            Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
            $findings.Add($msg) | Out-Null
        }
    }
    else {
        $findings.Add('SMBShare cmdlets unavailable - skipping share inventory.') | Out-Null
    }

    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -or $_.Free }
        $driveCsv = Join-Path -Path $exportPath -ChildPath 'DiskUsage.csv'
        $driveData = $drives | Select-Object Name, Root, Used, Free, @{Name='FreePercent';Expression={
            if (($_.Used + $_.Free) -gt 0) {
                [math]::Round(($_.Free/($_.Used + $_.Free))*100,2)
            } else {
                0
            }
        }}
        $driveData | Export-Csv -Path $driveCsv -NoTypeInformation
        $summaryLines.Add("Disk Drives: $($drives.Count)") | Out-Null
    }
    catch {
        $msg = "Unable to query disk utilization: $($_.Exception.Message)"
        Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
        $findings.Add($msg) | Out-Null
    }

    # Event log warnings (last 24h)
    try {
        $events = Get-WinEvent -FilterHashtable @{LogName='System'; Level=2,3; StartTime=(Get-Date).AddHours(-24)} -ErrorAction Stop
        $eventCsv = Join-Path -Path $exportPath -ChildPath 'SystemEvents.csv'
        $events | Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, Message |
            Export-Csv -Path $eventCsv -NoTypeInformation
        $summaryLines.Add("System warnings/errors (last 24h): $($events.Count)") | Out-Null
    }
    catch {
        $msg = "No system events found or unable to query: $($_.Exception.Message)"
        Write-WsaLog -Component $component -Message $msg -Level 'WARN'
        $summaryLines.Add("System warnings/errors (last 24h): 0") | Out-Null
    }

    $summaryPath = Join-Path -Path $exportPath -ChildPath 'Summary.txt'
    try {
        $summaryLines.Add("") | Out-Null
        $summaryLines.Add("Export Folder: $exportPath") | Out-Null
        $summaryLines | Out-File -FilePath $summaryPath -Encoding UTF8
    }
    catch {
        $msg = "Failed to write summary: $($_.Exception.Message)"
        Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
        $findings.Add($msg) | Out-Null
    }

    $status = if ($findings.Count -eq 0) { 'Compliant' } else { 'Changed' }
    Write-WsaLog -Component $component -Message "Health inventory complete with status $status."

    Write-Host "`nHealth report saved to: $exportPath" -ForegroundColor Cyan
    Write-Host "View summary: $summaryPath" -ForegroundColor Cyan

    return New-WsaResult -Status $status -Changes $changes.ToArray() -Findings $findings.ToArray() -Data @{ ExportPath = $exportPath; Summary = $summaryPath }
}
