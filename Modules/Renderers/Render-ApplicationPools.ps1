# =============================================================================
# Render-ApplicationPools — New-HtmlApplicationPoolsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlApplicationPoolsSection {
    param($AppPools)
    if (-not $AppPools -or $AppPools.Count -eq 0) {
        return ""
    }

    $content = [System.Text.StringBuilder]::new()

    foreach ($a in ($AppPools | Sort-Object FarmName, Name)) {
        $enabledBadge = if ($a.Enabled -eq "True") {
            New-HtmlBadge -Text "Enabled" -Color "ok"
        } else {
            New-HtmlBadge -Text "Disabled" -Color "neutral"
        }

        $null = $content.Append("<details class='detail-card'>")
        $null = $content.Append("<summary>")
        $null = $content.Append((Invoke-HtmlEncode $a.Name))
        $null = $content.Append(" <span class='card-meta'>$(Invoke-HtmlEncode $a.FarmName) &nbsp;$enabledBadge</span>")
        $null = $content.Append("</summary>")
        $null = $content.Append("<div>")

        # General
        $null = $content.Append("<h4>General</h4>")
        $detailRows = [System.Collections.Generic.List[string]]::new()
        $detailRows.Add((New-HtmlTableRow -Cells @("Name",           (Invoke-HtmlEncode $a.Name))))
        $detailRows.Add((New-HtmlTableRow -Cells @("Display Name",   (Invoke-HtmlEncode $a.DisplayName))))
        $detailRows.Add((New-HtmlTableRow -Cells @("Enabled",        $enabledBadge)))
        $detailRows.Add((New-HtmlTableRow -Cells @("Farm",           (Invoke-HtmlEncode $a.FarmName))))
        $detailRows.Add((New-HtmlTableRow -Cells @("Executable Path",(Invoke-HtmlEncode $a.ExecutablePath))))
        if ($a.EnablePreLaunch -ne "") {
            $plBadge = if ($a.EnablePreLaunch -eq "True") {
                New-HtmlBadge -Text "Yes" -Color "ok"
            } else {
                New-HtmlBadge -Text "No" -Color "neutral"
            }
            $detailRows.Add((New-HtmlTableRow -Cells @("Pre-Launch",  $plBadge)))
        }
        if ($a.EnableClientRestr -ne "") {
            $crBadge = if ($a.EnableClientRestr -eq "True") {
                New-HtmlBadge -Text "Yes" -Color "warn"
            } else {
                New-HtmlBadge -Text "No" -Color "neutral"
            }
            $detailRows.Add((New-HtmlTableRow -Cells @("Client Restriction", $crBadge)))
        }
        if ($a.AppStatus -and $a.AppStatus -ne "") {
            $stColor = switch ($a.AppStatus) {
                "OK"      { "ok" }
                "WARNING" { "warn" }
                "ERROR"   { "error" }
                default   { "neutral" }
            }
            $detailRows.Add((New-HtmlTableRow -Cells @("Status", (New-HtmlBadge -Text $a.AppStatus -Color $stColor))))
        }
        if ($a.AllowChooseMachines -ne "") {
            $acmBadge = if ($a.AllowChooseMachines -eq "True") {
                New-HtmlBadge -Text "Yes" -Color "ok"
            } else {
                New-HtmlBadge -Text "No" -Color "neutral"
            }
            $detailRows.Add((New-HtmlTableRow -Cells @("Allow Users to Choose Machines", $acmBadge)))
        }
        if ($a.Publisher -and $a.Publisher -ne "") {
            $detailRows.Add((New-HtmlTableRow -Cells @("Publisher", (Invoke-HtmlEncode $a.Publisher))))
        }
        if ($a.Version -and $a.Version -ne "") {
            $detailRows.Add((New-HtmlTableRow -Cells @("Version",   (Invoke-HtmlEncode $a.Version))))
        }
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $detailRows))

        # Entitlements
        $null = $content.Append("<h4>Entitlements</h4>")
        if ($a.Entitlements -and $a.Entitlements.Count -gt 0) {
            $entRows = foreach ($e in ($a.Entitlements | Sort-Object Name)) {
                $typeBadge = if ($e.IsGroup) {
                    New-HtmlBadge -Text "Group" -Color "neutral"
                } else {
                    New-HtmlBadge -Text "User" -Color "ok"
                }

                if ($e.IsGroup -and $e.MemberNames -and $e.MemberNames.Count -gt 0) {
                    $memberListHtml = ($e.MemberNames | Sort-Object | ForEach-Object {
                        $icon = if ($_ -like '[Group]*') { "&#128101;&nbsp;" } else { "&#128100;&nbsp;" }
                        "<div style='padding:2px 0'>" + $icon + (Invoke-HtmlEncode $_) + "</div>"
                    }) -join ""

                    $memberId   = "appm-" + ([System.Text.RegularExpressions.Regex]::Replace($a.Id + $e.Name, '[^a-zA-Z0-9]', '-'))
                    $memberCell = "<details id='" + $memberId + "' style='margin:0'>" +
                        "<summary style='cursor:pointer;display:flex;align-items:center;gap:6px'>" +
                        "<span style='font-weight:600'>" + $e.MemberCount + " Members</span>" +
                        "</summary>" +
                        "<div style='margin-top:6px;padding-left:12px;font-size:0.88em;color:#4a5568;line-height:1.7'>" +
                        $memberListHtml + "</div></details>"
                    New-HtmlTableRow -Cells @((Invoke-HtmlEncode $e.Name), $typeBadge, $memberCell)
                } elseif ($e.IsGroup) {
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $e.Name), $typeBadge,
                        "<span style='color:#a0aec0;font-style:italic'>0 Members</span>")
                } else {
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $e.Name), $typeBadge,
                        "<span style='color:#718096'>&#8212;</span>")
                }
            }
            $null = $content.Append((New-HtmlTable -Headers @("Name","Type","Members") -Rows $entRows))
        } else {
            $null = $content.Append("<p><em style='color:#888'>No entitlements configured</em></p>")
        }

        $null = $content.Append("</div></details>")
    }

    return New-HtmlSection -Id "application-pools" -Title "Application Pools" -Content $content.ToString()
}
