function Write-WsaLog {
    <#
    .SYNOPSIS
        Writes a structured log entry to the WinSysAuto log file.

    .DESCRIPTION
        Creates JSON-formatted log entries with timestamp, level, component, and message.
        Uses the log path from Get-WsaConfig or falls back to a default location.

    .PARAMETER Component
        The component or function name generating the log entry.

    .PARAMETER Message
        The log message to write.

    .PARAMETER Level
        The severity level: INFO, WARN, ERROR, or DEBUG.

    .EXAMPLE
        Write-WsaLog -Component 'MyFunction' -Message 'Starting operation' -Level 'INFO'

    .NOTES
        Logs are written to $env:ProgramData\WinSysAuto\Logs by default.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO','WARN','ERROR','DEBUG')]
        [string]$Level = 'INFO'
    )

    try {
        # Get log path from config
        $config = Get-WsaConfig
        $logRoot = $config.paths.logs

        # Ensure log directory exists
        if (-not (Test-Path -Path $logRoot)) {
            New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
        }

        $dateStamp = Get-Date -Format 'yyyyMMdd'
        $logFile = Join-Path -Path $logRoot -ChildPath ("WinSysAuto-{0}.log" -f $dateStamp)

        $entry = [pscustomobject]@{
            Timestamp = (Get-Date).ToString('s')
            Level     = $Level
            Component = $Component
            Message   = $Message
        }

        $json = $entry | ConvertTo-Json -Depth 3 -Compress
        Add-Content -Path $logFile -Value $json
        Write-Verbose -Message ("[{0}] {1}: {2}" -f $Level, $Component, $Message)
    }
    catch {
        Write-Verbose -Message ("[WARN] {0}: Failed to write log entry. {1}" -f $Component, $_.Exception.Message)
    }
}
