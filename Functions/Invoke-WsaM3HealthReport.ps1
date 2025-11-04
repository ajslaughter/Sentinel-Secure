function Invoke-WsaM3HealthReport {
    [CmdletBinding(DefaultParameterSetName = 'RunNow', SupportsShouldProcess = $true)]
    param(
        [Parameter(ParameterSetName = 'RunNow')]
        [switch]$RunNow,

        [Parameter(ParameterSetName = 'Schedule')]
        [switch]$Schedule,

        [Parameter(ParameterSetName = 'History')]
        [switch]$History,

        [string]$ConfigPath,

        [switch]$SendEmail,

        [switch]$TestMode
    )

    $moduleRoot = Split-Path -Parent $PSScriptRoot
    $resourceRoot = Join-Path -Path $moduleRoot -ChildPath 'M3_automation_monitoring'
    if (-not (Test-Path -Path $resourceRoot)) {
        throw "Resource folder '$resourceRoot' was not found."
    }

    if (-not $ConfigPath) {
        $ConfigPath = Join-Path -Path $resourceRoot -ChildPath 'config/default_config.yaml'
    }

    $config = Get-WsaM3Configuration -Path $ConfigPath -ResourceRoot $resourceRoot
    if (-not $config) {
        throw "Failed to load configuration from '$ConfigPath'."
    }

    $statePath = Join-Path -Path $resourceRoot -ChildPath 'data'
    if (-not (Test-Path -Path $statePath)) {
        New-Item -Path $statePath -ItemType Directory -Force | Out-Null
    }

    if ($PSCmdlet.ParameterSetName -eq 'Schedule') {
        if ($PSCmdlet.ShouldProcess('Scheduled Tasks', 'Create or update WinSysAuto M3 tasks')) {
            return Set-WsaM3ScheduledTask -Config $config -ModuleRoot $moduleRoot -TestMode:$TestMode
        }
        return
    }

    if ($PSCmdlet.ParameterSetName -eq 'History') {
        return Get-WsaM3HistoricalReport -Config $config -StatePath $statePath
    }

    $snapshot = New-WsaM3Snapshot -Config $config -ResourceRoot $resourceRoot -StatePath $statePath -SendEmail:$SendEmail -TestMode:$TestMode
    return $snapshot
}

function Get-WsaM3Configuration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ResourceRoot
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Configuration file '$Path' not found."
    }

    $raw = Get-Content -Path $Path -ErrorAction Stop
    $data = ConvertFrom-WsaSimpleYaml -Lines $raw

    if ($data.reports -and $data.reports.html_template) {
        $templatePath = $data.reports.html_template
        if (-not (Test-Path -Path $templatePath)) {
            $candidate = Join-Path -Path $ResourceRoot -ChildPath $data.reports.html_template
            if (Test-Path -Path $candidate) {
                $data.reports.html_template = $candidate
            }
        }
    }

    if ($data.reports -and $data.reports.output_path) {
        $resolved = Resolve-WsaPath -Value $data.reports.output_path
        $data.reports.output_path = $resolved
    }

    if ($data.logging -and $data.logging.path) {
        $data.logging.path = Resolve-WsaPath -Value $data.logging.path
    }

    return $data
}

function ConvertFrom-WsaSimpleYaml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Lines
    )

    $root = @{}
    $stack = New-Object System.Collections.ArrayList
    $null = $stack.Add(@{ Indent = -1; Type = 'object'; Value = $root })

    for ($index = 0; $index -lt $Lines.Length; $index++) {
        $line = $Lines[$index]
        if ($null -eq $line) { continue }

        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }

        $commentIndex = $trimmed.IndexOf(' #')
        if ($commentIndex -ge 0) {
            $trimmed = $trimmed.Substring(0, $commentIndex).TrimEnd()
        }

        if ($trimmed.Length -eq 0) { continue }

        $indent = $line.Length - $line.TrimStart().Length

        while ($stack.Count -gt 1 -and $indent -le $stack[$stack.Count - 1].Indent) {
            $stack.RemoveAt($stack.Count - 1)
        }

        $context = $stack[$stack.Count - 1]

        if ($trimmed.StartsWith('- ')) {
            if ($context.Type -ne 'array') {
                throw "YAML structure error near line $($index + 1): unexpected array item."
            }

            $valueText = $trimmed.Substring(2).Trim()
            $value = Convert-WsaYamlScalar -Value $valueText
            $null = $context.Value.Add($value)
            continue
        }

        $parts = $trimmed.Split(':', 2)
        if ($parts.Count -lt 2) {
            throw "Invalid YAML line: '$trimmed'"
        }

        $key = $parts[0].Trim()
        $valueText = $parts[1].Trim()

        if ($valueText.Length -eq 0) {
            $childType = 'object'
            $nextIndex = $index + 1
            while ($nextIndex -lt $Lines.Length) {
                $lookAhead = $Lines[$nextIndex]
                if ($null -eq $lookAhead) { $nextIndex++; continue }
                $lookTrim = $lookAhead.Trim()
                if ($lookTrim.Length -eq 0 -or $lookTrim.StartsWith('#')) { $nextIndex++; continue }
                $lookComment = $lookTrim.IndexOf(' #')
                if ($lookComment -ge 0) { $lookTrim = $lookTrim.Substring(0, $lookComment).TrimEnd() }
                $lookIndent = $lookAhead.Length - $lookAhead.TrimStart().Length
                if ($lookIndent -le $indent) { break }
                if ($lookTrim.StartsWith('- ')) {
                    $childType = 'array'
                }
                break
            }

            if ($childType -eq 'array') {
                $child = New-Object System.Collections.ArrayList
            }
            else {
                $child = @{}
            }

            $context.Value[$key] = $child
            $null = $stack.Add(@{ Indent = $indent + 2; Type = $childType; Value = $child })
            continue
        }

        $context.Value[$key] = Convert-WsaYamlScalar -Value $valueText
    }

    return $root
}

