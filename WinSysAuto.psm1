#Requires -Version 5.1

$moduleRoot = Split-Path -Parent $PSCommandPath

# Load private functions first
$privateFunctions = Join-Path -Path $moduleRoot -ChildPath 'Private'
if (Test-Path -Path $privateFunctions) {
    Get-ChildItem -Path $privateFunctions -Filter '*.ps1' -Recurse | Sort-Object FullName | ForEach-Object {
        . $_.FullName
    }
}

# Load config functions
$configFunctions = Join-Path -Path $moduleRoot -ChildPath 'Config'
if (Test-Path -Path $configFunctions) {
    Get-ChildItem -Path $configFunctions -Filter '*.ps1' -Recurse | Sort-Object FullName | ForEach-Object {
        . $_.FullName
    }
}

# Load public functions
$publicFunctions = Join-Path -Path $moduleRoot -ChildPath 'Public'
if (Test-Path -Path $publicFunctions) {
    Get-ChildItem -Path $publicFunctions -Filter '*.ps1' -Recurse | Sort-Object FullName | ForEach-Object {
        . $_.FullName
    }
}

# Export public functions
$exportFunctions = @(
    'Initialize-WsaEnvironment',
    'Get-WsaHealth',
    'Start-WsaDashboard',
    'New-WsaUsersFromCsv',
    'Backup-WsaConfig',
    'Invoke-WsaSecurityBaseline'
)

Export-ModuleMember -Function $exportFunctions

# First-run detection
$configPath = Join-Path -Path $env:ProgramData -ChildPath 'WinSysAuto\config.json'
if (-not (Test-Path -Path $configPath)) {
    Write-Host "`n" -NoNewline
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Host "  WinSysAuto - First Run Detected" -ForegroundColor Cyan
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Host "`n  To initialize WinSysAuto for this environment, run:" -ForegroundColor Yellow
    Write-Host "`n    Initialize-WsaEnvironment" -ForegroundColor Green
    Write-Host "`n  This will auto-detect your domain, servers, and network configuration."
    Write-Host "`n  After initialization, you can use:" -ForegroundColor Yellow
    Write-Host "    - " -NoNewline
    Write-Host "Start-WsaDashboard" -ForegroundColor Green -NoNewline
    Write-Host "          Live cyberpunk monitoring dashboard"
    Write-Host "    - " -NoNewline
    Write-Host "Get-WsaHealth" -ForegroundColor Green -NoNewline
    Write-Host "               Health check and reporting"
    Write-Host "    - " -NoNewline
    Write-Host "New-WsaUsersFromCsv" -ForegroundColor Green -NoNewline
    Write-Host "        Bulk user creation from CSV"
    Write-Host "    - " -NoNewline
    Write-Host "Backup-WsaConfig" -ForegroundColor Green -NoNewline
    Write-Host "            Backup domain configuration"
    Write-Host "    - " -NoNewline
    Write-Host "Invoke-WsaSecurityBaseline" -ForegroundColor Green -NoNewline
    Write-Host "  Apply security hardening"
    Write-Host "`n" -NoNewline
    Write-Host "=" * 70 -ForegroundColor Cyan
    Write-Host "`n"
}
