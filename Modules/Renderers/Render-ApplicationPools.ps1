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

    # ------------------------------------------------------------------
    # Overview table — Name | Display Name | Farm | Status only
    # ------------------------------------------------------------------
    $ovRows = foreach ($a in ($AppPools | Sort-Object FarmName, Name)) {
        $statusBadge = if ($a.Enabled -eq "True") {
            New-HtmlBadge -Text "Enabled" -Color "ok"
        } else {
            New-HtmlBadge -Text "Disabled" -Color "neutral"
        }
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $a.Name),
            (Invoke-HtmlEncode $a.DisplayName),
            (Invoke-HtmlEncode $a.FarmName),
            $statusBadge
        )
    }
    $null = $content.Append((New-HtmlTable -Headers @("Name","Display Name","Farm","Status") -Rows $ovRows))

    # ------------------------------------------------------------------
    # Per-application detail cards
    # ------------------------------------------------------------------
    foreach ($a in ($AppPools | Sort-Object FarmName, Name)) {
        $enabledBadge = if ($a.Enabled -eq "True") {
            New-HtmlBadge -Text "Enabled" -Color "ok"
        } else {
            New-HtmlBadge -Text "Disabled" -Color "neutral"
        }

        $detailsId = "app-" + ([System.Text.RegularExpressions.Regex]::Replace($a.Id, '[^a-zA-Z0-9]', '-'))

        $null = $content.Append(
            "<details class='pool-detail' id='" + $detailsId + "' style='margin-top:16px;border:1px solid #d1d9e6;border-radius:4px;'>")
        $null = $content.Append(
            "<summary style='padding:10px 14px;font-weight:600;cursor:pointer;background:#f7f9fc;border-radius:4px;'>" +
            (Invoke-HtmlEncode $a.Name) + " &nbsp;" + $enabledBadge +
            " &nbsp;<span style='font-weight:400;color:#718096;font-size:12px'>" + (Invoke-HtmlEncode $a.FarmName) + "</span>" +
            "</summary>")
        $null = $content.Append("<div style='padding:14px 18px;'>")

        # --- Details ---
        $detailRows = [System.Collections.Generic.List[string]]::new()

        # id
        $detailRows.Add((New-HtmlTableRow -Cells @("ID",             (Invoke-HtmlEncode $a.Id))))
        # name / display_name
        $detailRows.Add((New-HtmlTableRow -Cells @("Name",           (Invoke-HtmlEncode $a.Name))))
        $detailRows.Add((New-HtmlTableRow -Cells @("Display Name",   (Invoke-HtmlEncode $a.DisplayName))))
        # enabled
        $detailRows.Add((New-HtmlTableRow -Cells @("Enabled",        $enabledBadge)))
        # farm_name
        $detailRows.Add((New-HtmlTableRow -Cells @("Farm",           (Invoke-HtmlEncode $a.FarmName))))
        # executable_path
        $detailRows.Add((New-HtmlTableRow -Cells @("Executable Path",(Invoke-HtmlEncode $a.ExecutablePath))))
        # enable_pre_launch
        if ($a.EnablePreLaunch -ne "") {
            $plBadge = if ($a.EnablePreLaunch -eq "True") {
                New-HtmlBadge -Text "Yes" -Color "ok"
            } else {
                New-HtmlBadge -Text "No" -Color "neutral"
            }
            $detailRows.Add((New-HtmlTableRow -Cells @("Pre-Launch",  $plBadge)))
        }
        # enable_client_restriction
        if ($a.EnableClientRestr -ne "") {
            $crBadge = if ($a.EnableClientRestr -eq "True") {
                New-HtmlBadge -Text "Yes" -Color "warn"
            } else {
                New-HtmlBadge -Text "No" -Color "neutral"
            }
            $detailRows.Add((New-HtmlTableRow -Cells @("Client Restriction", $crBadge)))
        }
        # status
        if ($a.AppStatus -and $a.AppStatus -ne "") {
            $stColor = switch ($a.AppStatus) {
                "OK"      { "ok" }
                "WARNING" { "warn" }
                "ERROR"   { "error" }
                default   { "neutral" }
            }
            $detailRows.Add((New-HtmlTableRow -Cells @("Status", (New-HtmlBadge -Text $a.AppStatus -Color $stColor))))
        }
        # allow_users_to_choose_machines
        if ($a.AllowChooseMachines -ne "") {
            $acmBadge = if ($a.AllowChooseMachines -eq "True") {
                New-HtmlBadge -Text "Yes" -Color "ok"
            } else {
                New-HtmlBadge -Text "No" -Color "neutral"
            }
            $detailRows.Add((New-HtmlTableRow -Cells @("Allow Users to Choose Machines", $acmBadge)))
        }
        # publisher / version
        if ($a.Publisher -and $a.Publisher -ne "") {
            $detailRows.Add((New-HtmlTableRow -Cells @("Publisher", (Invoke-HtmlEncode $a.Publisher))))
        }
        if ($a.Version -and $a.Version -ne "") {
            $detailRows.Add((New-HtmlTableRow -Cells @("Version",   (Invoke-HtmlEncode $a.Version))))
        }

        $null = $content.Append((New-HtmlTable -Headers @("Property","Value") -Rows $detailRows))

        # --- Entitlements ---
        $null = $content.Append("<h4 style='margin:14px 0 8px;font-size:13px;color:#2c5282;'>Entitlements</h4>")
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
