function Get-WsaDashboardData {
    <#
    .SYNOPSIS
        Collects current system metrics for the live dashboard in JSON format.

    .DESCRIPTION
        Fast-executing function that gathers CPU, memory, disk, service, and system metrics
        without external dependencies. Returns data formatted for the live dashboard.

    .EXAMPLE
        Get-WsaDashboardData
        Returns live system metrics as a PowerShell object.

    .EXAMPLE
        Get-WsaDashboardData | ConvertTo-Json
        Returns live system metrics as JSON.

    .NOTES
        Designed to execute quickly for real-time dashboard updates.
        Works on any Windows system without additional modules.
    #>
    [CmdletBinding()]
    param()

    # Default thresholds
    $thresholds = @{
        cpu = @{ warning = 70; critical = 90 }
        memory = @{ warning = 75; critical = 90 }
        disk = @{ warning = 80; critical = 95 }
    }

    # Critical services to monitor (common across Windows systems)
    $criticalServices = @('LanmanServer', 'LanmanWorkstation', 'EventLog', 'W32Time')

    # Add domain-specific services if domain-joined
    $config = Get-WsaConfig
    if ($config.isDomainController) {
        $criticalServices += @('NTDS', 'Netlogon', 'DNS', 'DFSR')
    }
    if ($config.hasDhcpModule) {
        $criticalServices += @('Dhcp')
    }
    if ($config.hasDnsModule) {
        $criticalServices += @('DNS')
    }

    # Collect CPU metrics
    try {
        $cpuCounter = Get-Counter -Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
        $cpuTotal = [math]::Round($cpuCounter.CounterSamples[0].CookedValue, 2)
    }
    catch {
        $cpuTotal = 0
    }

    # Collect per-core CPU (simplified - just show total for now)
    $processorCount = (Get-WmiObject -Class Win32_Processor).NumberOfLogicalProcessors
    $cpuPerCore = @()
    for ($i = 0; $i -lt $processorCount; $i++) {
        $cpuPerCore += $cpuTotal  # Simplified - would need individual core counters for accuracy
    }

    # Collect memory metrics
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        $totalMemoryGB = [math]::Round($computerSystem.TotalPhysicalMemory / 1GB, 2)
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedMemoryGB = [math]::Round($totalMemoryGB - $freeMemoryGB, 2)
        $memoryPercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 2)
    }
    catch {
        $totalMemoryGB = 0
        $freeMemoryGB = 0
        $usedMemoryGB = 0
        $memoryPercent = 0
    }

    # Collect disk metrics
    $diskData = @()
    try {
        $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -or $_.Free }
        foreach ($drive in $drives) {
            $totalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
            $usedGB = [math]::Round($drive.Used / 1GB, 2)
            $freeGB = [math]::Round($drive.Free / 1GB, 2)
            $usagePercent = if ($totalGB -gt 0) {
                [math]::Round(($usedGB / $totalGB) * 100, 2)
            } else { 0 }

            $diskData += @{
                name = $drive.Name + ":"
                totalGB = $totalGB
                usedGB = $usedGB
                freeGB = $freeGB
                usagePercent = $usagePercent
            }
        }
    }
    catch {
        # Fallback to WMI
        $disks = Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3"
        foreach ($disk in $disks) {
            $totalGB = [math]::Round($disk.Size / 1GB, 2)
            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $usedGB = [math]::Round($totalGB - $freeGB, 2)
            $usagePercent = if ($totalGB -gt 0) {
                [math]::Round(($usedGB / $totalGB) * 100, 2)
            } else { 0 }

            $diskData += @{
                name = $disk.DeviceID
                totalGB = $totalGB
                usedGB = $usedGB
                freeGB = $freeGB
                usagePercent = $usagePercent
            }
        }
    }

    # Collect service health
    $serviceData = @()
    foreach ($svcName in $criticalServices) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction SilentlyContinue
            if ($svc) {
                $status = 'healthy'
                if ($svc.Status -ne 'Running') {
                    $status = 'critical'
                }
                $serviceData += @{
                    name = $svc.DisplayName
                    status = $svc.Status.ToString()
                    startType = $svc.StartType.ToString()
                    health = $status
                }
            }
        }
        catch {
            # Service not found, skip
        }
    }

    # Collect event log metrics (last 24 hours)
    $failedLogons = 0
    $systemErrors = 0
    $applicationErrors = 0
    try {
        # Failed logons (Event ID 4625)
        $failedLogonEvents = Get-WinEvent -FilterHashtable @{
            LogName = 'Security'
            Id = 4625
            StartTime = (Get-Date).AddHours(-24)
        } -ErrorAction SilentlyContinue
        $failedLogons = if ($failedLogonEvents) { $failedLogonEvents.Count } else { 0 }
    }
    catch {
        # Security log might not be accessible
    }

    try {
        # System errors
        $sysErrors = Get-WinEvent -FilterHashtable @{
            LogName = 'System'
            Level = 2
            StartTime = (Get-Date).AddHours(-24)
        } -ErrorAction SilentlyContinue
        $systemErrors = if ($sysErrors) { $sysErrors.Count } else { 0 }
    }
    catch {
        # Errors reading event log
    }

    try {
        # Application errors
        $appErrors = Get-WinEvent -FilterHashtable @{
            LogName = 'Application'
            Level = 2
            StartTime = (Get-Date).AddHours(-24)
        } -ErrorAction SilentlyContinue
        $applicationErrors = if ($appErrors) { $appErrors.Count } else { 0 }
    }
    catch {
        # Errors reading event log
    }

    # System uptime
    try {
        $uptime = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
        $uptimeDays = [math]::Round($uptime.TotalDays, 2)
    }
    catch {
        $uptimeDays = 0
    }

    # Process count
    try {
        $processCount = (Get-Process).Count
    }
    catch {
        $processCount = 0
    }

    # Pending reboot detection
    $pendingReboot = $false
    try {
        $cbsRebootPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        $wuRebootPending = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        $pendingReboot = $cbsRebootPending -or $wuRebootPending
    }
    catch {
        # Can't determine
    }

    # Firewall status
    $firewallEnabled = $false
    try {
        $fwProfile = Get-NetFirewallProfile -Profile Domain -ErrorAction SilentlyContinue
        $firewallEnabled = $fwProfile.Enabled
    }
    catch {
        # Can't determine
    }

    # Calculate health score and alerts
    $alerts = @()
    $healthScore = 100

    # CPU checks
    if ($cpuTotal -ge $thresholds.cpu.critical) {
        $healthScore -= 15
        $alerts += @{
            metric = 'CPU'
            level = 'critical'
            message = "CPU usage is critical: $cpuTotal%"
        }
    }
    elseif ($cpuTotal -ge $thresholds.cpu.warning) {
        $healthScore -= 5
        $alerts += @{
            metric = 'CPU'
            level = 'warning'
            message = "CPU usage is high: $cpuTotal%"
        }
    }

    # Memory checks
    if ($memoryPercent -ge $thresholds.memory.critical) {
        $healthScore -= 15
        $alerts += @{
            metric = 'Memory'
            level = 'critical'
            message = "Memory usage is critical: $memoryPercent%"
        }
    }
    elseif ($memoryPercent -ge $thresholds.memory.warning) {
        $healthScore -= 5
        $alerts += @{
            metric = 'Memory'
            level = 'warning'
            message = "Memory usage is high: $memoryPercent%"
        }
    }

    # Disk checks
    foreach ($disk in $diskData) {
        if ($disk.usagePercent -ge $thresholds.disk.critical) {
            $healthScore -= 10
            $alerts += @{
                metric = "Disk $($disk.name)"
                level = 'critical'
                message = "Disk $($disk.name) is critically full: $($disk.usagePercent)%"
            }
        }
        elseif ($disk.usagePercent -ge $thresholds.disk.warning) {
            $healthScore -= 5
            $alerts += @{
                metric = "Disk $($disk.name)"
                level = 'warning'
                message = "Disk $($disk.name) is filling up: $($disk.usagePercent)%"
            }
        }
    }

    # Service checks
    foreach ($svc in $serviceData) {
        if ($svc.health -eq 'critical') {
            $healthScore -= 10
            $alerts += @{
                metric = 'Service'
                level = 'critical'
                message = "Critical service not running: $($svc.name)"
            }
        }
    }

    # Failed logon checks
    if ($failedLogons -ge 25) {
        $healthScore -= 10
        $alerts += @{
            metric = 'Security'
            level = 'critical'
            message = "High number of failed logons: $failedLogons"
        }
    }
    elseif ($failedLogons -ge 10) {
        $healthScore -= 5
        $alerts += @{
            metric = 'Security'
            level = 'warning'
            message = "Elevated failed logon attempts: $failedLogons"
        }
    }

    # Ensure health score doesn't go below 0
    if ($healthScore -lt 0) { $healthScore = 0 }

    # Determine overall health status
    $healthStatus = 'healthy'
    if ($healthScore -lt 70) {
        $healthStatus = 'critical'
    }
    elseif ($healthScore -lt 90) {
        $healthStatus = 'warning'
    }

    # Build response object
    $data = [ordered]@{
        timestamp = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        healthScore = $healthScore
        healthStatus = $healthStatus
        cpu = @{
            total = $cpuTotal
            perCore = $cpuPerCore
        }
        memory = @{
            percent = $memoryPercent
            usedGB = $usedMemoryGB
            totalGB = $totalMemoryGB
        }
        disk = $diskData
        services = $serviceData
        events = @{
            failedLogons = $failedLogons
            systemErrors = $systemErrors
            applicationErrors = $applicationErrors
        }
        system = @{
            uptimeDays = $uptimeDays
            processCount = $processCount
            pendingReboot = $pendingReboot
            firewall = $firewallEnabled
        }
        alerts = $alerts
    }

    return [pscustomobject]$data
}
