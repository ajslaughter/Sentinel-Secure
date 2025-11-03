$script:ModuleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$functionsPath = Join-Path -Path $script:ModuleRoot -ChildPath 'Functions'

if (Test-Path -Path $functionsPath) {
    Get-ChildItem -Path $functionsPath -Filter '*.ps1' -File | Sort-Object -Property FullName | ForEach-Object {
        . $_.FullName
    }
}

Export-ModuleMember -Function @(
    'Get-Inventory',
    'Invoke-PatchScan',
    'Set-SecurityBaseline',
    'Watch-Health',
    'Export-InventoryReport'
)
