# =============================================================================
# Render-Permissions — New-HtmlPermissionsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlPermissionsSection {
    param($Permissions)
    if (-not $Permissions -or $Permissions.Count -eq 0) {
        return ""
    }

    # Build table rows — groups get a collapsible member list
    $rows = [System.Collections.Generic.List[string]]::new()

    foreach ($p in ($Permissions | Sort-Object RoleName, DisplayName)) {
        $typeBadge = if ($p.IsGroup) {
            New-HtmlBadge -Text "Group" -Color "neutral"
        } else {
            New-HtmlBadge -Text "User" -Color "ok"
        }

        if ($p.IsGroup -and $p.MemberNames -and $p.MemberNames.Count -gt 0) {
            # Aufklappbare Mitgliederliste
            $memberListHtml = ($p.MemberNames | Sort-Object | ForEach-Object {
                $icon = if ($_ -like '[Group]*') { "&#128101;&nbsp;" } else { "&#128100;&nbsp;" }
                "<div style='padding:2px 0'>" + $icon + (Invoke-HtmlEncode $_) + "</div>"
            }) -join ""

            $detailsId = "adm-grp-" + ([System.Text.RegularExpressions.Regex]::Replace($p.DisplayName, '[^a-zA-Z0-9]', '-'))

            $expandCell = "<details id='" + $detailsId + "' style='margin:0'>" +
                "<summary style='cursor:pointer;display:flex;align-items:center;gap:6px'>" +
                "<span style='font-weight:600'>" + $p.MemberCount + " Members</span>" +
                "</summary>" +
                "<div style='margin-top:6px;padding-left:12px;font-size:0.88em;color:#4a5568;line-height:1.7'>" +
                $memberListHtml +
                "</div>" +
                "</details>"

            $rows.Add((New-HtmlTableRow -Cells @(
                (Invoke-HtmlEncode $p.DisplayName),
                $typeBadge,
                (Invoke-HtmlEncode $p.RoleName),
                $expandCell
            )))
        } else {
            # Einzelner User oder leere Gruppe
            $memberCell = if ($p.IsGroup) {
                "<span style='color:#a0aec0;font-style:italic'>0 Members</span>"
            } else {
                "<span style='color:#718096'>&#8212;</span>"
            }
            $rows.Add((New-HtmlTableRow -Cells @(
                (Invoke-HtmlEncode $p.DisplayName),
                $typeBadge,
                (Invoke-HtmlEncode $p.RoleName),
                $memberCell
            )))
        }
    }

    # Footer: Gesamtanzahl
    $totalMembers = ($Permissions | Measure-Object -Property MemberCount -Sum).Sum
    $groupCount   = @($Permissions | Where-Object { $_.IsGroup }).Count
    $userCount    = @($Permissions | Where-Object { -not $_.IsGroup }).Count

    $footerRow = "<tr style='font-weight:700;background:#edf2f7'>" +
        "<td colspan='3' style='padding:8px 12px;text-align:right'>Groups: " + $groupCount +
        " &nbsp;|&nbsp; Direct Users: " + $userCount + "</td>" +
        "<td style='padding:8px 12px'>" + $totalMembers + " Total Members</td></tr>"

    $table = New-HtmlTable -Headers @("Display Name", "Type", "Role", "Members") -Rows $rows
    $table = $table -replace '</table>', ($footerRow + '</table>')

    return New-HtmlSection -Id "permissions" -Title "Administrators" -Content $table
}
