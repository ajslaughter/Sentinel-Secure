<#
.SYNOPSIS
    Performs a Windows Update scan and returns pending updates.

.DESCRIPTION
    Invoke-PatchScan inspects the target computer for missing Windows Updates using either the
    PSWindowsUpdate module (when available) or the native Windows Update COM API as a fallback.
    The command supports local execution as well as PowerShell remoting via the -ComputerName and
    -Credential parameters. Results include KB identifier, severity, and classification metadata.

.EXAMPLE
    Invoke-PatchScan

    Performs a local scan using the most appropriate provider and returns pending updates.

.EXAMPLE
    Invoke-PatchScan -ComputerName 'Server01','Server02' -Credential (Get-Credential)

    Runs the scan remotely on the specified servers using the provided credential.
#>

Set-StrictMode -Version Latest

function Format-PatchScanResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Update,

        [Parameter(Mandatory = $true)]
        [string]$ComputerName
    )

    $kbList = @()
    foreach ($propertyName in 'KBArticleIDs', 'KB', 'KBArticles') {
        if ($Update.PSObject.Properties[$propertyName]) {
            $value = $Update.$propertyName
            if ($null -ne $value) {
                if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                    $kbList += ($value | Where-Object { $_ -and $_ -ne '' })
                }
                elseif ($value -ne '') {
                    $kbList += $value
                }
            }
        }
    }

    $kb = if ($kbList) {
        ($kbList | Select-Object -Unique) -join ', '
    } else {
        $null
    }

    $classificationList = @()
    if ($Update.PSObject.Properties['Categories'] -and $null -ne $Update.Categories) {
        $classificationList += ($Update.Categories | ForEach-Object { $_.Name })
    }
    foreach ($propertyName in 'UpdateType', 'Classification', 'Category', 'CategoriesString', 'Type') {
        if ($Update.PSObject.Properties[$propertyName]) {
            $value = $Update.$propertyName
            if ($null -ne $value) {
                if ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                    $classificationList += ($value | Where-Object { $_ -and $_ -ne '' })
                }
                elseif ($value -ne '') {
                    $classificationList += $value
                }
            }
        }
    }
    $classificationList = $classificationList | Where-Object { $_ -and $_ -ne '' } | Select-Object -Unique
    $classification = if ($classificationList) { $classificationList -join ', ' } else { 'Unspecified' }

    $severityList = @()
    foreach ($propertyName in 'MsrcSeverity', 'Severity', 'UpdateSeverity', 'KbSeverity') {
        if ($Update.PSObject.Properties[$propertyName]) {
            $value = $Update.$propertyName
            if ($null -ne $value -and $value -ne '') {
                $severityList += $value
            }
        }
    }
    $severityList = $severityList | Where-Object { $_ -and $_ -ne '' } | Select-Object -Unique
    $severity = if ($severityList) { $severityList[0] } else { 'Unspecified' }

    $title = if ($Update.PSObject.Properties['Title']) { $Update.Title } elseif ($Update.PSObject.Properties['Description']) { $Update.Description } else { 'Unknown Update' }

    $result = [pscustomobject]@{
        ComputerName   = $ComputerName
        KB             = $kb
        Title          = $title
        Severity       = $severity
        Classification = $classification
    }

    $result.PSObject.TypeNames.Insert(0, 'WinSysAuto.PatchScanResult')
    return $result
}