function Convert-WsaYamlScalar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $clean = $Value.Trim()
    if ($clean.Length -eq 0) { return $null }

    if (($clean.StartsWith('"') -and $clean.EndsWith('"')) -or ($clean.StartsWith("'") -and $clean.EndsWith("'"))) {
        return $clean.Substring(1, $clean.Length - 2)
    }

    if ($clean -eq 'true') { return $true }
    if ($clean -eq 'false') { return $false }

    if ($clean -match '^[+-]?[0-9]+$') {
        return [int64]$clean
    }

    if ($clean -match '^[+-]?[0-9]+\.[0-9]+$') {
        return [double]$clean
    }

    return $clean
}

function Resolve-WsaPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    $resolved = $expanded -replace '/', '\\'
    return $resolved
}

function New-WsaM3Snapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$ResourceRoot,

        [Parameter(Mandatory)]
        [string]$StatePath,

        [switch]$SendEmail,

        [switch]$TestMode
    )

    $timestamp = Get-Date
    Write-WsaLog -Component 'M3' -Message "Starting health snapshot at $timestamp" -Level 'INFO'

    $metrics = Get-WsaM3SystemMetrics -TestMode:$TestMode
    $services = Get-WsaM3ServiceHealth -Config $Config -TestMode:$TestMode
    $events = Get-WsaM3EventSummary -Config $Config -TestMode:$TestMode

    $analysis = Test-WsaM3Thresholds -Metrics $metrics -Services $services -Events $events -Config $Config
    $history = Save-WsaM3History -Metrics $metrics -Services $services -Events $events -StatePath $StatePath -Config $Config -Timestamp $timestamp -TestMode:$TestMode

    $reportData = New-WsaM3ReportData -Metrics $metrics -Services $services -Events $events -Analysis $analysis -History $history -Timestamp $timestamp -Config $Config

    $artifacts = Save-WsaM3Artifacts -ReportData $reportData -Config $Config -ResourceRoot $ResourceRoot

    if ($SendEmail -or ($Config.email.enabled -and $Config.email.enabled -eq $true)) {
        Send-WsaM3EmailReport -ReportData $reportData -Artifacts $artifacts -Config $Config
    }

    $result = [pscustomobject]@{
        Timestamp   = $timestamp
        Metrics     = $metrics
        Services    = $services
        Events      = $events
        Analysis    = $analysis
        History     = $history
        Artifacts   = $artifacts
    }

    Write-WsaLog -Component 'M3' -Message 'Health snapshot completed' -Level 'INFO'
    return $result
}

