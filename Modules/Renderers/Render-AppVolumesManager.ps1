# =============================================================================
# Render-AppVolumesManager — New-HtmlAppVolumesManagerSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlAppVolumesManagerSection {
    param($AVM)
    if (-not $AVM -or $AVM.Count -eq 0) {
        return ""
    }
    $rows = foreach ($a in $AVM) {
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $a.ServerName),
            (Invoke-HtmlEncode "$($a.Port)"),
            (Invoke-HtmlEncode $a.UserName)
        )
    }
    $table = New-HtmlTable -Headers @("Server Name","Port","Username") -Rows $rows
    return New-HtmlSection -Id "app-volumes" -Title "App Volumes Manager" -Content $table
}