function Test-PSWindowsUpdateAvailable {
    [CmdletBinding()]
    param()

    try {
        Write-Verbose 'Checking for PSWindowsUpdate module availability.'
        $module = Get-Module -ListAvailable -Name 'PSWindowsUpdate' -ErrorAction SilentlyContinue
        if ($null -eq $module) {
            return $false
        }

        $command = Get-Command -Name 'Get-WindowsUpdate' -ErrorAction SilentlyContinue
        return $null -ne $command
    }
    catch {
        Write-Verbose ("PSWindowsUpdate detection failed: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Get-PendingUpdatesFromPSWindowsUpdate {
    [CmdletBinding()]
    param()

    Write-Verbose 'Retrieving pending updates via PSWindowsUpdate.'

    $parameters = @{
        ListOnly        = $true
        MicrosoftUpdate = $true
        IgnoreReboot    = $true
        AcceptAll       = $true
        ErrorAction     = 'Stop'
    }

    $updates = @()
    try {
        $updates = @(Get-WindowsUpdate @parameters)
    }
    catch {
        throw
    }

    return $updates | Where-Object {
        $isInstalledProperty = $_.PSObject.Properties['IsInstalled']
        if ($isInstalledProperty) {
            -not [bool]$isInstalledProperty.Value
        }
        else {
            $true
        }
    }
}

function Get-PendingUpdatesFromCom {
    [CmdletBinding()]
    param()

    Write-Verbose 'Retrieving pending updates via Microsoft.Update.Session COM API.'

    try {
        $session = New-Object -ComObject 'Microsoft.Update.Session'
        $searcher = $session.CreateUpdateSearcher()
        $criteria = "IsInstalled=0 and Type='Software'"
        $searchResult = $searcher.Search($criteria)
        $collection = $searchResult.Updates
        $pending = @()
        for ($index = 0; $index -lt $collection.Count; $index++) {
            $pending += $collection.Item($index)
        }
        return $pending
    }
    catch {
        throw
    }
}

function Invoke-PatchScanCore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetComputer
    )

    try {
        $updates = if (Test-PSWindowsUpdateAvailable) {
            Get-PendingUpdatesFromPSWindowsUpdate
        }
        else {
            Get-PendingUpdatesFromCom
        }

        if (-not $updates) {
            return @()
        }

        $count = if ($updates -is [System.Collections.ICollection]) {
            $updates.Count
        }
        elseif ($updates -is [array]) {
            $updates.Count
        }
        else {
            ($updates | Measure-Object).Count
        }

        Write-Verbose ('Formatting {0} update result(s).' -f $count)
        return $updates | ForEach-Object { Format-PatchScanResult -Update $_ -ComputerName $TargetComputer }
    }
    catch {
        throw
    }
}

function Invoke-PatchScan {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('CN', 'Server')]
        [string[]]$ComputerName = @($env:COMPUTERNAME),

        [System.Management.Automation.PSCredential]$Credential
    )

    begin {
        $localComputerName = $env:COMPUTERNAME
        $localNormalized = if ($localComputerName) { $localComputerName.ToLowerInvariant() } else { '' }
        $localAliases = @('.', 'localhost', '127.0.0.1', '::1')
    }

    process {
        foreach ($name in $ComputerName) {
            $target = if ([string]::IsNullOrWhiteSpace($name)) { $localComputerName } else { $name }
            $normalizedTarget = if ($target) { $target.ToLowerInvariant() } else { '' }
            $isLocal = ($normalizedTarget -eq $localNormalized) -or ($localAliases -contains $normalizedTarget)

            if ($isLocal -or -not $target) {
                $effectiveName = if ($target) { $target } else { $localComputerName }
                Write-Verbose ("Scanning local computer '{0}'." -f $effectiveName)
                try {
                    Invoke-PatchScanCore -TargetComputer $effectiveName
                }
                catch {
                    Write-Error -Message ("Failed to scan {0}: {1}" -f $effectiveName, $_.Exception.Message)
                }
            }
            else {
                Write-Verbose ("Scanning remote computer '{0}'." -f $target)
                try {
                    $helperFunctionNames = @(
                        'Format-PatchScanResult',
                        'Test-PSWindowsUpdateAvailable',
                        'Get-PendingUpdatesFromPSWindowsUpdate',
                        'Get-PendingUpdatesFromCom',
                        'Invoke-PatchScanCore'
                    )

                    $functionDefinitions = ($helperFunctionNames | ForEach-Object {
                        $definition = ${function:$_}
                        if (-not $definition) {
                            throw "Required function '$_' is not defined."
                        }
                        "function $_ {`n$definition`n}"
                    }) -join "`n`n"

                    Invoke-Command -ComputerName $target -Credential $Credential -ErrorAction Stop -ScriptBlock {
                        param($definitions, $remoteTarget, $verbosePref)
                        $VerbosePreference = $verbosePref
                        Invoke-Expression $definitions
                        Invoke-PatchScanCore -TargetComputer $remoteTarget
                    } -ArgumentList $functionDefinitions, $target, $VerbosePreference
                }
                catch {
                    Write-Error -Message ("Failed to scan {0}: {1}" -f $target, $_.Exception.Message)
                }
            }
        }
    }
}

Export-ModuleMember -Function Invoke-PatchScan