function Get-WsaM3SystemMetrics {
    [CmdletBinding()]
    param(
        [switch]$TestMode
    )

    if ($TestMode) {
        return [pscustomobject]@{
            CpuTotal           = 32
            CpuPerCore         = @(22, 28, 35, 18)
            MemoryPercent      = 54
            MemoryUsedGB       = 18
            MemoryTotalGB      = 32
            DiskUsage          = @(
                [pscustomobject]@{ Name = 'C:'; TotalGB = 120; UsedGB = 80; FreeGB = 40; UsagePercent = 66 },
                [pscustomobject]@{ Name = 'D:'; TotalGB = 500; UsedGB = 350; FreeGB = 150; UsagePercent = 70 }
            )
            NetworkBytesTotal  = 5368709120
            UptimeDays         = 12
            BootTime           = (Get-Date).AddDays(-12)
            ProcessCount       = 145
            TopProcesses       = @(
                [pscustomobject]@{ Name = 'sqlservr'; Cpu = 12.5; MemoryMB = 2048 },
                [pscustomobject]@{ Name = 'w3wp'; Cpu = 7.1; MemoryMB = 512 },
                [pscustomobject]@{ Name = 'powershell'; Cpu = 3.8; MemoryMB = 256 }
            )
        }
    }

    try {
        $cpuInfo = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
        $osInfo = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $diskInfo = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
        $netInfo = Get-CimInstance -ClassName Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction Stop
    }
    catch {
        Write-WsaLog -Component 'M3' -Message ("Metric collection failed: {0}" -f $_.Exception.Message) -Level 'WARN'
        return Get-WsaM3SystemMetrics -TestMode
    }

    $cpuTotal = [double]::Parse(($cpuInfo | Measure-Object -Property LoadPercentage -Average).Average)
    $cpuPerCore = @()
    foreach ($cpu in $cpuInfo) {
        $cpuPerCore += [double]$cpu.LoadPercentage
    }

    $totalMemory = [math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 2)
    $freeMemory = [math]::Round($osInfo.FreePhysicalMemory / 1MB, 2)
    $usedMemory = [math]::Round($totalMemory - $freeMemory, 2)
    $memoryPercent = if ($totalMemory -eq 0) { 0 } else { [math]::Round(($usedMemory / $totalMemory) * 100, 2) }

    $diskUsage = @()
    foreach ($disk in $diskInfo) {
        $sizeGB = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 2) } else { 0 }
        $freeGB = if ($disk.FreeSpace) { [math]::Round($disk.FreeSpace / 1GB, 2) } else { 0 }
        $usedGB = [math]::Round([math]::Max($sizeGB - $freeGB, 0), 2)
        $usagePercent = if ($sizeGB -eq 0) { 0 } else { [math]::Round(($usedGB / $sizeGB) * 100, 2) }
        $diskUsage += [pscustomobject]@{
            Name          = $disk.DeviceID
            TotalGB       = $sizeGB
            UsedGB        = $usedGB
            FreeGB        = $freeGB
            UsagePercent  = $usagePercent
        }
    }

    $totalBytes = 0
    foreach ($adapter in $netInfo) {
        $totalBytes += [double]$adapter.BytesTotalPerSec
    }

    $bootTime = $osInfo.LastBootUpTime
    $uptime = (Get-Date) - $bootTime

    $topProcesses = Get-Process | Sort-Object -Property CPU -Descending | Select-Object -First 5 | ForEach-Object {
        [pscustomobject]@{
            Name      = $_.ProcessName
            Cpu       = [math]::Round($_.CPU, 2)
            MemoryMB  = [math]::Round($_.WorkingSet64 / 1MB, 2)
        }
    }

    return [pscustomobject]@{
        CpuTotal          = [math]::Round($cpuTotal, 2)
        CpuPerCore        = $cpuPerCore
        MemoryPercent     = $memoryPercent
        MemoryUsedGB      = $usedMemory
        MemoryTotalGB     = $totalMemory
        DiskUsage         = $diskUsage
        NetworkBytesTotal = [math]::Round($totalBytes, 2)
        UptimeDays        = [math]::Round($uptime.TotalDays, 2)
        BootTime          = $bootTime
        ProcessCount      = (Get-Process | Measure-Object).Count
        TopProcesses      = $topProcesses
    }
}

