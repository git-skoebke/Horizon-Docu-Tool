# =============================================================================
# Render-AppVolumesData — New-HtmlAppVolumesDataSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function Format-AvDisplayValue {
    param($Value)
    if ($null -eq $Value) { return "" }
    $s = $Value -as [string]
    if ([string]::IsNullOrEmpty($s)) { return "" }
    return ($s -replace '\s+[+-]\d{4}\s*$','').Trim()
}

function Format-AvBytes {
    param($Bytes)
    if ($null -eq $Bytes) { return "" }
    $n = [double]$Bytes
    if ($n -lt 0) { return "" }
    $units = @('B','KB','MB','GB','TB','PB')
    $i = 0
    while ($n -ge 1024 -and $i -lt ($units.Count - 1)) { $n /= 1024; $i++ }
    return ("{0:N1} {1}" -f $n, $units[$i])
}

function New-AvSubHeader {
    param([string]$Text)
    return "<h3 style='font-size:13px;font-weight:600;margin:14px 0 5px;color:#2c5282;padding-bottom:3px;border-bottom:1px solid #d1d9e6;'>$(Invoke-HtmlEncode $Text)</h3>"
}

function New-AvBoolBadge {
    param($Value)
    if ($null -eq $Value) { return "" }
    $isTrue = ($Value -eq $true) -or ($Value -eq 'true') -or ($Value -eq 'True') -or ($Value -eq 1)
    if ($isTrue) { return (New-HtmlBadge -Text "yes" -Color "ok") }
    else         { return (New-HtmlBadge -Text "no"  -Color "neutral") }
}

function Format-AvLabel {
    # Convert key_i18n like "Enable Legacy VMC" or raw key "ENABLE_LEGACY_VMC" into a clean label.
    # Prefers the i18n label; falls back to title-casing the raw key with underscores as spaces.
    param([string]$Label, [string]$Key)
    if ($Label -and $Label -match '\S') {
        # key_i18n arrives as "Enable Foo Bar" — fine as-is, just trim
        return $Label.Trim()
    }
    if ($Key) {
        return (($Key -replace '[_]',' ')).Trim()
    }
    return ""
}

# --- Script-level counter for unique toggle IDs (reset per render call) ------
$script:_avRowId = 0

function New-AvRowId {
    $script:_avRowId++
    return "avr_$($script:_avRowId)"
}

