$moduleRoot = Split-Path -Parent $PSCommandPath
$functionRoot = Join-Path -Path $moduleRoot -ChildPath 'Functions'

Get-ChildItem -Path $functionRoot -Filter '*.ps1' -Recurse | Sort-Object FullName | ForEach-Object {
    . $_.FullName
}

$publicFunctions = @(
    'Get-WsaHealth',
    'Ensure-WsaDnsForwarders',
    'Ensure-WsaDhcpScope',
    'Ensure-WsaOuModel',
    'New-WsaUsersFromCsv',
    'Ensure-WsaDeptShares',
    'Ensure-WsaDriveMappings',
    'Invoke-WsaSecurityBaseline',
    'Start-WsaDailyReport',
    'Backup-WsaConfig',
    'Invoke-WsaM3HealthReport'
)

Export-ModuleMember -Function $publicFunctions