function Get-WsaM3ServiceHealth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [switch]$TestMode
    )

    if ($TestMode) {
        return [pscustomobject]@{
            Services = @(
                [pscustomobject]@{ Name = 'LanmanServer'; Status = 'Running'; StartType = 'Automatic'; Notes = '' },
                [pscustomobject]@{ Name = 'LanmanWorkstation'; Status = 'Running'; StartType = 'Automatic'; Notes = '' },
                [pscustomobject]@{ Name = 'Dhcp'; Status = 'Running'; StartType = 'Automatic'; Notes = '' },
                [pscustomobject]@{ Name = 'DNS'; Status = 'Running'; StartType = 'Automatic'; Notes = '' },
                [pscustomobject]@{ Name = 'EventLog'; Status = 'Running'; StartType = 'Automatic'; Notes = '' }
            )
            WindowsUpdate  = 'Operational'
            WindowsDefender = 'Healthy'
            PendingReboot  = $false
            Firewall       = 'Enabled'
        }
    }

    $servicesToCheck = @()
    if ($Config.services -and $Config.services.critical) {
        $servicesToCheck = $Config.services.critical
    }

    $serviceStatus = @()
    foreach ($name in $servicesToCheck) {
        try {
            $svc = Get-Service -Name $name -ErrorAction Stop
            $serviceStatus += [pscustomobject]@{
                Name      = $svc.Name
                Status    = $svc.Status.ToString()
                StartType = $svc.StartType.ToString()
                Notes     = ''
            }
        }
        catch {
            $serviceStatus += [pscustomobject]@{
                Name      = $name
                Status    = 'Unknown'
                StartType = 'Unknown'
                Notes     = $_.Exception.Message
            }
        }
    }

    $windowsUpdate = 'Unknown'
    if ($Config.services.monitor_windows_update) {
        try {
            $wuService = Get-Service -Name 'wuauserv' -ErrorAction Stop
            if ($wuService.Status -eq 'Running') {
                $windowsUpdate = 'Running'
            }
            else {
                $windowsUpdate = "Stopped ($($wuService.Status))"
            }
        }
        catch {
            $windowsUpdate = 'Unavailable'
        }
    }

    $defender = 'Unknown'
    if ($Config.services.monitor_windows_defender) {
        try {
            $defService = Get-Service -Name 'WinDefend' -ErrorAction Stop
            $defender = $defService.Status.ToString()
        }
        catch {
            $defender = 'Unavailable'
        }
    }

    $pendingReboot = $false
    if ($Config.services.monitor_pending_reboot) {
        $pendingPaths = @(
            'HKLM:SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Component Based Servicing\\RebootPending',
            'HKLM:SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\WindowsUpdate\\Auto Update\\RebootRequired',
            'HKLM:SYSTEM\\CurrentControlSet\\Control\\Session Manager\\PendingFileRenameOperations'
        )
        foreach ($path in $pendingPaths) {
            if (Test-Path -Path $path) {
                $pendingReboot = $true
                break
            }
        }
    }

    $firewall = 'Unknown'
    if ($Config.services.monitor_firewall) {
        try {
            $profiles = Get-NetFirewallProfile -ErrorAction Stop
            if ($profiles | Where-Object { $_.Enabled -eq $false }) {
                $firewall = 'Partially Disabled'
            }
            else {
                $firewall = 'Enabled'
            }
        }
        catch {
            $firewall = 'Unavailable'
        }
    }

    return [pscustomobject]@{
        Services        = $serviceStatus
        WindowsUpdate   = $windowsUpdate
        WindowsDefender = $defender
        PendingReboot   = $pendingReboot
        Firewall        = $firewall
    }
}

function Get-WsaM3EventSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [switch]$TestMode
    )

    if ($TestMode) {
        return [pscustomobject]@{
            Summary = @(
                [pscustomobject]@{ Log = 'System'; Errors = 2; Warnings = 4; Critical = 0 },
                [pscustomobject]@{ Log = 'Application'; Errors = 1; Warnings = 3; Critical = 0 },
                [pscustomobject]@{ Log = 'Security'; Errors = 0; Warnings = 0; Critical = 1 }
            )
            FailedLogons = 3
            SecurityEvents = @(
                [pscustomobject]@{ Category = 'Account Lockout'; Count = 1 },
                [pscustomobject]@{ Category = 'Failed Logon'; Count = 3 }
            )
        }
    }

    $summary = @()
    $logs = @('System', 'Application', 'Security')
    $startTime = (Get-Date).AddHours(-24)

    foreach ($log in $logs) {
        try {
            $events = Get-WinEvent -FilterHashtable @{ LogName = $log; StartTime = $startTime } -ErrorAction Stop
            $errors = ($events | Where-Object { $_.LevelDisplayName -eq 'Error' }).Count
            $warnings = ($events | Where-Object { $_.LevelDisplayName -eq 'Warning' }).Count
            $critical = ($events | Where-Object { $_.LevelDisplayName -eq 'Critical' }).Count
            $summary += [pscustomobject]@{
                Log      = $log
                Errors   = $errors
                Warnings = $warnings
                Critical = $critical
            }
        }
        catch {
            $summary += [pscustomobject]@{
                Log      = $log
                Errors   = -1
                Warnings = -1
                Critical = -1
            }
        }
    }

    $failedLogons = 0
    try {
        $failedLogons = (Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = @(4625); StartTime = $startTime }).Count
    }
    catch {
        $failedLogons = -1
    }

    $securityDays = if ($Config.reports -and $Config.reports.security_summary_days) { [int]$Config.reports.security_summary_days } else { 7 }
    $securityEvents = @()
    try {
        $secEvents = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; StartTime = (Get-Date).AddDays(-$securityDays) }
        $byId = $secEvents | Group-Object -Property Id
        foreach ($group in $byId) {
            $securityEvents += [pscustomobject]@{
                Category = "Event $($group.Name)"
                Count    = $group.Count
            }
        }
    }
    catch {
        $securityEvents = @()
    }

    return [pscustomobject]@{
        Summary       = $summary
        FailedLogons  = $failedLogons
        SecurityEvents = $securityEvents
    }
}

