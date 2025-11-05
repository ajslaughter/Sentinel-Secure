function New-WsaResult {
    param(
        [ValidateSet('Compliant','Changed','Error','Unknown')]
        [string]$Status = 'Unknown',

        [object[]]$Changes = @(),

        [object[]]$Findings = @(),

        [hashtable]$Data = @{}
    )

    return [pscustomobject]@{
        Status   = $Status
        Changes  = $Changes
        Findings = $Findings
        Data     = $Data
    }
}
