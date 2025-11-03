$script:ModuleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$functionsPath = Join-Path $script:ModuleRoot 'functions'

if (Test-Path -Path $functionsPath) {
    Get-ChildItem -Path $functionsPath -Filter '*.ps1' -File | ForEach-Object {
        . $_.FullName
    }
}

Export-ModuleMember -Function * -Alias *