function Test-WsaM3Thresholds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Metrics,

        [Parameter(Mandatory)]
        $Services,

        [Parameter(Mandatory)]
        $Events,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $thresholds = $Config.thresholds
    $alerts = @()

    if ($thresholds) {
        if ($thresholds.cpu) {
            $cpuStatus = Get-WsaM3ThresholdStatus -Value $Metrics.CpuTotal -Threshold $thresholds.cpu
            if ($cpuStatus.Level -ne 'Normal') {
                $alerts += [pscustomobject]@{ Metric = 'CPU Total'; Level = $cpuStatus.Level; Message = $cpuStatus.Message }
            }
        }

        if ($thresholds.memory) {
            $memStatus = Get-WsaM3ThresholdStatus -Value $Metrics.MemoryPercent -Threshold $thresholds.memory
            if ($memStatus.Level -ne 'Normal') {
                $alerts += [pscustomobject]@{ Metric = 'Memory'; Level = $memStatus.Level; Message = $memStatus.Message }
            }
        }

        if ($thresholds.disk) {
            foreach ($disk in $Metrics.DiskUsage) {
                $diskStatus = Get-WsaM3ThresholdStatus -Value $disk.UsagePercent -Threshold $thresholds.disk
                if ($diskStatus.Level -ne 'Normal') {
                    $alerts += [pscustomobject]@{ Metric = "Disk $($disk.Name)"; Level = $diskStatus.Level; Message = $diskStatus.Message }
                }
            }
        }

        if ($thresholds.failed_logons -and $Events.FailedLogons -ge 0) {
            $logonStatus = Get-WsaM3ThresholdStatus -Value $Events.FailedLogons -Threshold $thresholds.failed_logons
            if ($logonStatus.Level -ne 'Normal') {
                $alerts += [pscustomobject]@{ Metric = 'Failed Logons'; Level = $logonStatus.Level; Message = $logonStatus.Message }
            }
        }
    }

    $serviceFailures = ($Services.Services | Where-Object { $_.Status -ne 'Running' }).Count
    if ($serviceFailures -gt 0 -and $thresholds.service_failures) {
        $serviceStatus = Get-WsaM3ThresholdStatus -Value $serviceFailures -Threshold $thresholds.service_failures
        if ($serviceStatus.Level -ne 'Normal') {
            $alerts += [pscustomobject]@{ Metric = 'Services'; Level = $serviceStatus.Level; Message = $serviceStatus.Message }
        }
    }

    $healthScore = [math]::Max(0, 100 - ($alerts.Count * 10) - ([int]($Metrics.CpuTotal / 10)))

    return [pscustomobject]@{
        Alerts      = $alerts
        HealthScore = $healthScore
    }
}

function Get-WsaM3ThresholdStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$Value,

        [Parameter(Mandatory)]
        [hashtable]$Threshold
    )

    $warning = [double]$Threshold.warning
    $critical = [double]$Threshold.critical

    if ($Value -ge $critical) {
        return [pscustomobject]@{ Level = 'Critical'; Message = "Value $Value exceeded critical threshold $critical" }
    }
    elseif ($Value -ge $warning) {
        return [pscustomobject]@{ Level = 'Warning'; Message = "Value $Value exceeded warning threshold $warning" }
    }

    return [pscustomobject]@{ Level = 'Normal'; Message = "Value $Value within acceptable range" }
}

function Save-WsaM3History {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Metrics,

        [Parameter(Mandatory)]
        $Services,

        [Parameter(Mandatory)]
        $Events,

        [Parameter(Mandatory)]
        [string]$StatePath,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [datetime]$Timestamp,

        [switch]$TestMode
    )

    $snapshot = [pscustomobject]@{
        Timestamp = $Timestamp.ToString('o')
        Metrics   = $Metrics
        Services  = $Services
        Events    = $Events
    }

    $snapshotsFile = Join-Path -Path $StatePath -ChildPath 'snapshots.json'
    $existing = @()
    if (Test-Path -Path $snapshotsFile) {
        try {
            $existing = Get-Content -Path $snapshotsFile -Raw | ConvertFrom-Json -Depth 10
        }
        catch {
            $existing = @()
        }
    }

    $collection = New-Object System.Collections.ArrayList
    if ($existing) {
        foreach ($item in $existing) {
            $null = $collection.Add($item)
        }
    }

    $null = $collection.Add($snapshot)

    $retain = if ($Config.retention -and $Config.retention.snapshots) { [int]$Config.retention.snapshots } else { 30 }
    while ($collection.Count -gt $retain) {
        $collection.RemoveAt(0)
    }

    $collection | ConvertTo-Json -Depth 10 | Set-Content -Path $snapshotsFile -Encoding UTF8

    $baselineFile = Join-Path -Path $StatePath -ChildPath 'baseline.json'
    if (-not (Test-Path -Path $baselineFile) -or $TestMode) {
        $baselineData = @{ Metrics = $Metrics; Services = $Services; Events = $Events; Timestamp = $Timestamp.ToString('o') }
        $baselineData | ConvertTo-Json -Depth 10 | Set-Content -Path $baselineFile -Encoding UTF8
    }

    return [pscustomobject]@{
        Snapshots = $collection
        Baseline  = if (Test-Path -Path $baselineFile) { Get-Content -Path $baselineFile -Raw | ConvertFrom-Json -Depth 10 } else { $null }
    }
}

