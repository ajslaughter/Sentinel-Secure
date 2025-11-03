function Export-InventoryReport {
    [CmdletBinding()]
    param(
        [string]$ComputerName = $env:COMPUTERNAME,
        [string]$OutputDirectory = 'C:\\Reports'
    )

    $inventory = Get-Inventory -ComputerName $ComputerName

    if (-not (Test-Path -Path $OutputDirectory)) {
        New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    }

    $reportPath = Join-Path -Path $OutputDirectory -ChildPath ("{0}-Inventory.html" -f $ComputerName)

    $processorLines = if ($inventory.Processors -and $inventory.Processors.Count -gt 0) {
        ($inventory.Processors | ForEach-Object {
            "<tr><td>$($_.Name)</td><td>$($_.NumberOfCores)</td><td>$($_.NumberOfLogicalProcessors)</td><td>$($_.MaxClockSpeedMHz)</td></tr>"
        }) -join [Environment]::NewLine
    }
    else {
        '<tr><td colspan="4">No processor data</td></tr>'
    }

    $diskLines = if ($inventory.Disks -and $inventory.Disks.Count -gt 0) {
        ($inventory.Disks | ForEach-Object {
            "<tr><td>$($_.Name)</td><td>$($_.SizeGB)</td><td>$($_.FreeGB)</td><td>$($_.PercentFree)</td></tr>"
        }) -join [Environment]::NewLine
    }
    else {
        '<tr><td colspan="4">No disk data</td></tr>'
    }

    $patchLines = if ($inventory.Last5Patches -and $inventory.Last5Patches.Count -gt 0) {
        ($inventory.Last5Patches | ForEach-Object {
            "<tr><td>$($_.HotFixID)</td><td>$($_.InstalledOn)</td><td>$($_.Description)</td></tr>"
        }) -join [Environment]::NewLine
    }
    else {
        '<tr><td colspan="3">No patch data</td></tr>'
    }

    $uptimeDisplay = if ($inventory.Uptime) {
        [System.String]::Format('{0:dd\:hh\:mm}', $inventory.Uptime)
    }
    else {
        'Unknown'
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <title>WinSysAuto Inventory Report</title>
    <style>
        body { font-family: Segoe UI, Arial, sans-serif; margin: 20px; }
        h1 { font-size: 20px; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th, td { border: 1px solid #666; padding: 6px; text-align: left; }
        th { background-color: #eaeaea; }
    </style>
</head>
<body>
    <h1>Inventory report for $ComputerName</h1>
    <h2>Operating system</h2>
    <p><strong>Caption:</strong> $($inventory.OperatingSystem.Caption)<br />
       <strong>Version:</strong> $($inventory.OperatingSystem.Version)<br />
       <strong>Build:</strong> $($inventory.OperatingSystem.BuildNumber)<br />
       <strong>Memory (GB):</strong> $($inventory.MemoryGB)<br />
       <strong>Uptime (dd:hh:mm):</strong> $uptimeDisplay
    </p>
    <h2>Processors</h2>
    <table>
        <thead>
            <tr><th>Name</th><th>Cores</th><th>Logical</th><th>Max MHz</th></tr>
        </thead>
        <tbody>
            $processorLines
        </tbody>
    </table>
    <h2>Disks</h2>
    <table>
        <thead>
            <tr><th>Name</th><th>Size (GB)</th><th>Free (GB)</th><th>Percent Free</th></tr>
        </thead>
        <tbody>
            $diskLines
        </tbody>
    </table>
    <h2>Recent patches</h2>
    <table>
        <thead>
            <tr><th>KB</th><th>Installed On</th><th>Description</th></tr>
        </thead>
        <tbody>
            $patchLines
        </tbody>
    </table>
</body>
</html>
"@

    Set-Content -Path $reportPath -Value $html -Encoding UTF8

    $notepad = Get-Command -Name 'notepad.exe' -ErrorAction SilentlyContinue
    if ($notepad) {
        try {
            Start-Process -FilePath $notepad.Source -ArgumentList $reportPath -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Host "Report saved to $reportPath"
        }
    }
    else {
        Write-Host "Report saved to $reportPath"
    }

    return $reportPath
}
