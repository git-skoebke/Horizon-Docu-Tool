# =============================================================================
# Render-LocalDesktopEntitlements — New-HtmlLocalDesktopEntitlementsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlLocalDesktopEntitlementsSection {
    param($Entitlements)
    if (-not $Entitlements -or $Entitlements.Count -eq 0) {
        return ""
    }

    # Collect all user names across all entitlements to detect duplicates
    $userToGroups = @{}
    foreach ($e in $Entitlements) {
        if ($e.MemberNames -and $e.MemberNames.Count -gt 0) {
            foreach ($userName in $e.MemberNames) {
                $key = $userName.ToLower()
                if (-not $userToGroups.ContainsKey($key)) {
                    $userToGroups[$key] = [System.Collections.Generic.List[string]]::new()
                }
                $entLabel = $e.Name + " (" + $e.PoolName + ")"
                $userToGroups[$key].Add($entLabel)
            }
        }
    }
    # Users appearing in more than one entitlement
    $duplicateUsers = @{}
    foreach ($kv in $userToGroups.GetEnumerator()) {
        if ($kv.Value.Count -gt 1) {
            $duplicateUsers[$kv.Key] = $kv.Value
        }
    }

    # Build collapsible member count cell
    $buildMemberCell = {
        param($e, [string]$idPrefix)

        if ($e.IsGroup) {
            if ($e.MemberNames -and $e.MemberNames.Count -gt 0) {
                $safeId = $idPrefix + "-" + ([System.Text.RegularExpressions.Regex]::Replace($e.Name, '[^a-zA-Z0-9]', '-'))
                $memberListHtml = ($e.MemberNames | Sort-Object | ForEach-Object {
                    $icon = if ($_ -like '[Group]*') { "&#128101;&nbsp;" } else { "&#128100;&nbsp;" }
                    "<div style='padding:2px 0'>" + $icon + (Invoke-HtmlEncode $_) + "</div>"
                }) -join ""
                return "<details id='" + $safeId + "' style='margin:0'>" +
                    "<summary style='display:flex;align-items:center;gap:6px'>" +
                    "<span style='font-weight:600'>" + $e.MemberCount + " members</span>" +
                    "</summary>" +
                    "<div style='margin-top:4px;padding-left:14px;font-size:0.88em;color:#4a5568;line-height:1.7'>" +
                    $memberListHtml + "</div></details>"
            } else {
                return "<span style='color:#a0aec0;font-style:italic'>0 members</span>"
            }
        } else {
            # Direct user — no expand needed
            return "<span>" + $e.MemberCount + "</span>"
        }
    }

    # Build main table
    $totalUsers = 0
    $rowIndex   = 0
    $rows = foreach ($e in ($Entitlements | Sort-Object PoolName, Name)) {
        $typeBadge   = if ($e.IsGroup) { New-HtmlBadge -Text "Group" -Color "neutral" } else { New-HtmlBadge -Text "User" -Color "ok" }
        $totalUsers += $e.MemberCount
        $memberCell  = & $buildMemberCell $e ("lde-$rowIndex")
        $rowIndex++
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $e.PoolName),
            (Invoke-HtmlEncode $e.Name),
            $typeBadge,
            $memberCell
        )
    }

    # Unique user count
    $allUniqueUsers = @{}
    foreach ($e in $Entitlements) {
        if ($e.MemberNames) {
            foreach ($u in $e.MemberNames) { $allUniqueUsers[$u.ToLower()] = $true }
        }
    }
    $uniqueCount = $allUniqueUsers.Count

    $footerRow  = "<tr style='font-weight:700;background:#edf2f7'><td colspan='3' style='padding:8px 12px;text-align:right'>Total Users (sum)</td><td style='padding:8px 12px'>$totalUsers</td></tr>"
    $footerRow += "<tr style='font-weight:700;background:#edf2f7'><td colspan='3' style='padding:8px 12px;text-align:right'>Unique Users</td><td style='padding:8px 12px'>$uniqueCount</td></tr>"

    $table = New-HtmlTable -Headers @("Desktop Pool","Entitlement (AD Group / User)","Type","Member Count") -Rows $rows
    $table = $table -replace '</table>', ($footerRow + '</table>')

    # Duplicate users detail
    $dupHtml = ""
    if ($duplicateUsers.Count -gt 0) {
        $dupRows = foreach ($kv in ($duplicateUsers.GetEnumerator() | Sort-Object Key)) {
            $groupList = ($kv.Value | ForEach-Object { Invoke-HtmlEncode $_ }) -join "<br>"
            New-HtmlTableRow -Cells @(
                (Invoke-HtmlEncode $kv.Key),
                "$($kv.Value.Count)",
                $groupList
            )
        }
        $dupTable   = New-HtmlTable -Headers @("User","Entitled via (count)","Entitlements") -Rows $dupRows
        $dupSummary = "" + $duplicateUsers.Count + " users in multiple entitlements"
        $dupHtml    = "<details class='inline-detail' style='margin-top:12px'><summary style='cursor:pointer;font-weight:600;color:#2b6cb0'>" + $dupSummary + " (duplicate count)</summary>" + $dupTable + "</details>"
    }

    $content = $table + $dupHtml
    return New-HtmlSection -Id "local-desktop-entitlements" -Title "Local Desktop Entitlements" -Content $content
}