function New-WsaM3ReportData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Metrics,

        [Parameter(Mandatory)]
        $Services,

        [Parameter(Mandatory)]
        $Events,

        [Parameter(Mandatory)]
        $Analysis,

        [Parameter(Mandatory)]
        $History,

        [Parameter(Mandatory)]
        [datetime]$Timestamp,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $yesterday = $null
    $lastWeek = $null
    if ($History.Snapshots.Count -ge 2) {
        $yesterday = $History.Snapshots[$History.Snapshots.Count - 2]
    }
    if ($History.Snapshots.Count -ge 7) {
        $lastWeek = $History.Snapshots[$History.Snapshots.Count - 7]
    }

    $metricsRows = @()
    $metricsRows += [pscustomobject]@{
        Name = 'CPU Usage (%)'
        Current = $Metrics.CpuTotal
        PreviousDay = if ($yesterday) { $yesterday.Metrics.CpuTotal } else { $null }
        PreviousWeek = if ($lastWeek) { $lastWeek.Metrics.CpuTotal } else { $null }
        StatusSymbol = Get-WsaM3StatusSymbol -Value $Metrics.CpuTotal -Threshold $Config.thresholds.cpu
        StatusClass = Get-WsaM3StatusClass -Value $Metrics.CpuTotal -Threshold $Config.thresholds.cpu
    }

    $metricsRows += [pscustomobject]@{
        Name = 'Memory Usage (%)'
        Current = $Metrics.MemoryPercent
        PreviousDay = if ($yesterday) { $yesterday.Metrics.MemoryPercent } else { $null }
        PreviousWeek = if ($lastWeek) { $lastWeek.Metrics.MemoryPercent } else { $null }
        StatusSymbol = Get-WsaM3StatusSymbol -Value $Metrics.MemoryPercent -Threshold $Config.thresholds.memory
        StatusClass = Get-WsaM3StatusClass -Value $Metrics.MemoryPercent -Threshold $Config.thresholds.memory
    }

    $diskRows = @()
    foreach ($disk in $Metrics.DiskUsage) {
        $diskRows += [pscustomobject]@{
            Name = $disk.Name
            TotalGB = $disk.TotalGB
            UsedGB = $disk.UsedGB
            FreeGB = $disk.FreeGB
            UsagePercent = $disk.UsagePercent
        }
    }

    $serviceRows = $Services.Services

    $securityRows = @()
    foreach ($item in $Events.SecurityEvents) {
        $securityRows += [pscustomobject]@{ Category = $item.Category; Count = $item.Count }
    }

    $trendData = @()
    foreach ($snap in $History.Snapshots) {
        $trendData += @{ timestamp = $snap.Timestamp; value = $snap.Metrics.CpuTotal }
    }

    $recommendations = Get-WsaM3Recommendations -Analysis $Analysis -Services $Services -Events $Events

    $scoreBadge = switch ($Analysis.HealthScore) {
        { $_ -ge 90 } { 'badge-green'; break }
        { $_ -ge 70 } { 'badge-yellow'; break }
        default { 'badge-red' }
    }

    $alertSummary = if ($Analysis.Alerts.Count -gt 0) {
        ($Analysis.Alerts | ForEach-Object { "[$($_.Level)] $($_.Metric) - $($_.Message)" }) -join '; '
    } else {
        'All monitored metrics within acceptable ranges.'
    }

    return [pscustomobject]@{
        Title              = 'Daily Health Report'
        GeneratedAt        = $Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
        HealthScore        = $Analysis.HealthScore
        ScoreBadge         = $scoreBadge
        AlertSummary       = $alertSummary
        Recommendations    = $recommendations
        MetricsRows        = $metricsRows
        ServiceRows        = $serviceRows
        DiskRows           = $diskRows
        SecurityRows       = $securityRows
        SecurityDays       = if ($Config.reports.security_summary_days) { $Config.reports.security_summary_days } else { 7 }
        TrendData          = $trendData
        Raw                = [pscustomobject]@{
            Metrics = $Metrics
            Services = $Services
            Events = $Events
            Analysis = $Analysis
            History = $History
        }
    }
}

function Get-WsaM3StatusSymbol {
    [CmdletBinding()]
    param(
        [double]$Value,
        [hashtable]$Threshold
    )

    $status = Get-WsaM3ThresholdStatus -Value $Value -Threshold $Threshold
    switch ($status.Level) {
        'Critical' { return '🔴' }
        'Warning' { return '🟡' }
        default { return '🟢' }
    }
}

