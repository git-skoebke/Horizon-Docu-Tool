# =============================================================================
# Render-VCenter — New-HtmlVCenterSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlVCenterSection {
    param($VCenters)
    if (-not $VCenters -or $VCenters.Count -eq 0) {
        return ""
    }
    $rows = foreach ($vc in $VCenters) {
        $cbrcDisplay = if ($null -eq $vc.CbrcEnabled) { "N/A" }
                       elseif ($vc.CbrcEnabled)       { "Enabled ($($vc.CbrcCacheSizeMB) MB)" }
                       else                            { "Disabled" }
        $buildDisplay = if ($vc.Build) { $vc.Build } else { "N/A" }
        $roleDisplay  = if ($vc.SecurityRole) { $vc.SecurityRole } else { "N/A" }
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $vc.Name),
            (Invoke-HtmlEncode $vc.Version),
            (Invoke-HtmlEncode $buildDisplay),
            (Invoke-HtmlEncode $vc.UserName),
            (Invoke-HtmlEncode $roleDisplay),
            (Invoke-HtmlEncode $vc.DeploymentType),
            (Invoke-HtmlEncode $cbrcDisplay)
        )
    }
    $table = New-HtmlTable -Headers @("Name","Version","Build","Connected As","Security Role","Deployment Type","CBRC") -Rows $rows

    # Collapsible privilege details per vCenter with a role
    $privDetails = ""
    foreach ($vc in $VCenters) {
        if ($vc.RolePrivileges -and $vc.RolePrivileges.Count -gt 0) {
            $privRows = foreach ($p in ($vc.RolePrivileges | Sort-Object)) {
                New-HtmlTableRow -Cells @((Invoke-HtmlEncode $p))
            }
            $privTable = New-HtmlTable -Headers @("Privilege") -Rows $privRows
            $summaryText = "Role: " + (Invoke-HtmlEncode $vc.SecurityRole) + " - " + $vc.RolePrivileges.Count + " privileges"
            $vcLabel = Invoke-HtmlEncode $vc.Name
            $privDetails += "<details class='inline-detail' style='margin-top:8px'><summary><strong>" + $vcLabel + "</strong> - " + $summaryText + "</summary>" + $privTable + "</details>"
        }
    }

    $content = $table + $privDetails
    return New-HtmlSection -Id "vcenter-servers" -Title "vCenter Servers" -Content $content
}

