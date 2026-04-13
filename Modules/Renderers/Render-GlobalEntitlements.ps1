# =============================================================================
# Render-GlobalEntitlements — New-HtmlGlobalEntitlementsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlGlobalEntitlementsSection {
    param($GE)
    if ($null -eq $GE -or ($GE.DesktopEntitlements.Count -eq 0 -and $GE.AppEntitlements.Count -eq 0)) {
        return ""
    }

    # Build the collapsible members cell for one entitlement row
    # $adMembers = list of [PSCustomObject]@{ Name; IsGroup; MemberCount; MemberNames }
    $buildMembersCell = {
        param($adMembers, [string]$idPrefix)

        if (-not $adMembers -or $adMembers.Count -eq 0) {
            return "<em style='color:#888'>None</em>"
        }

        $parts = [System.Text.StringBuilder]::new()

        foreach ($m in $adMembers) {
            $safeId = $idPrefix + "-" + ([System.Text.RegularExpressions.Regex]::Replace($m.Name, '[^a-zA-Z0-9]', '-'))

            if ($m.IsGroup) {
                $typeBadge = New-HtmlBadge -Text "Group" -Color "neutral"

                if ($m.MemberNames -and $m.MemberNames.Count -gt 0) {
                    $memberListHtml = ($m.MemberNames | Sort-Object | ForEach-Object {
                        $icon = if ($_ -like '[Group]*') { "&#128101;&nbsp;" } else { "&#128100;&nbsp;" }
                        "<div style='padding:2px 0'>" + $icon + (Invoke-HtmlEncode $_) + "</div>"
                    }) -join ""

                    $null = $parts.Append(
                        "<details id='" + $safeId + "' style='margin-bottom:4px'>" +
                        "<summary style='display:flex;align-items:center;gap:6px'>" +
                        "<span style='font-weight:600'>" + (Invoke-HtmlEncode $m.Name) + "</span>" +
                        $typeBadge +
                        "<span style='color:#718096;font-size:11px;margin-left:2px'>" + $m.MemberCount + " members</span>" +
                        "</summary>" +
                        "<div style='margin-top:4px;padding-left:14px;font-size:0.88em;color:#4a5568;line-height:1.7'>" +
                        $memberListHtml + "</div>" +
                        "</details>"
                    )
                } else {
                    # Group with 0 resolved members
                    $null = $parts.Append(
                        "<div style='margin-bottom:4px;display:flex;align-items:center;gap:6px'>" +
                        (Invoke-HtmlEncode $m.Name) + " " + $typeBadge +
                        "<span style='color:#a0aec0;font-size:11px;font-style:italic'>0 members</span>" +
                        "</div>"
                    )
                }
            } else {
                # Direct user — no expand needed
                $typeBadge = New-HtmlBadge -Text "User" -Color "ok"
                $null = $parts.Append(
                    "<div style='margin-bottom:4px;display:flex;align-items:center;gap:6px'>" +
                    "&#128100;&nbsp;" + (Invoke-HtmlEncode $m.Name) + " " + $typeBadge +
                    "</div>"
                )
            }
        }

        return $parts.ToString()
    }

    $content = [System.Text.StringBuilder]::new()

    # -------------------------------------------------------------------------
    # Desktop Entitlements
    # -------------------------------------------------------------------------
    if ($GE.DesktopEntitlements.Count -gt 0) {
        $dRows = foreach ($d in ($GE.DesktopEntitlements | Sort-Object name)) {
            $enBadge    = if ($d.enabled) { New-HtmlBadge -Text "Enabled" -Color "ok" } else { New-HtmlBadge -Text "Disabled" -Color "neutral" }
            $idPrefix   = "gde-" + ([System.Text.RegularExpressions.Regex]::Replace("$($d.id)", '[^a-zA-Z0-9]', '-'))
            $membersHtml = & $buildMembersCell $d.AD_Members $idPrefix
            New-HtmlTableRow -Cells @(
                (Invoke-HtmlEncode $d.name),
                (Invoke-HtmlEncode $d.display_name),
                $enBadge,
                (Invoke-HtmlEncode $d.default_display_protocol),
                (Invoke-HtmlEncode $d.description),
                $membersHtml
            )
        }
        $null = $content.Append("<h3 style='margin:0 0 8px;font-size:14px;'>Desktop Entitlements</h3>")
        $null = $content.Append((New-HtmlTable -Headers @("Name","Display Name","Status","Protocol","Description","AD Groups / Users") -Rows $dRows))
    }

    # -------------------------------------------------------------------------
    # Application Entitlements
    # -------------------------------------------------------------------------
    if ($GE.AppEntitlements.Count -gt 0) {
        $aRows = foreach ($a in ($GE.AppEntitlements | Sort-Object name)) {
            $enBadge    = if ($a.enabled) { New-HtmlBadge -Text "Enabled" -Color "ok" } else { New-HtmlBadge -Text "Disabled" -Color "neutral" }
            $idPrefix   = "gae-" + ([System.Text.RegularExpressions.Regex]::Replace("$($a.id)", '[^a-zA-Z0-9]', '-'))
            $membersHtml = & $buildMembersCell $a.AD_Members $idPrefix
            New-HtmlTableRow -Cells @(
                (Invoke-HtmlEncode $a.name),
                (Invoke-HtmlEncode $a.display_name),
                $enBadge,
                (Invoke-HtmlEncode "$($a.allow_multiple_sessions_per_user)"),
                (Invoke-HtmlEncode $a.description),
                $membersHtml
            )
        }
        $null = $content.Append("<h3 style='margin:16px 0 8px;font-size:14px;'>Application Entitlements</h3>")
        $null = $content.Append((New-HtmlTable -Headers @("Name","Display Name","Status","Multi-Session","Description","AD Groups / Users") -Rows $aRows))
    }

    return New-HtmlSection -Id "global-entitlements" -Title "Global Entitlements" -Content $content.ToString()
}