function Get-WsaM3StatusClass {
    [CmdletBinding()]
    param(
        [double]$Value,
        [hashtable]$Threshold
    )

    $status = Get-WsaM3ThresholdStatus -Value $Value -Threshold $Threshold
    switch ($status.Level) {
        'Critical' { return 'status-red' }
        'Warning' { return 'status-yellow' }
        default { return 'status-green' }
    }
}

function Get-WsaM3Recommendations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Analysis,

        [Parameter(Mandatory)]
        $Services,

        [Parameter(Mandatory)]
        $Events
    )

    $recommendations = New-Object System.Collections.ArrayList

    foreach ($alert in $Analysis.Alerts) {
        switch ($alert.Metric) {
            'CPU Total' { $null = $recommendations.Add('Investigate processes with sustained high CPU usage.') }
            'Memory' { $null = $recommendations.Add('Review running services or scheduled tasks for memory leaks.') }
            { $_ -like 'Disk *' } { $null = $recommendations.Add('Plan for storage expansion or cleanup temporary files.') }
            'Failed Logons' { $null = $recommendations.Add('Examine security logs for repeated authentication failures.') }
            'Services' { $null = $recommendations.Add('Restart failed services and validate configuration drift.') }
        }
    }

    if ($Services.PendingReboot) {
        $null = $recommendations.Add('Pending reboot detected. Schedule maintenance window to reboot the server.')
    }

    if ($Services.WindowsDefender -ne 'Running' -and $Services.WindowsDefender -ne 'Healthy') {
        $null = $recommendations.Add('Windows Defender not healthy. Ensure signatures are up to date and service is running.')
    }

    if ($recommendations.Count -eq 0) {
        $null = $recommendations.Add('System operating within expected parameters. Continue monitoring.')
    }

    return $recommendations
}

