function Ensure-WsaOuModel {
    <#
    .SYNOPSIS
        Ensures the departmental OU structure exists within Active Directory.

    .DESCRIPTION
        Validates the OU=Departments tree and required child organisational units. Missing
        OUs are created, and accidental deletion protection can optionally be enforced.

    .PARAMETER ProtectFromAccidentalDeletion
        When supplied, each OU created or discovered has accidental deletion protection
        enabled.

    .EXAMPLE
        Ensure-WsaOuModel -Verbose

        Ensures the OU tree exists beneath the root domain with verbose logging.

    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [switch]$ProtectFromAccidentalDeletion
    )

    $component = 'Ensure-WsaOuModel'
    Write-WsaLog -Component $component -Message 'Validating OU structure.'

    if (-not (Get-Command -Name Get-ADOrganizationalUnit -ErrorAction SilentlyContinue)) {
        $message = 'ActiveDirectory module not available on this system.'
        Write-WsaLog -Component $component -Message $message -Level 'ERROR'
        throw $message
    }

    try {
        $domain = Get-ADDomain -ErrorAction Stop
    }
    catch {
        $message = "Unable to resolve domain context: $($_.Exception.Message)"
        Write-WsaLog -Component $component -Message $message -Level 'ERROR'
        throw $message
    }

    $rootOu = "OU=Departments,$($domain.DistinguishedName)"
    $childOus = @('IT','Sales','HR','Finance')

    $changes  = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]

    try {
        $existingRoot = Get-ADOrganizationalUnit -Identity $rootOu -ErrorAction SilentlyContinue
    }
    catch {
        $existingRoot = $null
    }

    if (-not $existingRoot) {
        if ($PSCmdlet.ShouldProcess($rootOu, 'Create organisational unit', 'Create OU')) {
            try {
                New-ADOrganizationalUnit -Name 'Departments' -Path $domain.DistinguishedName -ProtectedFromAccidentalDeletion:$ProtectFromAccidentalDeletion.IsPresent -ErrorAction Stop | Out-Null
                $changes.Add('Created OU=Departments.') | Out-Null
                Write-WsaLog -Component $component -Message 'Created OU=Departments.'
                $existingRoot = Get-ADOrganizationalUnit -Identity $rootOu -ErrorAction Stop
            }
            catch {
                $msg = "Failed to create OU=Departments: $($_.Exception.Message)"
                Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
                throw $msg
            }
        }
        else {
            $findings.Add('OU=Departments missing but creation skipped due to -WhatIf.') | Out-Null
        }
    }
    elseif ($ProtectFromAccidentalDeletion.IsPresent -and -not $existingRoot.ProtectedFromAccidentalDeletion) {
        if ($PSCmdlet.ShouldProcess($rootOu, 'Enable accidental deletion protection', 'Protect OU')) {
            try {
                Set-ADOrganizationalUnit -Identity $rootOu -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
                $changes.Add('Enabled protection on OU=Departments.') | Out-Null
            }
            catch {
                $msg = "Failed to protect OU=Departments: $($_.Exception.Message)"
                Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
                $findings.Add($msg) | Out-Null
            }
        }
    }

    foreach ($child in $childOus) {
        $childDn = "OU=$child,$rootOu"
        try {
            $existingChild = Get-ADOrganizationalUnit -Identity $childDn -ErrorAction SilentlyContinue
        }
        catch {
            $existingChild = $null
        }

        if (-not $existingChild) {
            if ($PSCmdlet.ShouldProcess($childDn, 'Create departmental OU', "Create OU $child")) {
                try {
                    New-ADOrganizationalUnit -Name $child -Path $rootOu -ProtectedFromAccidentalDeletion:$ProtectFromAccidentalDeletion.IsPresent -ErrorAction Stop | Out-Null
                    $changes.Add("Created OU=$child,$rootOu") | Out-Null
                    Write-WsaLog -Component $component -Message "Created OU=$child,$rootOu."
                }
                catch {
                    # FIXED: Wrapped $child in ${} to avoid PowerShell misreading as drive path
                    $msg = "Failed to create OU=${child}: $($_.Exception.Message)"
                    Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
                    $findings.Add($msg) | Out-Null
                }
            }
        }
        else {
            if ($ProtectFromAccidentalDeletion.IsPresent -and -not $existingChild.ProtectedFromAccidentalDeletion) {
                if ($PSCmdlet.ShouldProcess($childDn, 'Enable accidental deletion protection', "Protect OU $child")) {
                    try {
                        Set-ADOrganizationalUnit -Identity $childDn -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
                        $changes.Add("Enabled protection on OU=$child,$rootOu") | Out-Null
                    }
                    catch {
                        # FIXED: Wrapped $child in ${} to avoid PowerShell misreading as drive path
                        $msg = "Failed to protect OU=${child}: $($_.Exception.Message)"
                        Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
                        $findings.Add($msg) | Out-Null
                    }
                }
            }
        }
    }

    if ($changes.Count -eq 0 -and $findings.Count -eq 0) {
        $findings.Add('Compliant') | Out-Null
    }

    $status = if ($changes.Count -gt 0) { 'Changed' } else { 'Compliant' }
    if ($findings.Count -gt 0 -and -not $findings.Contains('Compliant')) { $status = 'Changed' }

    return New-WsaResult -Status $status -Changes $changes.ToArray() -Findings $findings.ToArray() -Data @{ RootOu = $rootOu; Children = $childOus }
}
