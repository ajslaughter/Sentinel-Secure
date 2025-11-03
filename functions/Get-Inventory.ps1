function Invoke-InventoryCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [System.Management.Automation.PSCredential]
        $Credential,

        [switch]
        $IncludeApplications
    )

    $timestamp = Get-Date
    $credentialParameters = @{}
    if ($PSBoundParameters.ContainsKey('Credential') -and $Credential) {
        $credentialParameters['Credential'] = $Credential
    }

    $osInfo = $null
    $hardwareInfo = $null
    $applications = @()
    $errors = @()

    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ComputerName $ComputerName @credentialParameters -ErrorAction Stop
        if ($os) {
            $osInfo = [ordered]@{
                Caption        = $os.Caption
                Version        = $os.Version
                BuildNumber    = $os.BuildNumber
                LastBootUpTime = $os.LastBootUpTime
            }
        }
    }
    catch {
        $errors += "OperatingSystem: $($_.Exception.Message)"
    }

    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ComputerName $ComputerName @credentialParameters -ErrorAction Stop
        $bios = Get-CimInstance -ClassName Win32_BIOS -ComputerName $ComputerName @credentialParameters -ErrorAction Stop
        $hardwareInfo = [ordered]@{}
        if ($computerSystem) {
            $hardwareInfo['Manufacturer'] = $computerSystem.Manufacturer
            $hardwareInfo['Model'] = $computerSystem.Model
            $hardwareInfo['TotalPhysicalMemory'] = $computerSystem.TotalPhysicalMemory
            $hardwareInfo['NumberOfProcessors'] = $computerSystem.NumberOfProcessors
        }
        if ($bios) {
            $hardwareInfo['SerialNumber'] = $bios.SerialNumber
        }
    }
    catch {
        $errors += "Hardware: $($_.Exception.Message)"
    }

    if ($IncludeApplications.IsPresent) {
        try {
            $registryPaths = @(
                "Registry::\\$ComputerName\\HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*",
                "Registry::\\$ComputerName\\HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*"
            )

            foreach ($path in $registryPaths) {
                try {
                    if (Test-Path -Path $path) {
                        $applications += Get-ItemProperty -Path $path |
                            Where-Object { $_.DisplayName } |
                            ForEach-Object {
                                [pscustomobject]@{
                                    Name        = $_.DisplayName
                                    Version     = $_.DisplayVersion
                                    Publisher   = $_.Publisher
                                    InstallDate = $_.InstallDate
                                }
                            }
                    }
                }
                catch {
                    $errors += "Applications($path): $($_.Exception.Message)"
                }
            }
        }
        catch {
            $errors += "Applications: $($_.Exception.Message)"
        }
    }

    return [pscustomobject][ordered]@{
        ComputerName     = $ComputerName
        Timestamp        = $timestamp
        OperatingSystem  = $osInfo
        Hardware         = $hardwareInfo
        Applications     = if ($IncludeApplications.IsPresent) { $applications } else { $null }
        Errors           = if ($errors.Count) { $errors } else { $null }
    }
}

<#
.SYNOPSIS
Collects operating system, hardware, and optionally application inventory information from one or more computers.

.DESCRIPTION
The Get-Inventory function collects system inventory data from the specified computers using CIM and registry queries. The function can gather operating system and hardware information, and optionally retrieve installed application details. The operation runs in parallel on PowerShell 7 or later and falls back to a sequential run when parallelism is not available or disabled.

.PARAMETER ComputerName
Specifies one or more remote computer names to query. If omitted, the local computer name is used.

.PARAMETER Credential
Specifies the credential to use for remote CIM and registry queries.

.PARAMETER ThrottleLimit
Defines the maximum number of parallel inventory operations to execute at once. The default is 5.

.PARAMETER IncludeApplications
When present, installed application information is retrieved in addition to system and hardware details.

.EXAMPLE
PS> Get-Inventory -ComputerName 'Server01','Server02' -IncludeApplications

Collects inventory details, including installed applications, from two remote servers.

.EXAMPLE
PS> Get-Inventory -Credential (Get-Credential)

Collects operating system and hardware inventory from the local computer using the supplied credentials.

.NOTES
Requires PowerShell 7 or later for parallel execution; otherwise falls back to sequential processing.
#>
function Get-Inventory {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        [string[]]
        $ComputerName,

        [System.Management.Automation.PSCredential]
        $Credential,

        [int]
        $ThrottleLimit = 5,

        [switch]
        $IncludeApplications
    )

    begin {
        $collector = ${function:Invoke-InventoryCollection}.GetNewClosure()
        $parallelSupported = ($PSVersionTable.PSVersion.Major -ge 7) -and ((Get-Command ForEach-Object).Parameters.ContainsKey('Parallel'))
        $disableParallel = $env:WINSA_DISABLE_PARALLEL -eq '1'
        $targets = @()
    }

    process {
        if ($null -ne $ComputerName) {
            $targets += $ComputerName
        }
    }

    end {
        if (-not $targets.Count) {
            $targets = @($env:COMPUTERNAME)
        }

        $targets = $targets | Where-Object { $_ } | Select-Object -Unique

        $results = @()
        if ($parallelSupported -and -not $disableParallel) {
            $results = $targets | ForEach-Object -Parallel {
                param($collector, $credential, $includeApps)
                & $collector -ComputerName $_ -Credential $credential -IncludeApplications:$includeApps
            } -ThrottleLimit $ThrottleLimit -ArgumentList $collector, $Credential, $IncludeApplications
        }
        else {
            foreach ($target in $targets) {
                $results += & $collector -ComputerName $target -Credential $Credential -IncludeApplications:$IncludeApplications
            }
        }

        return $results
    }
}
