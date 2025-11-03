function Invoke-PatchScan {
    [CmdletBinding()]
    param(
        [string]$Criteria = "IsInstalled=0 and Type='Software'"
    )

    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
    }
    catch {
        throw
    }

    $searcher = $updateSession.CreateUpdateSearcher()

    try {
        $searchResult = $searcher.Search($Criteria)
    }
    catch {
        throw
    }

    $updates = @()
    if ($searchResult -and $searchResult.Updates -and $searchResult.Updates.Count -gt 0) {
        for ($index = 0; $index -lt $searchResult.Updates.Count; $index++) {
            $update = $searchResult.Updates.Item($index)
            if ($null -eq $update) {
                continue
            }

            $kbList = @()
            if ($update.PSObject.Properties['KBArticleIDs']) {
                foreach ($kb in $update.KBArticleIDs) {
                    if ($kb) {
                        $kbList += $kb
                    }
                }
            }

            $categoryList = @()
            if ($update.PSObject.Properties['Categories']) {
                foreach ($category in $update.Categories) {
                    if ($category -and $category.PSObject.Properties['Name']) {
                        $categoryList += $category.Name
                    }
                }
            }

            $severity = 'Unspecified'
            foreach ($propertyName in 'MsrcSeverity', 'Severity', 'UpdateSeverity') {
                if ($update.PSObject.Properties[$propertyName] -and $update.$propertyName) {
                    $severity = $update.$propertyName
                    break
                }
            }

            $updates += [pscustomobject]@{
                Title        = $update.Title
                KB           = if ($kbList) { $kbList -join ', ' } else { $null }
                Severity     = $severity
                Categories   = if ($categoryList) { ($categoryList | Sort-Object -Unique) -join ', ' } else { 'Unspecified' }
                IsDownloaded = [bool]$update.IsDownloaded
                IsMandatory  = [bool]$update.IsMandatory
            }
        }
    }

    return $updates
}