function Save-WsaM3Artifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ReportData,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$ResourceRoot
    )

    $outputPath = $Config.reports.output_path
    if (-not $outputPath) {
        $outputPath = Join-Path -Path $ResourceRoot -ChildPath 'output'
    }
    if (-not (Test-Path -Path $outputPath)) {
        New-Item -Path $outputPath -ItemType Directory -Force | Out-Null
    }

    $dateStamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $htmlPath = Join-Path -Path $outputPath -ChildPath ("health-report-$dateStamp.html")
    $jsonPath = Join-Path -Path $outputPath -ChildPath ("health-report-$dateStamp.json")
    $csvPath = Join-Path -Path $outputPath -ChildPath ("health-report-metrics-$dateStamp.csv")

    $templatePath = $Config.reports.html_template
    if (-not (Test-Path -Path $templatePath)) {
        throw "HTML template not found at '$templatePath'."
    }

    $template = Get-Content -Path $templatePath -Raw
    $template = $template.Replace('{{TITLE}}', $ReportData.Title)
    $template = $template.Replace('{{GENERATED_AT}}', $ReportData.GeneratedAt)
    $template = $template.Replace('{{HEALTH_SCORE}}', [string]$ReportData.HealthScore)
    $template = $template.Replace('{{SCORE_BADGE}}', $ReportData.ScoreBadge)
    $template = $template.Replace('{{ALERT_SUMMARY}}', $ReportData.AlertSummary)
    $template = $template.Replace('{{SECURITY_DAYS}}', [string]$ReportData.SecurityDays)

    $recommendationList = ''
    foreach ($rec in $ReportData.Recommendations) {
        $recommendationList += "<li>$rec</li>"
    }
    $template = $template.Replace('{{RECOMMENDATIONS_LIST}}', $recommendationList)

    $metricRows = ''
    foreach ($row in $ReportData.MetricsRows) {
        # FIXED: Added backticks to escape inner quotes for class attribute
        $metricRows += "<tr><td>$($row.Name)</td><td>$($row.Current)</td><td>$($row.PreviousDay)</td><td>$($row.PreviousWeek)</td><td class=`"$($row.StatusClass)`">$($row.StatusSymbol)</td></tr>"
    }
    $template = $template.Replace('{{METRIC_ROWS}}', $metricRows)

    $serviceRows = ''
    foreach ($svc in $ReportData.ServiceRows) {
        $serviceRows += "<tr><td>$($svc.Name)</td><td>$($svc.Status)</td><td>$($svc.StartType)</td><td>$($svc.Notes)</td></tr>"
    }
    $template = $template.Replace('{{SERVICE_ROWS}}', $serviceRows)

    $diskRows = ''
    foreach ($disk in $ReportData.DiskRows) {
        $diskRows += "<tr><td>$($disk.Name)</td><td>$($disk.TotalGB)</td><td>$($disk.UsedGB)</td><td>$($disk.FreeGB)</td><td>$($disk.UsagePercent)</td></tr>"
    }
    $template = $template.Replace('{{DISK_ROWS}}', $diskRows)

    $securityRows = ''
    foreach ($sec in $ReportData.SecurityRows) {
        $securityRows += "<tr><td>$($sec.Category)</td><td>$($sec.Count)</td></tr>"
    }
    $template = $template.Replace('{{SECURITY_ROWS}}', $securityRows)

    $trendJson = ($ReportData.TrendData | ConvertTo-Json -Compress)
    $template = $template.Replace('{{TREND_DATA_JSON}}', $trendJson)

    Set-Content -Path $htmlPath -Value $template -Encoding UTF8
    $ReportData.Raw | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

    $ReportData.MetricsRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

    if ($Config.reports.retain_reports) {
        Invoke-WsaReportRetention -OutputPath $outputPath -Retain $Config.reports.retain_reports
    }

    return [pscustomobject]@{
        Html = $htmlPath
        Json = $jsonPath
        Csv  = $csvPath
    }
}

function Invoke-WsaReportRetention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter(Mandatory)]
        [int]$Retain
    )

    $files = Get-ChildItem -Path $OutputPath -Filter 'health-report-*' | Sort-Object -Property LastWriteTime
    if ($files.Count -le $Retain) { return }
    $removeCount = $files.Count - $Retain
    for ($i = 0; $i -lt $removeCount; $i++) {
        Remove-Item -Path $files[$i].FullName -Force -ErrorAction SilentlyContinue
    }
}

function Send-WsaM3EmailReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $ReportData,

        [Parameter(Mandatory)]
        $Artifacts,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    if (-not $Config.email) { return }
    if (-not $Config.email.smtp_server) { return }

    $subject = $Config.email.subject
    if (-not $subject) { $subject = 'WinSysAuto Daily Health Report' }

    $body = Get-Content -Path $Artifacts.Html -Raw

    $params = @{
        SmtpServer = $Config.email.smtp_server
        Port       = if ($Config.email.smtp_port) { [int]$Config.email.smtp_port } else { 25 }
        From       = $Config.email.from
        To         = $Config.email.to -join ','
        Subject    = $subject
        Body       = $body
        BodyAsHtml = $true
    }

    if ($Config.email.use_ssl) {
        $params['UseSsl'] = $true
    }

    if ($Config.email.credential_target) {
        try {
            $cred = Get-StoredCredential -Target $Config.email.credential_target -ErrorAction Stop
            if ($cred) {
                $params['Credential'] = $cred
            }
        }
        catch {
            Write-WsaLog -Component 'M3' -Message 'Stored credential retrieval failed.' -Level 'WARN'
        }
    }

    try {
        Send-MailMessage @params
        Write-WsaLog -Component 'M3' -Message 'Email report sent successfully.' -Level 'INFO'
    }
    catch {
        Write-WsaLog -Component 'M3' -Message ("Failed to send email: {0}" -f $_.Exception.Message) -Level 'WARN'
    }
}

function Get-StoredCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target
    )

    try {
        return Get-Credential -Message "Enter credentials for $Target"
    }
    catch {
        return $null
    }
}

function Set-WsaM3ScheduledTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$ModuleRoot,

        [switch]$TestMode
    )

    $modulePath = Join-Path -Path $ModuleRoot -ChildPath 'WinSysAuto.psd1'
    $taskName = 'WinSysAuto-M3-Daily'

    # FIXED: Rewritten to use New-ScheduledTaskAction instead of over-escaped schtasks.exe command
    $commandScript = "Import-Module `'$modulePath`'; Invoke-WsaM3HealthReport -RunNow"
    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command `"$commandScript`""
    $trigger = New-ScheduledTaskTrigger -Daily -At '9:00AM'
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    if ($TestMode) {
        return @{ Task = $taskName; Action = $action; Trigger = $trigger }
    }

    try {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
        }
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -ErrorAction Stop | Out-Null
        Write-WsaLog -Component 'M3' -Message 'Scheduled task created or updated.' -Level 'INFO'
    }
    catch {
        Write-WsaLog -Component 'M3' -Message "Failed to create scheduled task: $($_.Exception.Message)" -Level 'ERROR'
        throw
    }

    return @{ Task = $taskName; Action = $action }
}

function Get-WsaM3HistoricalReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$StatePath
    )

    $snapshotsFile = Join-Path -Path $StatePath -ChildPath 'snapshots.json'
    if (-not (Test-Path -Path $snapshotsFile)) {
        throw 'No historical data available.'
    }

    $data = Get-Content -Path $snapshotsFile -Raw | ConvertFrom-Json -Depth 10
    return $data
}
