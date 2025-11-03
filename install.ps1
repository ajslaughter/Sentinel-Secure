param(
    [string]$DestinationRoot = "$env:ProgramFiles\WindowsPowerShell\Modules"
)

$moduleName = 'WinSysAuto'
$sourcePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$destinationPath = Join-Path -Path $DestinationRoot -ChildPath $moduleName

if (-not (Test-Path -Path $DestinationRoot)) {
    New-Item -Path $DestinationRoot -ItemType Directory -Force | Out-Null
}

if (Test-Path -Path $destinationPath) {
    Remove-Item -Path $destinationPath -Recurse -Force
}

Copy-Item -Path $sourcePath -Destination $destinationPath -Recurse -Force

Write-Host "WinSysAuto installed to $destinationPath"
function Resolve-ModuleRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath
    )

    $manifest = Get-ChildItem -Path $BasePath -Filter '*.psd1' -Recurse -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        Select-Object -First 1

    if ($manifest) {
        Write-Verbose "Found module manifest at '$($manifest.FullName)'."
        return [pscustomobject]@{
            Path = $manifest.DirectoryName
            Name = $manifest.BaseName
        }
    }

    $fallbackName = Split-Path -Path $BasePath -Leaf
    Write-Warning "No module manifest (*.psd1) found. Falling back to installing the entire repository as module '$fallbackName'."
    return [pscustomobject]@{
        Path = $BasePath
        Name = $fallbackName
    }
}

function Get-DestinationPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope,
        [Parameter(Mandatory)]
        [string]$ModuleName
    )

    switch ($Scope) {
        'AllUsers' {
            if (-not $env:ProgramFiles) {
                throw "\$env:ProgramFiles is not defined."
            }
            $moduleRoot = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsPowerShell\Modules'
        }
        'CurrentUser' {
            if (-not $env:USERPROFILE) {
                throw "\$env:USERPROFILE is not defined."
            }
            $moduleRoot = Join-Path -Path $env:USERPROFILE -ChildPath 'Documents\WindowsPowerShell\Modules'
        }
    }

    if (-not (Test-Path -LiteralPath $moduleRoot)) {
        Write-Verbose "Creating module root '$moduleRoot'."
        $null = New-Item -ItemType Directory -Path $moduleRoot -Force
    }

    return Join-Path -Path $moduleRoot -ChildPath $ModuleName
}

function Get-FileHashTable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $hashes = @{}
    Get-ChildItem -Path $Path -File -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring($Path.Length).TrimStart('\\', '/')
        $hashes[$relative] = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
    }
    return $hashes
}

function Copy-ModuleContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination,
        [switch]$Force
    )

    if (Test-Path -LiteralPath $Destination) {
        if ($Force) {
            Write-Verbose "Removing existing module at '$Destination'."
            Remove-Item -LiteralPath $Destination -Recurse -Force
        }
        else {
            throw "Module destination '$Destination' already exists. Use -Force to overwrite."
        }
    }

    Write-Verbose "Copying module files from '$Source' to '$Destination'."
    $null = New-Item -ItemType Directory -Path $Destination -Force
    $excluded = @('.git', '.github', '.vs', '.idea', 'install.ps1')
    Get-ChildItem -Path $Source -Force | Where-Object { $excluded -notcontains $_.Name } | ForEach-Object {
        $itemDestination = Join-Path -Path $Destination -ChildPath $_.Name
        Copy-Item -Path $_.FullName -Destination $itemDestination -Recurse -Force
    }
}

function Confirm-ChecksumsMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination
    )

    Write-Verbose "Verifying file checksums between source and destination."
    $sourceHashes = Get-FileHashTable -Path $Source
    $destinationHashes = Get-FileHashTable -Path $Destination

    $issues = @()
    foreach ($key in $sourceHashes.Keys) {
        if (-not $destinationHashes.ContainsKey($key)) {
            $issues += "Missing file '$key' in destination."
            continue
        }
        if ($sourceHashes[$key] -ne $destinationHashes[$key]) {
            $issues += "Checksum mismatch for '$key'."
        }
    }

    foreach ($key in $destinationHashes.Keys) {
        if (-not $sourceHashes.ContainsKey($key)) {
            $issues += "Extra file '$key' found in destination."
        }
    }

    if ($issues.Count -gt 0) {
        $issues | ForEach-Object { Write-Warning $_ }
        throw "Checksum verification failed."
    }

    Write-Verbose "Checksum verification succeeded."
}

Write-Verbose "Running on PowerShell $($PSVersionTable.PSVersion)."

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleInfo = Resolve-ModuleRoot -BasePath $scriptRoot

$isAdmin = Test-IsAdministrator

switch ($Scope) {
    'Auto' {
        $effectiveScope = if ($isAdmin) { 'AllUsers' } else { 'CurrentUser' }
    }
    default {
        $effectiveScope = $Scope
    }
}

if ($effectiveScope -eq 'AllUsers' -and -not $isAdmin) {
    Write-Warning 'Administrator privileges are required to install for AllUsers. Falling back to CurrentUser scope.'
    $effectiveScope = 'CurrentUser'
}

$destinationPath = Get-DestinationPath -Scope $effectiveScope -ModuleName $moduleInfo.Name

if ($PSCmdlet.ShouldProcess($destinationPath, "Install module '$($moduleInfo.Name)'")) {
    Copy-ModuleContent -Source $moduleInfo.Path -Destination $destinationPath -Force:$Force
    Confirm-ChecksumsMatch -Source $moduleInfo.Path -Destination $destinationPath
    Write-Host "WinSysAuto module installed to '$destinationPath'." -ForegroundColor Green
}
