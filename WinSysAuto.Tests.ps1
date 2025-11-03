$testsPath = Join-Path -Path $PSScriptRoot -ChildPath 'tests'
Invoke-Pester -Path $testsPath
