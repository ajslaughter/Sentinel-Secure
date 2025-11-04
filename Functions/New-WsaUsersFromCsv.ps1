function New-WsaUsersFromCsv {
    <#
    .SYNOPSIS
        Creates or updates Active Directory users from a CSV definition.

    .DESCRIPTION
        Reads user definitions from a CSV file and ensures each account exists within the
        departmental OU tree. Optional behaviours include creating missing security
        groups, resetting passwords, and adding group memberships. Existing accounts are
        updated safely without duplication.

    .PARAMETER Path
        Path to the CSV file. Columns: GivenName,Surname,SamAccountName,Department,OU,
        Password,Groups.

    .PARAMETER AutoCreateGroups
        Creates security groups named SG_<Department> within OU=Departments when missing.

    .PARAMETER ResetPasswordIfProvided
        Resets the password for existing users when a Password column value is supplied.

    .EXAMPLE
        New-WsaUsersFromCsv -Path .\users.csv -AutoCreateGroups -Verbose

        Imports users from the CSV and ensures required groups exist.

    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -Path $_ })]
        [string]$Path,

        [switch]$AutoCreateGroups,

        [switch]$ResetPasswordIfProvided
    )

    $component = 'New-WsaUsersFromCsv'
    Write-WsaLog -Component $component -Message "Importing users from $Path."

    if (-not (Get-Command -Name New-ADUser -ErrorAction SilentlyContinue)) {
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

    $changes  = New-Object System.Collections.Generic.List[object]
    $findings = New-Object System.Collections.Generic.List[object]
    $results  = New-Object System.Collections.Generic.List[object]

    $records = Import-Csv -Path $Path
    if (-not $records) {
        return New-WsaResult -Status 'Compliant' -Findings @('CSV file contained no records.')
    }

    foreach ($record in $records) {
        if (-not $record.SamAccountName) {
            $findings.Add('Record missing SamAccountName. Skipping.') | Out-Null
            continue
        }

        $targetOu = if ([string]::IsNullOrWhiteSpace($record.OU)) {
            "OU=$($record.Department),OU=Departments,$($domain.DistinguishedName)"
        } else {
            $record.OU
        }

        $userPrincipalName = "$($record.SamAccountName)@$($domain.DNSRoot)"
        $displayName = "$($record.GivenName) $($record.Surname)".Trim()

        try {
            $ouExists = Get-ADOrganizationalUnit -Identity $targetOu -ErrorAction SilentlyContinue
        }
        catch {
            $ouExists = $null
        }

        if (-not $ouExists) {
            $findings.Add("OU not found for $($record.SamAccountName): $targetOu") | Out-Null
            continue
        }

        try {
            $existingUser = Get-ADUser -Identity $record.SamAccountName -ErrorAction SilentlyContinue
        }
        catch {
            $existingUser = $null
        }

        $shouldCreate = -not $existingUser

        if ($shouldCreate) {
            if ($PSCmdlet.ShouldProcess($record.SamAccountName, 'Create user account', 'Create AD user')) {
                try {
                    $params = @{ 
                        Name               = $displayName
                        SamAccountName     = $record.SamAccountName
                        GivenName          = $record.GivenName
                        Surname            = $record.Surname
                        DisplayName        = $displayName
                        UserPrincipalName  = $userPrincipalName
                        Path               = $targetOu
                        Enabled            = $true
                        AccountPassword    = if ($record.Password) { (ConvertTo-SecureString -String $record.Password -AsPlainText -Force) } else { (ConvertTo-SecureString -String ([guid]::NewGuid().ToString()) -AsPlainText -Force) }
                    }
                    New-ADUser @params
                    Enable-ADAccount -Identity $record.SamAccountName -ErrorAction Stop
                    $changes.Add("Created user $($record.SamAccountName) in $targetOu") | Out-Null
                    Write-WsaLog -Component $component -Message "Created AD user $($record.SamAccountName)."
                }
                catch {
                    $msg = "Failed to create user $($record.SamAccountName): $($_.Exception.Message)"
                    Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
                    $findings.Add($msg) | Out-Null
                    continue
                }
            }
            else {
                $findings.Add("Creation skipped for $($record.SamAccountName) due to -WhatIf.") | Out-Null
                continue
            }
        }
        else {
            Write-WsaLog -Component $component -Message "User $($record.SamAccountName) already exists." -Level 'DEBUG'
            if ($ResetPasswordIfProvided.IsPresent -and $record.Password) {
                if ($PSCmdlet.ShouldProcess($record.SamAccountName, 'Reset password', 'Reset user password')) {
                    try {
                        $securePassword = ConvertTo-SecureString -String $record.Password -AsPlainText -Force
                        Set-ADAccountPassword -Identity $record.SamAccountName -NewPassword $securePassword -Reset -ErrorAction Stop
                        $changes.Add("Reset password for $($record.SamAccountName)") | Out-Null
                    }
                    catch {
                        $msg = "Failed to reset password for $($record.SamAccountName): $($_.Exception.Message)"
                        Write-WsaLog -Component $component -Message $msg -Level 'ERROR'
                        $findings.Add($msg) | Out-Null
                    }
                }
            }

            try {
                Enable-ADAccount -Identity $record.SamAccountName -ErrorAction Stop
            }
            catch {
                $msg = "Failed to enable user $($record.SamAccountName): $($_.Exception.Message)"
                Write-WsaLog -Component $component -Message $msg -Level 'WARN'
                $findings.Add($msg) | Out-Null
            }
        }

        # Group handling
        $groupList = @()
        if ($record.Groups) {
            $groupList = $record.Groups -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        }

        if ($AutoCreateGroups.IsPresent -and $record.Department) {
            $deptGroup = "SG_$($record.Department)"
            if ($deptGroup -notin $groupList) {
                $groupList += $deptGroup
            }

            try {
                $groupDn = "CN=$deptGroup,OU=Departments,$($domain.DistinguishedName)"
                $existingGroup = Get-ADGroup -Identity $deptGroup -ErrorAction SilentlyContinue
                if (-not $existingGroup -and $PSCmdlet.ShouldProcess($deptGroup, 'Create security group', 'Create group')) {
                    New-ADGroup -Name $deptGroup -GroupScope Global -GroupCategory Security -Path "OU=Departments,$($domain.DistinguishedName)" -SamAccountName $deptGroup -ErrorAction Stop | Out-Null
                    $changes.Add("Created group $deptGroup") | Out-Null
                    Write-WsaLog -Component $component -Message "Created group $deptGroup."
                }
            }
            catch {
                # FIXED: Wrapped $deptGroup in ${} to avoid PowerShell misreading as drive path
                $msg = "Failed to ensure group ${deptGroup}: $($_.Exception.Message)"
                Write-WsaLog -Component $component -Message $msg -Level 'WARN'
                $findings.Add($msg) | Out-Null
            }
        }

        foreach ($group in $groupList) {
            if (-not $group) { continue }
            try {
                $existingMembership = Get-ADGroupMember -Identity $group -Recursive -ErrorAction Stop | Where-Object { $_.SamAccountName -eq $record.SamAccountName }
                if (-not $existingMembership) {
                    if ($PSCmdlet.ShouldProcess($record.SamAccountName, "Add to group $group", 'Update group membership')) {
                        Add-ADGroupMember -Identity $group -Members $record.SamAccountName -ErrorAction Stop
                        $changes.Add("Added $($record.SamAccountName) to $group") | Out-Null
                    }
                }
            }
            catch {
                # FIXED: Wrapped $group in ${} to avoid PowerShell misreading as drive path
                $msg = "Failed to add $($record.SamAccountName) to ${group}: $($_.Exception.Message)"
                Write-WsaLog -Component $component -Message $msg -Level 'WARN'
                $findings.Add($msg) | Out-Null
            }
        }

        $results.Add([pscustomobject]@{
            SamAccountName = $record.SamAccountName
            OU              = $targetOu
            Groups          = $groupList
            Status          = if ($shouldCreate) { 'Created' } else { 'Processed' }
        }) | Out-Null
    }

    $status = if ($changes.Count -gt 0) { 'Changed' } else { 'Compliant' }
    if ($findings.Count -gt 0 -and $status -ne 'Changed') { $status = 'Changed' }

    return New-WsaResult -Status $status -Changes $changes.ToArray() -Findings $findings.ToArray() -Data @{ Users = $results }
}
