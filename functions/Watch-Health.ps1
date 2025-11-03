function Watch-Health {
    <#
    .SYNOPSIS
        Monitor CPU, memory, disk and Windows service health with toast notifications.

    .DESCRIPTION
        Polls performance counters via Get-Counter and service state via Get-Service. Threshold
        violations raise BurntToast notifications when the module is installed. The function can
        run interactively or as a background job and supports graceful cancellation (Ctrl+C or
        Stop-Job).

    .PARAMETER CpuThreshold
        Percentage utilisation of the "\Processor(_Total)\% Processor Time" counter that will
        raise an alert.

    .PARAMETER MemoryThreshold
        Percentage utilisation of the "\Memory\% Committed Bytes In Use" counter that will raise
        an alert.

    .PARAMETER DiskFreeThreshold
        Percentage of free space reported by the "\LogicalDisk(_Total)\% Free Space" counter below
        which an alert is raised.

    .PARAMETER Services
        Names of Windows services that must remain in the Running state.

    .PARAMETER IntervalSeconds
        Number of seconds between samples.

    .PARAMETER MaxIterations
        Limits the number of polling iterations. Useful for automation and unit testing.

    .PARAMETER AsJob
        Run the watcher in a PowerShell background job.

    .PARAMETER SuppressNotifications
        Disable toast notifications (warnings are still emitted).

    .EXAMPLE
        Watch-Health -Services 'LanmanServer','W32Time' -CpuThreshold 85 -MemoryThreshold 85

        Monitors the selected counters and services, emitting BurntToast notifications when the
        thresholds are breached. If the BurntToast module is not installed a warning is displayed
        explaining how to add it: Install-Module -Name BurntToast -Scope CurrentUser.
    #>
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$CpuThreshold = 80,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$MemoryThreshold = 80,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]$DiskFreeThreshold = 15,

        [Parameter()]
        [string[]]$Services = @(),

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]$IntervalSeconds = 30,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxIterations = [int]::MaxValue,

        [Parameter()]
        [switch]$AsJob,

        [Parameter()]
        [switch]$SuppressNotifications
    )

    if ($AsJob.IsPresent) {
        $jobParameters = @{}
        foreach ($key in $PSBoundParameters.Keys) {
            if ($key -ne 'AsJob') {
                $jobParameters[$key] = $PSBoundParameters[$key]
            }
        }

        return Start-Job -Name 'Watch-Health' -ScriptBlock {
            param($functionBlock, $boundParameters)
            & $functionBlock @boundParameters
        } -ArgumentList @(${function:Watch-Health}, $jobParameters)
    }

    $burntToastAvailable = $false
    $burntToastCommand = 'New-BurntToastNotification'

    try {
        $module = Get-Module -Name BurntToast -ListAvailable | Select-Object -First 1
        if ($null -ne $module) {
            Import-Module -Name BurntToast -ErrorAction Stop | Out-Null
            $burntToastAvailable = $true
        }
        else {
            Write-Verbose 'BurntToast module not found. Install with: Install-Module -Name BurntToast -Scope CurrentUser.'
        }
    }
    catch {
        Write-Warning "Failed to import BurntToast: $($_.Exception.Message)"
    }

    function Send-HealthNotification {
        param (
            [Parameter(Mandatory = $true)]
            [string]$Title,

            [Parameter(Mandatory = $true)]
            [string]$Message
        )

        if ($SuppressNotifications.IsPresent) {
            Write-Verbose "Notification suppressed: $Title - $Message"
            return
        }

        if ($burntToastAvailable -and (Get-Command -Name $burntToastCommand -ErrorAction SilentlyContinue)) {
            try {
                & $burntToastCommand -Text $Title, $Message -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Warning "Failed to send BurntToast notification: $($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "$Title - $Message"
        }
    }

    $counterPaths = @(
        '\Processor(_Total)\% Processor Time',
        '\Memory\% Committed Bytes In Use'
    )

    $diskCounterPath = '\LogicalDisk(_Total)\% Free Space'

    $iteration = 0

    while ($iteration -lt $MaxIterations) {
        if ($PSCmdlet.Stopping) {
            break
        }

        $iteration++

        try {
            $counterSamples = (Get-Counter -Counter $counterPaths -ErrorAction Stop).CounterSamples
        }
        catch {
            Write-Warning "Failed to query performance counters: $($_.Exception.Message)"
            $counterSamples = @()
        }

        $cpuUsage = $null
        $memoryUsage = $null

        foreach ($sample in $counterSamples) {
            switch ($sample.Path) {
                { $_ -eq $counterPaths[0] -or $_ -eq $counterPaths[0].TrimStart('\') } { $cpuUsage = [math]::Round([double]$sample.CookedValue, 2); continue }
                { $_ -eq $counterPaths[1] -or $_ -eq $counterPaths[1].TrimStart('\') } { $memoryUsage = [math]::Round([double]$sample.CookedValue, 2); continue }
            }
        }

        if ($null -ne $cpuUsage -and $cpuUsage -ge $CpuThreshold) {
            Send-HealthNotification -Title 'CPU utilisation alert' -Message "CPU usage is at $cpuUsage% (threshold $CpuThreshold%)"
        }

        if ($null -ne $memoryUsage -and $memoryUsage -ge $MemoryThreshold) {
            Send-HealthNotification -Title 'Memory utilisation alert' -Message "Memory usage is at $memoryUsage% (threshold $MemoryThreshold%)"
        }

        try {
            $diskSample = (Get-Counter -Counter $diskCounterPath -ErrorAction Stop).CounterSamples | Select-Object -First 1
            if ($null -ne $diskSample) {
                $diskFree = [math]::Round([double]$diskSample.CookedValue, 2)
                if ($diskFree -le $DiskFreeThreshold) {
                    Send-HealthNotification -Title 'Disk free space alert' -Message "Logical disks free space is at $diskFree% (threshold $DiskFreeThreshold%)"
                }
            }
        }
        catch {
            Write-Warning "Failed to query disk counter: $($_.Exception.Message)"
        }

        foreach ($serviceName in $Services) {
            try {
                $service = Get-Service -Name $serviceName -ErrorAction Stop
                if ($service.Status -ne 'Running') {
                    Send-HealthNotification -Title 'Service state alert' -Message "Service '$($service.Name)' is $($service.Status)"
                }
            }
            catch {
                Send-HealthNotification -Title 'Service state alert' -Message "Service '$serviceName' not found: $($_.Exception.Message)"
            }
        }

        if ($iteration -ge $MaxIterations) {
            break
        }

        for ($elapsed = 0; $elapsed -lt $IntervalSeconds; $elapsed++) {
            if ($PSCmdlet.Stopping) {
                break 2
            }
            Start-Sleep -Seconds 1
        }
    }
}