function New-HtmlAppVolumesDataSection {
    param($AppVolumesData)

    if (-not $AppVolumesData -or $AppVolumesData.Count -eq 0) { return "" }

    $sb = [System.Text.StringBuilder]::new()
    $script:_avRowId = 0

    # One-time scoped CSS + JS for the expandable table rows.
    # The toggle function shows/hides the <tr> following the clicked header row.
    $null = $sb.Append(@'
<style>
/* Expandable table rows --------------------------------------------------- */
.av-tbl { width: 100%; border-collapse: collapse; font-size: 13px; table-layout: fixed; }
.av-tbl th { background: #2c5282; color: #fff; text-align: left;
             padding: 8px 12px; font-weight: 600; }
.av-tbl td { padding: 7px 12px; border-bottom: 1px solid #e2e8f0; vertical-align: top; }
.av-tbl tbody tr:nth-child(4n+1) td,
.av-tbl tbody tr:nth-child(4n+2) td { background: #f0f4f8; }
.av-hdr-row { cursor: pointer; user-select: none; }
.av-hdr-row:hover td { background: #e6f0fa !important; }
.av-chev-cell { width: 16px; text-align: center; font-size: 0.75em;
                padding: 7px 2px !important; color: #2c5282; }
.av-chev-cell .av-chev { display: inline-block; transition: transform 0.15s; }
.av-hdr-row.av-open .av-chev-cell .av-chev { transform: rotate(90deg); }
.av-hdr-row.av-static { cursor: default; }
.av-hdr-row.av-static .av-chev-cell { visibility: hidden; }
.av-detail-row > td { background: #fafbfd !important;
                      border-top: 1px dashed #d1d9e6;
                      padding: 10px 12px 14px 20px; }
.av-detail-row table { font-size: 12px; margin-top: 4px; width: 100%; table-layout: fixed; }
.av-detail-row table th { background: #4a6fa5; font-size: 11px; padding: 5px 8px; }
.av-detail-row table td { padding: 5px 8px; border-bottom: 1px solid #e2e8f0; background: transparent !important; }
.av-detail-row h4 { font-size: 11px; font-weight: 600; color: #2c5282;
                    margin: 8px 0 3px; text-transform: uppercase; letter-spacing: 0.04em; }
.av-detail-row h4:first-child { margin-top: 0; }
/* Print: always show details */
@media print {
  .av-detail-row { display: table-row !important; }
  .av-chev-cell::before { content: "▶"; }
}
</style>
<script>
function avToggle(id) {
  var hdr = document.getElementById('h_' + id);
  var det = document.getElementById('d_' + id);
  if (!det) return;
  var hidden = det.style.display === 'none' || det.style.display === '';
  det.style.display = hidden ? 'table-row' : 'none';
  if (hdr) hdr.classList.toggle('av-open', hidden);
}
</script>
'@)

    foreach ($mgr in $AppVolumesData) {
        $mgrTitle = Invoke-HtmlEncode $mgr.Server

        if ($mgr.LoginFailed) {
            $null = $sb.Append("<details class='detail-card' open><summary>$mgrTitle</summary>")
            $null = $sb.Append("<p style='padding:10px;color:#c53030;'>")
            $null = $sb.Append("App Volumes API login failed for $(Invoke-HtmlEncode $mgr.Server) — check credentials.")
            $null = $sb.Append("</p></details>")
            continue
        }

        $null = $sb.Append("<details class='detail-card'><summary>$mgrTitle</summary>")
        $null = $sb.Append("<div style='padding:12px 0;'>")

        # ── Version ───────────────────────────────────────────────────────
        if ($mgr.Version) {
            $v = $mgr.Version
            $rows = foreach ($prop in ($v.PSObject.Properties | Sort-Object Name)) {
                $val = $prop.Value
                if ($null -eq $val -or ($val -is [System.Collections.IEnumerable] -and $val -isnot [string])) { continue }
                New-HtmlTableRow -Cells @(
                    (Invoke-HtmlEncode $prop.Name),
                    (Invoke-HtmlEncode (Format-AvDisplayValue $val))
                )
            }
            if ($rows) {
                $null = $sb.Append((New-AvSubHeader "Version"))
                $null = $sb.Append('<table style="width:100%;table-layout:fixed;">')
                $null = $sb.Append('<colgroup><col style="width:35%"><col style="width:65%"></colgroup>')
                $null = $sb.Append('<thead><tr><th>Property</th><th>Value</th></tr></thead><tbody>')
                foreach ($row in $rows) { $null = $sb.Append($row) }
                $null = $sb.Append('</tbody></table>')
            }
        }

        # ── Applications ──────────────────────────────────────────────────
        # Each Application = one clickable header row; click reveals detail row with
        # Packages + Assignments sub-tables. Uses onclick toggle — no CSS grid tricks.
        if ($mgr.AppProducts -and $mgr.AppProducts.Count -gt 0) {
            $null = $sb.Append((New-AvSubHeader "Applications"))
            $null = $sb.Append('<table class="av-tbl">')
            $null = $sb.Append('<colgroup><col style="width:28px"><col style="width:24%"><col><col style="width:90px"><col style="width:160px"></colgroup>')
            $null = $sb.Append('<thead><tr><th></th><th>Name</th><th>Description</th><th>Status</th><th>Last Updated</th></tr></thead><tbody>')

            foreach ($prod in $mgr.AppProducts) {
                $rid = New-AvRowId
                $statusBadge = switch -Wildcard (($prod.Status -as [string]).ToLower()) {
                    "*active*"   { New-HtmlBadge -Text $prod.Status -Color "ok" }
                    "*enabled*"  { New-HtmlBadge -Text $prod.Status -Color "ok" }
                    "*disabled*" { New-HtmlBadge -Text $prod.Status -Color "neutral" }
                    default      { Invoke-HtmlEncode $prod.Status }
                }

                $pkgCount = @($prod.Packages).Count
                $asnCount = @($prod.Assignments).Count
                $hasDetail = ($pkgCount -gt 0) -or ($asnCount -gt 0)
                $rowClass = if ($hasDetail) { "av-hdr-row" } else { "av-hdr-row av-static" }
                $clickAttr = if ($hasDetail) { " onclick=""avToggle('$rid')"" id=""h_$rid""" } else { "" }

                $null = $sb.Append("<tr class='$rowClass'$clickAttr>")
                $null = $sb.Append("<td class='av-chev-cell'><span class='av-chev'>&#9654;</span></td>")
                $null = $sb.Append("<td>$(Invoke-HtmlEncode $prod.Name)</td>")
                $null = $sb.Append("<td>$(Invoke-HtmlEncode $prod.Description)</td>")
                $null = $sb.Append("<td>$statusBadge</td>")
                $null = $sb.Append("<td style='white-space:nowrap'>$(Invoke-HtmlEncode $prod.Updated)</td>")
                $null = $sb.Append("</tr>")

                if ($hasDetail) {
                    $null = $sb.Append("<tr class='av-detail-row' id='d_$rid' style='display:none'>")
                    $null = $sb.Append("<td colspan='5'>")

                    if ($pkgCount -gt 0) {
                        $null = $sb.Append("<h4>Packages ($pkgCount)</h4>")
                        $pkgRows = foreach ($p in $prod.Packages) {
                            $pkgStatus = switch -Wildcard (($p.Status -as [string]).ToLower()) {
                                "*enabled*"  { New-HtmlBadge -Text $p.Status -Color "ok" }
                                "*disabled*" { New-HtmlBadge -Text $p.Status -Color "neutral" }
                                default      { Invoke-HtmlEncode $p.Status }
                            }
                            $sizeTxt = if ($p.SizeMb) { "$($p.SizeMb) MB" } else { "" }
                            New-HtmlTableRow -Cells @(
                                (Invoke-HtmlEncode $p.Name),
                                (Invoke-HtmlEncode $p.Version),
                                $pkgStatus,
                                (Invoke-HtmlEncode $p.Delivery),
                                (Invoke-HtmlEncode $p.OS),
                                (Invoke-HtmlEncode $p.AgentVersion),
                                (Invoke-HtmlEncode $sizeTxt),
                                (Invoke-HtmlEncode $p.Updated)
                            )
                        }
                        $null = $sb.Append((New-HtmlTable -Headers @("Package","Version","Status","Delivery","Base OS","Agent","Size","Updated") -Rows $pkgRows))
                    }

                    if ($asnCount -gt 0) {
                        $null = $sb.Append("<h4>Assignments ($asnCount)</h4>")
                        $asnRows = foreach ($a in $prod.Assignments) {
                            $pkgMarker = if ($a.PackageName -and $a.MarkerName) { "$($a.PackageName) / $($a.MarkerName)" }
                                         elseif ($a.PackageName) { $a.PackageName }
                                         elseif ($a.MarkerName)  { $a.MarkerName }
                                         else                    { "" }
                            New-HtmlTableRow -Cells @(
                                (Invoke-HtmlEncode $a.EntityName),
                                (Invoke-HtmlEncode $a.EntityType),
                                (Invoke-HtmlEncode $pkgMarker),
                                (Invoke-HtmlEncode $a.DistinguishedName),
                                (Invoke-HtmlEncode $a.AssignedAt)
                            )
                        }
                        $null = $sb.Append((New-HtmlTable -Headers @("Entity","Type","Package / Marker","Distinguished Name","Assigned At") -Rows $asnRows))
                    }

                    $null = $sb.Append("</td></tr>")
                }
            }

            $null = $sb.Append("</tbody></table>")
        }

        # ── All Assignments — grouped by Application, each app is a toggleable row ─
        if ($mgr.Assignments -and $mgr.Assignments.Count -gt 0) {
            $null = $sb.Append((New-AvSubHeader "All Assignments"))

            # Group assignments by ProductName
            $byProduct = $mgr.Assignments | Group-Object ProductName
            $null = $sb.Append('<table class="av-tbl">')
            $null = $sb.Append('<colgroup><col style="width:28px"><col style="width:42%"><col></colgroup>')
            $null = $sb.Append('<thead><tr><th></th><th>Application</th><th>Assignments</th></tr></thead><tbody>')

            foreach ($grp in ($byProduct | Sort-Object Name)) {
                $rid = New-AvRowId
                $asnList = @($grp.Group)
                $userCount  = ($asnList | Where-Object { $_.EntityType -eq 'User'  }).Count
                $groupCount = ($asnList | Where-Object { $_.EntityType -eq 'Group' }).Count
                $parts = @()
                if ($userCount  -gt 0) { $parts += "$userCount user$(if($userCount -gt 1){'s'})" }
                if ($groupCount -gt 0) { $parts += "$groupCount group$(if($groupCount -gt 1){'s'})" }
                $otherCount = $asnList.Count - $userCount - $groupCount
                if ($otherCount -gt 0) { $parts += "$otherCount other" }
                $summary = if ($parts) { $parts -join ", " } else { "$($asnList.Count) assignment$(if($asnList.Count -ne 1){'s'})" }

                $null = $sb.Append("<tr class='av-hdr-row' onclick=""avToggle('$rid')"" id='h_$rid'>")
                $null = $sb.Append("<td class='av-chev-cell'><span class='av-chev'>&#9654;</span></td>")
                $null = $sb.Append("<td><strong>$(Invoke-HtmlEncode $grp.Name)</strong></td>")
                $null = $sb.Append("<td>$(Invoke-HtmlEncode $summary)</td>")
                $null = $sb.Append("</tr>")

                $null = $sb.Append("<tr class='av-detail-row' id='d_$rid' style='display:none'>")
                $null = $sb.Append("<td colspan='3'>")
                $asnRows = foreach ($a in $asnList) {
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $a.EntityName),
                        (Invoke-HtmlEncode $a.EntityType),
                        (Invoke-HtmlEncode $a.DistinguishedName),
                        (Invoke-HtmlEncode $a.AssignedAt)
                    )
                }
                $null = $sb.Append((New-HtmlTable -Headers @("Entity","Type","Distinguished Name","Assigned At") -Rows $asnRows))
                $null = $sb.Append("</td></tr>")
            }

            $null = $sb.Append("</tbody>")

            # Footer row: unique direct users + unique groups across all applications.
            # Deduplication is by EntityName (case-insensitive) — a user assigned to multiple
            # apps is counted once. Groups are listed separately because their member count
            # is not available from the API.
            $uniqueUsers = @($mgr.Assignments |
                Where-Object { $_.EntityType -eq 'User' } |
                ForEach-Object { $_.EntityName.ToLower() } |
                Sort-Object -Unique)
            $uniqueGroups = @($mgr.Assignments |
                Where-Object { $_.EntityType -eq 'Group' } |
                ForEach-Object { $_.EntityName.ToLower() } |
                Sort-Object -Unique)
            $footerParts = @()
            if ($uniqueUsers.Count  -gt 0) { $footerParts += "$($uniqueUsers.Count) unique user$(if($uniqueUsers.Count -ne 1){'s'})" }
            if ($uniqueGroups.Count -gt 0) { $footerParts += "$($uniqueGroups.Count) unique group$(if($uniqueGroups.Count -ne 1){'s'})" }
            $footerText = if ($footerParts) { "Total: " + ($footerParts -join ", ") } else { "" }
            if ($footerText) {
                $null = $sb.Append("<tfoot><tr>")
                $null = $sb.Append("<td colspan='3' style='text-align:right;font-weight:600;font-size:12px;")
                $null = $sb.Append("color:#2c5282;padding:8px 12px;border-top:2px solid #d1d9e6;background:#f7f9fc;'>")
                $null = $sb.Append((Invoke-HtmlEncode $footerText))
                $null = $sb.Append("</td></tr></tfoot>")
            }
            $null = $sb.Append("</table>")
        }

        # ── Writables ─────────────────────────────────────────────────────
        if ($mgr.Writables -and $mgr.Writables.Count -gt 0) {
            $rows = foreach ($w in $mgr.Writables) {
                $statusBadge = switch -Wildcard (($w.Status -as [string]).ToLower()) {
                    "*enabled*"  { New-HtmlBadge -Text $w.Status -Color "ok" }
                    "*disabled*" { New-HtmlBadge -Text $w.Status -Color "neutral" }
                    "*error*"    { New-HtmlBadge -Text $w.Status -Color "error" }
                    default      { Invoke-HtmlEncode $w.Status }
                }
                $sizeMb = if ($w.Size) { "$($w.Size) MB" } else { "" }
                New-HtmlTableRow -Cells @(
                    (Invoke-HtmlEncode $w.Name),
                    (Invoke-HtmlEncode $w.Owner),
                    (Invoke-HtmlEncode $w.OwnerType),
                    $statusBadge,
                    (Invoke-HtmlEncode $w.Datastore),
                    (Invoke-HtmlEncode $sizeMb)
                )
            }
            $null = $sb.Append((New-AvSubHeader "Writables"))
            $null = $sb.Append((New-HtmlTable -Headers @("Name","Owner","Type","Status","Datastore","Size") -Rows $rows))
        }

        # ── License ────────────────────────────────────────────────────────
        if ($mgr.License) {
            $null = $sb.Append((New-AvSubHeader "License"))
            $lname   = if ($mgr.License.Name) { $mgr.License.Name } else { "(no license)" }
            $lstatus = if ($mgr.License.Invalid) { New-HtmlBadge -Text "invalid" -Color "error" }
                       else                      { New-HtmlBadge -Text "valid"   -Color "ok" }
            $null = $sb.Append("<p style='margin:4px 0 8px;'><strong>$(Invoke-HtmlEncode $lname)</strong> &nbsp; $lstatus</p>")

            if (@($mgr.License.Details).Count -gt 0) {
                $rows = foreach ($d in $mgr.License.Details) {
                    if ([string]::IsNullOrWhiteSpace($d.Value)) { continue }
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $d.Key),
                        (Invoke-HtmlEncode $d.Value)
                    )
                }
                $null = $sb.Append('<table style="width:100%;table-layout:fixed;">')
                $null = $sb.Append('<colgroup><col style="width:35%"><col style="width:65%"></colgroup>')
                $null = $sb.Append('<thead><tr><th>Property</th><th>Value</th></tr></thead><tbody>')
                foreach ($r in $rows) { $null = $sb.Append($r) }
                $null = $sb.Append('</tbody></table>')
            }

            if (@($mgr.License.Features).Count -gt 0) {
                $null = $sb.Append("<h4 style='font-size:12px;font-weight:600;margin:10px 0 4px;color:#4a6fa5;'>Features</h4>")
                $rows = foreach ($f in ($mgr.License.Features | Sort-Object Name)) {
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $f.Name),
                        (New-AvBoolBadge $f.Enabled)
                    )
                }
                $null = $sb.Append((New-HtmlTable -Headers @("Feature","Enabled") -Rows $rows))
            }

            if (@($mgr.LicenseUsage).Count -gt 0) {
                $null = $sb.Append("<h4 style='font-size:12px;font-weight:600;margin:10px 0 4px;color:#4a6fa5;'>Usage</h4>")
                $rows = foreach ($u in $mgr.LicenseUsage) {
                    $capTxt = if ($null -eq $u.Cap) { "unlimited" } else { ($u.Cap -as [string]) }
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $u.Label),
                        (Invoke-HtmlEncode ($u.Used -as [string])),
                        (Invoke-HtmlEncode $capTxt)
                    )
                }
                $null = $sb.Append((New-HtmlTable -Headers @("License Type","In Use","Cap") -Rows $rows))
            }
        }

        # ── Domains ────────────────────────────────────────────────────────
        if (@($mgr.LdapDomains).Count -gt 0) {
            $null = $sb.Append((New-AvSubHeader "Domains"))
            $rows = foreach ($d in $mgr.LdapDomains) {
                $secTxt = if ($d.Ldaps) { "LDAPS" } elseif ($d.LdapTls) { "LDAP+TLS" } else { "LDAP" }
                New-HtmlTableRow -Cells @(
                    (Invoke-HtmlEncode $d.Domain),
                    (Invoke-HtmlEncode $d.NetBIOS),
                    (Invoke-HtmlEncode $d.Hosts),
                    (Invoke-HtmlEncode $d.Username),
                    (Invoke-HtmlEncode $d.Base),
                    (Invoke-HtmlEncode $secTxt),
                    (Invoke-HtmlEncode ($d.Port -as [string])),
                    (New-AvBoolBadge $d.SslVerify),
                    (Invoke-HtmlEncode $d.Updated)
                )
            }
            $null = $sb.Append((New-HtmlTable -Headers @("Domain","NetBIOS","Hosts","Service Account","Base DN","Security","Port","SSL Verify","Updated") -Rows $rows))
        }

        # ── Admin Roles ────────────────────────────────────────────────────
        if (@($mgr.AdminAssignments).Count -gt 0 -or @($mgr.AdminRoles).Count -gt 0) {
            $null = $sb.Append((New-AvSubHeader "Admin Roles"))

            if (@($mgr.AdminAssignments).Count -gt 0) {
                $null = $sb.Append("<h4 style='font-size:12px;font-weight:600;margin:6px 0 4px;color:#4a6fa5;'>Assigned Administrators</h4>")
                $rows = foreach ($a in $mgr.AdminAssignments) {
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $a.Role),
                        (Invoke-HtmlEncode $a.AssigneeName),
                        (Invoke-HtmlEncode $a.AssigneeType),
                        (Invoke-HtmlEncode $a.DistinguishedName),
                        (Invoke-HtmlEncode $a.Created)
                    )
                }
                $null = $sb.Append((New-HtmlTable -Headers @("Role","Assignee","Type","Distinguished Name","Assigned At") -Rows $rows))
            }

            if (@($mgr.AdminRoles).Count -gt 0) {
                $null = $sb.Append("<h4 style='font-size:12px;font-weight:600;margin:10px 0 4px;color:#4a6fa5;'>Role Definitions</h4>")
                $null = $sb.Append('<table class="av-tbl">')
                $null = $sb.Append('<colgroup><col style="width:28px"><col style="width:22%"><col><col style="width:110px"><col style="width:90px"></colgroup>')
                $null = $sb.Append('<thead><tr><th></th><th>Name</th><th>Description</th><th>Type</th><th>Predefined</th></tr></thead><tbody>')

                foreach ($r in $mgr.AdminRoles) {
                    $rid    = New-AvRowId
                    $predef = if ($r.Predefined) { New-HtmlBadge -Text "built-in" -Color "neutral" }
                              else               { New-HtmlBadge -Text "custom"   -Color "ok" }
                    $permCount = @($r.Permissions).Count
                    $isCatchAll = ($permCount -eq 0) -and $r.Predefined
                    $hasDetail  = ($permCount -gt 0) -or $isCatchAll
                    $rowClass   = if ($hasDetail) { "av-hdr-row" } else { "av-hdr-row av-static" }
                    $clickAttr  = if ($hasDetail) { " onclick=""avToggle('$rid')"" id=""h_$rid""" } else { "" }

                    $null = $sb.Append("<tr class='$rowClass'$clickAttr>")
                    $null = $sb.Append("<td class='av-chev-cell'><span class='av-chev'>&#9654;</span></td>")
                    $null = $sb.Append("<td>$(Invoke-HtmlEncode $r.Name)</td>")
                    $null = $sb.Append("<td>$(Invoke-HtmlEncode $r.Description)</td>")
                    $null = $sb.Append("<td>$(Invoke-HtmlEncode $r.Type)</td>")
                    $null = $sb.Append("<td>$predef</td>")
                    $null = $sb.Append("</tr>")

                    if ($hasDetail) {
                        $null = $sb.Append("<tr class='av-detail-row' id='d_$rid' style='display:none'>")
                        $null = $sb.Append("<td colspan='5'>")
                        if ($permCount -gt 0) {
                            $null = $sb.Append("<h4>Permissions ($permCount)</h4>")
                            $null = $sb.Append("<ul style='columns:2;margin:4px 0 0 16px;font-size:12px;list-style:disc;'>")
                            foreach ($p in $r.Permissions) {
                                $null = $sb.Append("<li>$(Invoke-HtmlEncode $p)</li>")
                            }
                            $null = $sb.Append("</ul>")
                        } else {
                            $hint = if ($r.Name -like "*Read only*") { "Grants read access to all configuration, logs and user-created objects." }
                                    else                             { "Grants all permissions (full administrative access)." }
                            $null = $sb.Append("<p style='margin:4px 0;font-size:12px;color:#4a5568;font-style:italic;'>$(Invoke-HtmlEncode $hint)</p>")
                        }
                        $null = $sb.Append("</td></tr>")
                    }
                }

                $null = $sb.Append("</tbody></table>")
            }
        }

        # ── Storage ────────────────────────────────────────────────────────
        $hasStorage = $mgr.StorageDefaults -or @($mgr.StorageDatastores).Count -gt 0 -or
                      @($mgr.Storages).Count -gt 0 -or @($mgr.StorageGroups).Count -gt 0
        if ($hasStorage) {
            $null = $sb.Append((New-AvSubHeader "Storage"))

            if (@($mgr.StorageDatastores).Count -gt 0) {
                $null = $sb.Append("<h4 style='font-size:12px;font-weight:600;margin:6px 0 4px;color:#4a6fa5;'>Datastores</h4>")
                $rows = foreach ($d in $mgr.StorageDatastores) {
                    $capTxt  = Format-AvBytes $d.Capacity
                    $freeTxt = Format-AvBytes $d.FreeSpace
                    $usedPct = if ($d.Capacity -gt 0) {
                        "$([math]::Round((1 - $d.FreeSpace / $d.Capacity) * 100, 1))%"
                    } else { "" }
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $d.Name),
                        (Invoke-HtmlEncode $d.Category),
                        (Invoke-HtmlEncode $d.Description),
                        (New-AvBoolBadge $d.Accessible),
                        (Invoke-HtmlEncode $capTxt),
                        (Invoke-HtmlEncode $freeTxt),
                        (Invoke-HtmlEncode $usedPct)
                    )
                }
                $null = $sb.Append((New-HtmlTable -Headers @("Name","Category","Description","Accessible","Capacity","Free","Used") -Rows $rows))
            }

            if (@($mgr.Storages).Count -gt 0) {
                $null = $sb.Append("<h4 style='font-size:12px;font-weight:600;margin:10px 0 4px;color:#4a6fa5;'>Storage Shares</h4>")
                $rows = foreach ($s in $mgr.Storages) {
                    $statusBadge = switch -Wildcard (($s.Status -as [string]).ToLower()) {
                        "*existing*" { New-HtmlBadge -Text $s.Status -Color "ok" }
                        "*error*"    { New-HtmlBadge -Text $s.Status -Color "error" }
                        default      { Invoke-HtmlEncode $s.Status }
                    }
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $s.Name),
                        $statusBadge,
                        (New-AvBoolBadge $s.Attachable),
                        (Invoke-HtmlEncode $s.SpaceUsedDisplay),
                        (Invoke-HtmlEncode $s.SpaceTotalDisplay),
                        (Invoke-HtmlEncode ($s.NumPackages  -as [string])),
                        (Invoke-HtmlEncode ($s.NumAppStacks -as [string])),
                        (Invoke-HtmlEncode ($s.NumWritables -as [string])),
                        (Invoke-HtmlEncode $s.Created)
                    )
                }
                $null = $sb.Append((New-HtmlTable -Headers @("Share","Status","Attachable","Used","Total","Packages","AppStacks","Writables","Added") -Rows $rows))
            }

            if (@($mgr.StorageGroups).Count -gt 0) {
                $null = $sb.Append("<h4 style='font-size:12px;font-weight:600;margin:10px 0 4px;color:#4a6fa5;'>Storage Groups</h4>")
                $null = $sb.Append('<table class="av-tbl">')
                $null = $sb.Append('<colgroup><col style="width:16px"><col style="width:22%"><col style="width:14%"><col style="width:14%"><col style="width:10%"><col style="width:10%"><col style="width:10%"><col style="width:14%"></colgroup>')
                $null = $sb.Append('<thead><tr><th style="padding:8px 2px"></th><th>Name</th><th>Strategy</th><th>Template Storage</th><th>Members</th><th>Used</th><th>Total</th><th>Created</th></tr></thead><tbody>')

                foreach ($sg in $mgr.StorageGroups) {
                    $rid = New-AvRowId
                    $memberCount = @($sg.Members).Count
                    $hasDetail = $memberCount -gt 0

                    $rowClass = if ($hasDetail) { "av-hdr-row" } else { "av-hdr-row av-static" }
                    $clickAttr = if ($hasDetail) { " onclick=""avToggle('$rid')"" id=""h_$rid""" } else { "" }

                    $replicateBadge = New-AvBoolBadge $sg.AutoReplicate
                    $importBadge    = New-AvBoolBadge $sg.AutoImport

                    $null = $sb.Append("<tr class='$rowClass'$clickAttr>")
                    $null = $sb.Append("<td class='av-chev-cell'><span class='av-chev'>&#9654;</span></td>")
                    $null = $sb.Append("<td>$(Invoke-HtmlEncode $sg.Name)</td>")
                    $null = $sb.Append("<td>$(Invoke-HtmlEncode $sg.Strategy)</td>")
                    $null = $sb.Append("<td>$(Invoke-HtmlEncode $sg.TemplateStorage)</td>")
                    $null = $sb.Append("<td>$($sg.MemberCount)</td>")
                    $null = $sb.Append("<td>$(Invoke-HtmlEncode $sg.SpaceUsed)</td>")
                    $null = $sb.Append("<td>$(Invoke-HtmlEncode $sg.SpaceTotal)</td>")
                    $null = $sb.Append("<td style='white-space:nowrap'>$(Invoke-HtmlEncode $sg.Created)</td>")
                    $null = $sb.Append("</tr>")

                    if ($hasDetail) {
                        $null = $sb.Append("<tr class='av-detail-row' id='d_$rid' style='display:none'>")
                        $null = $sb.Append("<td colspan='8'>")

                        # Detail info
                        $null = $sb.Append("<h4>Settings</h4>")
                        $null = $sb.Append('<table style="width:100%;table-layout:fixed;">')
                        $null = $sb.Append('<colgroup><col style="width:35%"><col style="width:65%"></colgroup>')
                        $null = $sb.Append('<thead><tr><th>Setting</th><th>Value</th></tr></thead><tbody>')
                        $null = $sb.Append((New-HtmlTableRow -Cells @("Auto Replicate", $replicateBadge)))
                        $null = $sb.Append((New-HtmlTableRow -Cells @("Auto Import", $importBadge)))
                        if ($sg.ReplicatedAt) {
                            $null = $sb.Append((New-HtmlTableRow -Cells @("Last Replicated", (Invoke-HtmlEncode $sg.ReplicatedAt))))
                        }
                        if ($sg.ImportedAt) {
                            $null = $sb.Append((New-HtmlTableRow -Cells @("Last Imported", (Invoke-HtmlEncode $sg.ImportedAt))))
                        }
                        $null = $sb.Append('</tbody></table>')

                        # Members table
                        $null = $sb.Append("<h4>Members ($memberCount)</h4>")
                        $memberRows = foreach ($m in $sg.Members) {
                            $deletedBadge = if ($m.Deleted) { New-HtmlBadge -Text "Deleted" -Color "error" } else { New-HtmlBadge -Text "Active" -Color "ok" }
                            New-HtmlTableRow -Cells @(
                                (Invoke-HtmlEncode $m.Name),
                                (Invoke-HtmlEncode $m.Datacenter),
                                (Invoke-HtmlEncode $m.SpaceUsed),
                                (Invoke-HtmlEncode $m.SpaceTotal),
                                $deletedBadge
                            )
                        }
                        $null = $sb.Append((New-HtmlTable -Headers @("Storage","Datacenter","Used","Total","Status") -Rows $memberRows))

                        $null = $sb.Append("</td></tr>")
                    }
                }

                $null = $sb.Append("</tbody></table>")
            }

            if ($mgr.StorageDefaults) {
                $null = $sb.Append("<h4 style='font-size:12px;font-weight:600;margin:10px 0 4px;color:#4a6fa5;'>Default Paths</h4>")
                $rows = foreach ($p in ($mgr.StorageDefaults.PSObject.Properties)) {
                    if ([string]::IsNullOrWhiteSpace($p.Value) -or $p.Value -match '^\|+$') { continue }
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $p.Name),
                        (Invoke-HtmlEncode ($p.Value -as [string]))
                    )
                }
                if ($rows) {
                    $null = $sb.Append('<table style="width:100%;table-layout:fixed;">')
                    $null = $sb.Append('<colgroup><col style="width:35%"><col style="width:65%"></colgroup>')
                    $null = $sb.Append('<thead><tr><th>Setting</th><th>Value</th></tr></thead><tbody>')
                    foreach ($r in $rows) { $null = $sb.Append($r) }
                    $null = $sb.Append('</tbody></table>')
                }
            }
        }

        # ── Machine Managers ───────────────────────────────────────────────
        if (@($mgr.MachineManagers).Count -gt 0) {
            $null = $sb.Append((New-AvSubHeader "Machine Managers"))
            $rows = foreach ($m in $mgr.MachineManagers) {
                New-HtmlTableRow -Cells @(
                    (Invoke-HtmlEncode $m.Name),
                    (Invoke-HtmlEncode $m.Host),
                    (Invoke-HtmlEncode $m.Type),
                    (Invoke-HtmlEncode $m.AdapterType),
                    (Invoke-HtmlEncode $m.Username),
                    (Invoke-HtmlEncode $m.Datacenter),
                    (Invoke-HtmlEncode $m.Status),
                    (Invoke-HtmlEncode $m.Updated)
                )
            }
            $null = $sb.Append((New-HtmlTable -Headers @("Name","Host","Type","Adapter","Username","Datacenter","Status","Updated") -Rows $rows))
        }

        # ── Managers (App Volumes Manager instances) ───────────────────────
        if (@($mgr.ManagerServices).Count -gt 0) {
            $null = $sb.Append((New-AvSubHeader "Managers"))
            $rows = foreach ($m in $mgr.ManagerServices) {
                $statusBadge = switch -Wildcard (($m.Status -as [string]).ToLower()) {
                    "*registered*" { New-HtmlBadge -Text $m.Status -Color "ok" }
                    "*pending*"    { New-HtmlBadge -Text $m.Status -Color "warn" }
                    "*error*"      { New-HtmlBadge -Text $m.Status -Color "error" }
                    default        { Invoke-HtmlEncode $m.Status }
                }
                New-HtmlTableRow -Cells @(
                    (Invoke-HtmlEncode $m.Name),
                    (Invoke-HtmlEncode $m.Fqdn),
                    (Invoke-HtmlEncode $m.ProductVersion),
                    $statusBadge,
                    (New-AvBoolBadge $m.Secure),
                    (Invoke-HtmlEncode $m.LogLevel),
                    (Invoke-HtmlEncode $m.FirstSeen),
                    (Invoke-HtmlEncode $m.LastSeen)
                )
            }
            $null = $sb.Append((New-HtmlTable -Headers @("Name","FQDN","Version","Status","Secure","Log Level","First Seen","Last Seen") -Rows $rows))
        }

        # ── Settings ───────────────────────────────────────────────────────
        # Rendered in three groups: Feature Flags (feature), Settings (setting), Advanced Settings.
        # Bot Configuration, RBAC Settings, and Internal (hash) are omitted — not relevant for docs.
        # Label comes from key_i18n; raw key used as fallback.
        # feature + setting are shown as separate groups — features are runtime toggles,
        # settings are configuration values. No de-duplication needed as they serve different purposes.
        if (@($mgr.Settings).Count -gt 0) {
            $null = $sb.Append((New-AvSubHeader "Settings"))

            $showTypes = @('feature', 'setting', 'advanced_setting')
            $typeLabels = @{
                'feature'          = 'Feature Flags'
                'setting'          = 'Configuration'
                'advanced_setting' = 'Advanced Settings'
            }

            foreach ($type in $showTypes) {
                $items = $mgr.Settings | Where-Object { $_.Type -eq $type }
                if (-not $items) { continue }
                $itemArr = @($items)
                $null = $sb.Append("<h4 style='font-size:12px;font-weight:600;margin:10px 0 4px;color:#4a6fa5;'>$($typeLabels[$type]) ($($itemArr.Count))</h4>")

                $rows = foreach ($s in ($itemArr | Sort-Object { Format-AvLabel $_.Label $_.Key })) {
                    $displayLabel = Invoke-HtmlEncode (Format-AvLabel $s.Label $s.Key)
                    $valCell = if ($s.InputType -eq 'checkbox' -and ($s.Value -eq 'true' -or $s.Value -eq 'false')) {
                        New-AvBoolBadge $s.Value
                    } else {
                        Invoke-HtmlEncode $s.Value
                    }
                    New-HtmlTableRow -Cells @(
                        $displayLabel,
                        $valCell,
                        (Invoke-HtmlEncode $s.Changed)
                    )
                }
                $null = $sb.Append((New-HtmlTable -Headers @("Setting","Value","Last Changed") -Rows $rows))
            }
        }

        $null = $sb.Append("</div></details>")
    }

    return New-HtmlSection -Id "app-volumes-data" -Title "App Volumes — Detailed Configuration" -Content ($sb.ToString())
}
