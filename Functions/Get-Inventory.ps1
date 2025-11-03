function Get-Inventory {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [string]$ComputerName = $env:COMPUTERNAME
    )

    process {
        try {
            $os = Get-CimInstance -ClassName 'Win32_OperatingSystem' -ComputerName $ComputerName -ErrorAction Stop
            $processors = Get-CimInstance -ClassName 'Win32_Processor' -ComputerName $ComputerName -ErrorAction Stop
            $disks = Get-CimInstance -ClassName 'Win32_LogicalDisk' -Filter "DriveType=3" -ComputerName $ComputerName -ErrorAction SilentlyContinue
        }
        catch {
            throw
        }

        $memoryGb = if ($os.TotalVisibleMemorySize) {
            [math]::Round(($os.TotalVisibleMemorySize / 1MB), 2)
        }
        else {
            $null
        }

        $uptime = $null
        if ($os.PSObject.Properties['LastBootUpTime'] -and $null -ne $os.LastBootUpTime) {
            $uptime = (Get-Date) - $os.LastBootUpTime
        }

        $processorSummary = @()
        foreach ($processor in $processors) {
            $processorSummary += [pscustomobject]@{
                Name                      = $processor.Name
                NumberOfCores             = $processor.NumberOfCores
                NumberOfLogicalProcessors = $processor.NumberOfLogicalProcessors
                MaxClockSpeedMHz          = $processor.MaxClockSpeed
            }
        }

        $diskSummary = @()
        foreach ($disk in $disks) {
            $sizeGb = $null
            $freeGb = $null
            $percentFree = $null

            if ($disk.Size -and $disk.Size -gt 0) {
                $sizeGb = [math]::Round(($disk.Size / 1GB), 2)
                $freeGb = [math]::Round(($disk.FreeSpace / 1GB), 2)
                $percentFree = if ($disk.FreeSpace -ne $null) {
                    [math]::Round((($disk.FreeSpace / $disk.Size) * 100), 2)
                }
                else {
                    $null
                }
            }

            $diskSummary += [pscustomobject]@{
                Name        = $disk.DeviceID
                SizeGB      = $sizeGb
                FreeGB      = $freeGb
                PercentFree = $percentFree
            }
        }

        $patches = @()
        try {
            $patches = Get-HotFix -ComputerName $ComputerName -ErrorAction Stop | Sort-Object -Property InstalledOn -Descending | Select-Object -First 5
        }
        catch {
            $patches = @()
        }

        $patchSummary = @()
        foreach ($patch in $patches) {
            $patchSummary += [pscustomobject]@{
                HotFixID    = $patch.HotFixID
                InstalledOn = $patch.InstalledOn
                Description = $patch.Description
            }
        }

        [pscustomobject]@{
            ComputerName    = $ComputerName
            OperatingSystem = [pscustomobject]@{
                Caption     = $os.Caption
                Version     = $os.Version
                BuildNumber = $os.BuildNumber
            }
            MemoryGB        = $memoryGb
            Uptime          = $uptime
            Processors      = $processorSummary
            Disks           = $diskSummary
            Last5Patches    = $patchSummary
        }
    }
}
