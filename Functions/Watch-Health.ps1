function Watch-Health {
    [CmdletBinding()]
    param(
        [int]$CpuThreshold = 90,
        [int]$SampleIntervalSeconds = 15,
        [int]$MaxSamples = 0
    )

    $toastCommand = Get-Command -Name 'New-BurntToastNotification' -ErrorAction SilentlyContinue
    $samplesTaken = 0

    while ($true) {
        if ($MaxSamples -gt 0 -and $samplesTaken -ge $MaxSamples) {
            break
        }

        $samplesTaken++

        $cpuUsage = $null
        try {
            $counterResult = Get-Counter -Counter '\\Processor(_Total)\\% Processor Time' -ErrorAction Stop
            if ($counterResult.CounterSamples.Count -gt 0) {
                $cpuUsage = [math]::Round($counterResult.CounterSamples[0].CookedValue, 2)
            }
        }
        catch {
            Write-Warning "Failed to read processor counters: $($_.Exception.Message)"
        }

        if ($cpuUsage -ne $null -and $cpuUsage -ge $CpuThreshold) {
            $message = "CPU utilisation is {0}% (threshold {1}%)." -f $cpuUsage, $CpuThreshold
            if ($toastCommand) {
                try {
                    & $toastCommand -Text 'WinSysAuto CPU Alert', $message | Out-Null
                }
                catch {
                    Write-Host $message
                }
            }
            else {
                Write-Host $message
            }
        }

        if ($MaxSamples -gt 0 -and $samplesTaken -ge $MaxSamples) {
            break
        }

        Start-Sleep -Seconds $SampleIntervalSeconds
    }
}
