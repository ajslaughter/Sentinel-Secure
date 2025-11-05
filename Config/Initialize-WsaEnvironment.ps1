function Initialize-WsaEnvironment {
    <#
    .SYNOPSIS
        Auto-detects the Windows domain environment and creates a configuration file.

    .DESCRIPTION
        Detects the current domain, domain controllers, DHCP servers, DNS servers, and
        network interfaces. Saves the configuration to $env:ProgramData\WinSysAuto\config.json
        for use by other WinSysAuto functions. Can also be run manually to reconfigure.

    .PARAMETER Force
        Force re-initialization even if a config file already exists.

    .PARAMETER ConfigPath
        Custom path for the configuration file. Defaults to $env:ProgramData\WinSysAuto\config.json

    .EXAMPLE
        Initialize-WsaEnvironment
        Auto-detects the environment and creates the config file.

    .EXAMPLE
        Initialize-WsaEnvironment -Force
        Re-initializes the environment configuration.

    .OUTPUTS
        PSCustomObject with environment detection results.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$Force,

        [string]$ConfigPath
    )

    $component = 'Initialize-WsaEnvironment'

    # Determine config path
    if (-not $ConfigPath) {
        $configRoot = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto'
        $ConfigPath = Join-Path -Path $configRoot -ChildPath 'config.json'
    }
    else {
        $configRoot = Split-Path -Path $ConfigPath -Parent
    }

    # Check if config already exists
    if ((Test-Path -Path $ConfigPath) -and -not $Force) {
        Write-Verbose "Configuration already exists at $ConfigPath. Use -Force to reinitialize."
        $existingConfig = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        return New-WsaResult -Status 'Compliant' -Findings @("Configuration already exists at $ConfigPath") -Data @{ Config = $existingConfig }
    }

    $changes = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]

    Write-Host "Initializing WinSysAuto environment..." -ForegroundColor Cyan
    Write-Verbose "Detecting environment configuration..."

    # Create config directory
    if (-not (Test-Path -Path $configRoot)) {
        if ($PSCmdlet.ShouldProcess($configRoot, 'Create configuration directory')) {
            try {
                New-Item -Path $configRoot -ItemType Directory -Force | Out-Null
                $changes.Add("Created config directory: $configRoot") | Out-Null
            }
            catch {
                $msg = "Failed to create config directory: $($_.Exception.Message)"
                $findings.Add($msg) | Out-Null
                throw $msg
            }
        }
    }

    # Detect environment
    $config = @{
        initialized = (Get-Date -Format 's')
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

    # Detect domain membership
    try {
        $computerSystem = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        if ($computerSystem.PartOfDomain) {
            $config.isDomainJoined = $true
            $config.domain = $computerSystem.Domain
            Write-Host "  Domain: $($config.domain)" -ForegroundColor Green
            $findings.Add("Domain detected: $($config.domain)") | Out-Null
        }
        else {
            $config.isDomainJoined = $false
            Write-Host "  Not domain-joined (workgroup mode)" -ForegroundColor Yellow
            $findings.Add("Computer is not domain-joined") | Out-Null
        }
    }
    catch {
        $msg = "Failed to detect domain membership: $($_.Exception.Message)"
        Write-Host "  $msg" -ForegroundColor Yellow
        $findings.Add($msg) | Out-Null
    }

    # Detect if this is a domain controller
    try {
        $dcDiag = Get-Service -Name NTDS -ErrorAction SilentlyContinue
        if ($dcDiag -and $dcDiag.Status -eq 'Running') {
            $config.isDomainController = $true
            Write-Host "  Role: Domain Controller" -ForegroundColor Green
        }
        else {
            Write-Host "  Role: Member Server/Workstation" -ForegroundColor Green
        }
    }
    catch {
        # Not a DC, which is fine
    }

    # Detect Active Directory module
    $config.hasAdModule = $null -ne (Get-Module -Name ActiveDirectory -ListAvailable -ErrorAction SilentlyContinue)
    if ($config.hasAdModule) {
        Write-Host "  ActiveDirectory module: Available" -ForegroundColor Green

        # Get domain details if AD module is available and domain-joined
        if ($config.isDomainJoined) {
            try {
                $adDomain = Get-ADDomain -ErrorAction Stop
                $config.domainDN = $adDomain.DistinguishedName
                $config.domainNetBIOS = $adDomain.NetBIOSName
                $config.domainFQDN = $adDomain.DNSRoot

                $adForest = Get-ADForest -ErrorAction Stop
                $config.forestName = $adForest.Name
                $config.domainControllers = @($adForest.GlobalCatalogs)

                Write-Host "  Domain DN: $($config.domainDN)" -ForegroundColor Green
                Write-Host "  Domain Controllers: $($config.domainControllers.Count) found" -ForegroundColor Green
            }
            catch {
                $msg = "AD module available but failed to query domain: $($_.Exception.Message)"
                Write-Host "  $msg" -ForegroundColor Yellow
                $findings.Add($msg) | Out-Null
            }
        }
    }
    else {
        Write-Host "  ActiveDirectory module: Not available" -ForegroundColor Yellow
        $findings.Add("ActiveDirectory module not available - some functions will be limited") | Out-Null
    }

    # Detect DHCP module and servers
    $config.hasDhcpModule = $null -ne (Get-Module -Name DhcpServer -ListAvailable -ErrorAction SilentlyContinue)
    if ($config.hasDhcpModule) {
        Write-Host "  DhcpServer module: Available" -ForegroundColor Green
        try {
            $dhcpScopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if ($dhcpScopes) {
                $config.dhcpScopes = @($dhcpScopes | ForEach-Object {
                    @{
                        ScopeId = $_.ScopeId.ToString()
                        Name = $_.Name
                        StartRange = $_.StartRange.ToString()
                        EndRange = $_.EndRange.ToString()
                    }
                })
                Write-Host "  DHCP Scopes: $($dhcpScopes.Count) found" -ForegroundColor Green
            }
        }
        catch {
            # Not a DHCP server, which is fine
        }
    }
    else {
        Write-Host "  DhcpServer module: Not available" -ForegroundColor Yellow
    }

    # Detect DNS module
    $config.hasDnsModule = $null -ne (Get-Module -Name DnsServer -ListAvailable -ErrorAction SilentlyContinue)
    if ($config.hasDnsModule) {
        Write-Host "  DnsServer module: Available" -ForegroundColor Green
        try {
            $dnsForwarders = Get-DnsServerForwarder -ErrorAction SilentlyContinue
            if ($dnsForwarders) {
                $config.dnsForwarders = @($dnsForwarders.IPAddress.IPAddressToString)
                Write-Host "  DNS Forwarders: $($config.dnsForwarders.Count) configured" -ForegroundColor Green
            }
        }
        catch {
            # Not a DNS server, which is fine
        }
    }
    else {
        Write-Host "  DnsServer module: Not available" -ForegroundColor Yellow
    }

    # Detect network interfaces
    try {
        $networkAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1
        if ($networkAdapters) {
            $ipConfig = Get-NetIPAddress -InterfaceIndex $networkAdapters.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
            if ($ipConfig) {
                $config.primaryIP = $ipConfig.IPAddress
                $config.subnetMask = $ipConfig.PrefixLength
                Write-Host "  Primary IP: $($config.primaryIP)/$($config.subnetMask)" -ForegroundColor Green
            }
        }
    }
    catch {
        $msg = "Failed to detect network configuration: $($_.Exception.Message)"
        Write-Host "  $msg" -ForegroundColor Yellow
        $findings.Add($msg) | Out-Null
    }

    # Create necessary directories
    foreach ($path in $config.paths.Values) {
        if (-not (Test-Path -Path $path)) {
            try {
                New-Item -Path $path -ItemType Directory -Force | Out-Null
                $changes.Add("Created directory: $path") | Out-Null
            }
            catch {
                $msg = "Failed to create directory $path: $($_.Exception.Message)"
                $findings.Add($msg) | Out-Null
            }
        }
    }

    # Save configuration
    if ($PSCmdlet.ShouldProcess($ConfigPath, 'Save environment configuration')) {
        try {
            $config | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force
            $changes.Add("Saved configuration to $ConfigPath") | Out-Null
            Write-Host "`nConfiguration saved to: $ConfigPath" -ForegroundColor Cyan
            Write-Host "WinSysAuto is ready to use!" -ForegroundColor Green
        }
        catch {
            $msg = "Failed to save configuration: $($_.Exception.Message)"
            Write-Host "  ERROR: $msg" -ForegroundColor Red
            $findings.Add($msg) | Out-Null
            throw $msg
        }
    }

    $status = if ($changes.Count -gt 0) { 'Changed' } else { 'Compliant' }
    return New-WsaResult -Status $status -Changes $changes.ToArray() -Findings $findings.ToArray() -Data @{ Config = $config; ConfigPath = $ConfigPath }
}
