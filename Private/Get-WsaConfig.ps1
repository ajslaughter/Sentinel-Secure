function Get-WsaConfig {
    <#
    .SYNOPSIS
        Retrieves the WinSysAuto environment configuration.

    .DESCRIPTION
        Loads the configuration file created by Initialize-WsaEnvironment.
        If the configuration doesn't exist, returns a default configuration
        with minimal settings.

    .PARAMETER ConfigPath
        Custom path to the configuration file. Defaults to $env:ProgramData\WinSysAuto\config.json

    .PARAMETER ErrorIfMissing
        Throw an error if the configuration file doesn't exist.

    .EXAMPLE
        Get-WsaConfig
        Retrieves the current environment configuration.

    .OUTPUTS
        PSCustomObject with environment configuration.
    #>
    [CmdletBinding()]
    param(
        [string]$ConfigPath,

        [switch]$ErrorIfMissing
    )

    # Determine config path
    if (-not $ConfigPath) {
        $configRoot = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto'
        $ConfigPath = Join-Path -Path $configRoot -ChildPath 'config.json'
    }

    # Check if config exists
    if (-not (Test-Path -Path $ConfigPath)) {
        if ($ErrorIfMissing) {
            throw "WinSysAuto configuration not found at $ConfigPath. Run Initialize-WsaEnvironment first."
        }

        Write-Verbose "Configuration file not found at $ConfigPath. Using default configuration."

        # Return default configuration
        return [PSCustomObject]@{
            initialized = $null
            computerName = $env:COMPUTERNAME
            isDomainController = $false
            isDomainJoined = $false
            hasAdModule = $false
            hasDhcpModule = $false
            hasDnsModule = $false
            paths = @{
                reports = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\Reports'
                backups = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\Backups'
                logs = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\Logs'
            }
        }
    }

    # Load and return config
    try {
        $config = Get-Content -Path $ConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json
        Write-Verbose "Loaded configuration from $ConfigPath"
        return $config
    }
    catch {
        if ($ErrorIfMissing) {
            throw "Failed to load configuration from $ConfigPath: $($_.Exception.Message)"
        }

        Write-Warning "Failed to load configuration from $ConfigPath. Using default configuration."
        return [PSCustomObject]@{
            initialized = $null
            computerName = $env:COMPUTERNAME
            isDomainController = $false
            isDomainJoined = $false
            hasAdModule = $false
            hasDhcpModule = $false
            hasDnsModule = $false
            paths = @{
                reports = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\Reports'
                backups = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\Backups'
                logs = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\Logs'
            }
        }
    }
}
