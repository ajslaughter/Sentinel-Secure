<#
.SYNOPSIS
    Installs the WinSysAuto PowerShell module.

.DESCRIPTION
    Installs WinSysAuto to either the current user's module path or the system-wide
    module path (requires administrator). Automatically detects the best installation
    location and handles both PowerShell 5.1 and PowerShell 7+.

.PARAMETER Scope
    Installation scope: 'CurrentUser' or 'AllUsers'. AllUsers requires administrator.
    Default: CurrentUser

.PARAMETER Force
    Force reinstallation even if the module is already installed.

.EXAMPLE
    .\install.ps1
    Installs for the current user.

.EXAMPLE
    .\install.ps1 -Scope AllUsers
    Installs system-wide (requires administrator).

.EXAMPLE
    .\install.ps1 -Force
    Reinstalls the module for the current user.
#>
[CmdletBinding()]
param(
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser',

    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Write-Host "`n" -NoNewline
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "  WinSysAuto Installation" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "`n"

$moduleSource = $PSScriptRoot
$moduleName = 'WinSysAuto'

# Determine target path based on scope
if ($Scope -eq 'AllUsers') {
    # Check for admin rights
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "ERROR: Installing to AllUsers scope requires administrator privileges." -ForegroundColor Red
        Write-Host "Please run this script as Administrator or use -Scope CurrentUser" -ForegroundColor Yellow
        exit 1
    }

    # System-wide installation
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell Core/7+
        $targetRoot = Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\Modules'
    }
    else {
        # Windows PowerShell 5.1
        $targetRoot = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsPowerShell\Modules'
    }
    Write-Host "Installing for: All Users (system-wide)" -ForegroundColor Green
}
else {
    # User installation
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # PowerShell Core/7+
        $targetRoot = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'PowerShell\Modules'
    }
    else {
        # Windows PowerShell 5.1
        $targetRoot = Join-Path -Path ([Environment]::GetFolderPath('MyDocuments')) -ChildPath 'WindowsPowerShell\Modules'
    }
    Write-Host "Installing for: Current User" -ForegroundColor Green
}

$targetPath = Join-Path -Path $targetRoot -ChildPath $moduleName
Write-Host "Target path:    $targetPath" -ForegroundColor Cyan

# Check if already installed
if (Test-Path -Path $targetPath) {
    if ($Force) {
        Write-Host "`nModule already exists. Force flag specified - removing old version..." -ForegroundColor Yellow
        Remove-Item -Path $targetPath -Recurse -Force
    }
    else {
        Write-Host "`nERROR: Module already installed at $targetPath" -ForegroundColor Red
        Write-Host "Use -Force to reinstall or manually remove the existing module." -ForegroundColor Yellow
        exit 1
    }
}

# Create target directory
Write-Host "`nCreating module directory..." -ForegroundColor Cyan
New-Item -Path $targetPath -ItemType Directory -Force | Out-Null

# Copy files
Write-Host "Copying module files..." -ForegroundColor Cyan
$filesToCopy = @(
    'WinSysAuto.psd1',
    'WinSysAuto.psm1',
    'Config',
    'Public',
    'Private',
    'Dashboard',
    'baselines'
)

foreach ($item in $filesToCopy) {
    $sourcePath = Join-Path -Path $moduleSource -ChildPath $item
    if (Test-Path -Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $targetPath -Recurse -Force
        Write-Host "  Copied: $item" -ForegroundColor Gray
    }
    else {
        Write-Host "  WARNING: $item not found, skipping..." -ForegroundColor Yellow
    }
}

# Set execution policy if needed (CurrentUser scope only)
if ($Scope -eq 'CurrentUser') {
    try {
        $currentPolicy = Get-ExecutionPolicy -Scope CurrentUser
        if ($currentPolicy -eq 'Restricted' -or $currentPolicy -eq 'Undefined') {
            Write-Host "`nSetting execution policy to RemoteSigned for current user..." -ForegroundColor Cyan
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
        }
    }
    catch {
        Write-Host "WARNING: Could not set execution policy: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Import and test
Write-Host "`nImporting module..." -ForegroundColor Cyan
try {
    Import-Module -Name $targetPath -Force -ErrorAction Stop
    Write-Host "Module imported successfully!" -ForegroundColor Green
}
catch {
    Write-Host "ERROR: Failed to import module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Show available commands
Write-Host "`n" -NoNewline
Write-Host "=" * 70 -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "=" * 70 -ForegroundColor Green
Write-Host "`nAvailable Commands:" -ForegroundColor Cyan
Get-Command -Module WinSysAuto | ForEach-Object {
    Write-Host "  - " -NoNewline
    Write-Host $_.Name -ForegroundColor Green
}

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "  1. Run: " -NoNewline
Write-Host "Initialize-WsaEnvironment" -ForegroundColor Green
Write-Host "     (Auto-detects your domain and network configuration)"
Write-Host "`n  2. Run: " -NoNewline
Write-Host "Start-WsaDashboard" -ForegroundColor Green
Write-Host "     (Launch the live monitoring dashboard)"

Write-Host "`nFor help on any command, use: " -NoNewline
Write-Host "Get-Help <CommandName> -Detailed" -ForegroundColor Green

Write-Host "`n" -NoNewline
Write-Host "=" * 70 -ForegroundColor Green
Write-Host "`n"
