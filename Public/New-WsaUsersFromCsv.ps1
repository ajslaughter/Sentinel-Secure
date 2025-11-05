function New-WsaUsersFromCsv {
    <#
    .SYNOPSIS
        Creates or updates Active Directory users from a CSV definition.

    .DESCRIPTION
        Reads user definitions from a CSV file and ensures each account exists within the
        specified OU structure. Optional behaviors include creating missing security
        groups, resetting passwords, and adding group memberships. Existing accounts are
        updated safely without duplication.

        CSV Format:
        - GivenName: User's first name
        - Surname: User's last name
        - SamAccountName: Username (required)
        - Department: Department name (optional, used for auto-grouping)
        - OU: Full distinguished name of target OU (optional)
        - Password: Initial password (optional)
        - Groups: Semicolon-separated list of group names (optional)

    .PARAMETER Path
        Path to the CSV file.

    .PARAMETER AutoCreateGroups
        Creates security groups named SG_<Department> when missing.

    .PARAMETER ResetPasswordIfProvided
        Resets the password for existing users when a Password column value is supplied.

    .PARAMETER DefaultOU
        Default OU for users if not specified in CSV. If not provided, uses CN=Users,<domain>.

    .EXAMPLE
        New-WsaUsersFromCsv -Path .\users.csv -AutoCreateGroups -Verbose

        Imports users from the CSV and ensures required groups exist.

    .EXAMPLE
        New-WsaUsersFromCsv -Path .\users.csv -DefaultOU "OU=Employees,DC=contoso,DC=com"

        Imports users into a specific OU.

    .OUTPUTS
        PSCustomObject
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateScript({ Test-Path -Path $_ })]
        [string]$Path,

        [switch]$AutoCreateGroups,

        [switch]$ResetPasswordIfProvided,

        [string]$DefaultOU
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

    # Set default OU if not specified
    if (-not $DefaultOU) {
        $DefaultOU = "CN=Users,$($domain.DistinguishedName)"
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

        # Determine target OU
        $targetOu = if (-not [string]::IsNullOrWhiteSpace($record.OU)) {
            $record.OU
        }
        elseif (-not [string]::IsNullOrWhiteSpace($record.Department)) {
            # Try department-based OU, fall back to default
            $deptOU = "OU=$($record.Department),OU=Departments,$($domain.DistinguishedName)"
            # Check if this OU exists
            try {
                $ouTest = Get-ADOrganizationalUnit -Identity $deptOU -ErrorAction SilentlyContinue
                if ($ouTest) {
                    $deptOU
                }
                else {
                    $DefaultOU
                }
            }
            catch {
                $DefaultOU
            }
        }
        else {
            $DefaultOU
        }

        $userPrincipalName = "$($record.SamAccountName)@$($domain.DNSRoot)"
        $displayName = "$($record.GivenName) $($record.Surname)".Trim()

        # Verify OU exists
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

        # Check if user exists
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
                        AccountPassword    = if ($record.Password) {
                            (ConvertTo-SecureString -String $record.Password -AsPlainText -Force)
                        } else {
                            (ConvertTo-SecureString -String ([guid]::NewGuid().ToString()) -AsPlainText -Force)
                        }
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
                $existingGroup = Get-ADGroup -Identity $deptGroup -ErrorAction SilentlyContinue
                if (-not $existingGroup) {
                    # Try to create in Departments OU, fall back to Users container
                    $groupPath = "OU=Departments,$($domain.DistinguishedName)"
                    $groupPathExists = Get-ADOrganizationalUnit -Identity $groupPath -ErrorAction SilentlyContinue
                    if (-not $groupPathExists) {
                        $groupPath = "CN=Users,$($domain.DistinguishedName)"
                    }

                    if ($PSCmdlet.ShouldProcess($deptGroup, 'Create security group', 'Create group')) {
                        New-ADGroup -Name $deptGroup -GroupScope Global -GroupCategory Security -Path $groupPath -SamAccountName $deptGroup -ErrorAction Stop | Out-Null
                        $changes.Add("Created group $deptGroup") | Out-Null
                        Write-WsaLog -Component $component -Message "Created group $deptGroup."
                    }
                }
            }
            catch {
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
