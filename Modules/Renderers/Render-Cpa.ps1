# =============================================================================
# Render-Cpa — New-HtmlCpaSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlCpaSection {
    param($Cpa)
    if ($null -eq $Cpa -or $null -eq $Cpa.CpaInfo) {
        return ""
    }
    $content = [System.Text.StringBuilder]::new()
    $ci = $Cpa.CpaInfo

    # Overview: name, GUID, status, member sites, site redirection
    $statusBadge = switch ($ci.LocalCsStatus) {
        "ENABLED"  { New-HtmlBadge -Text "ENABLED"  -Color "ok" }
        "DISABLED" { New-HtmlBadge -Text "DISABLED" -Color "neutral" }
        default    { New-HtmlBadge -Text "$($ci.LocalCsStatus)" -Color "neutral" }
    }
    $overviewRows = @(
        (New-HtmlTableRow -Cells @("Pod Name",                   (Invoke-HtmlEncode $ci.Name))),
        (New-HtmlTableRow -Cells @("Pod GUID",                   (Invoke-HtmlEncode $ci.Guid))),
        (New-HtmlTableRow -Cells @("CPA Status",                 $statusBadge)),
        (New-HtmlTableRow -Cells @("Member Sites",               (Invoke-HtmlEncode ($ci.SiteNames -join ", ")))),
        (New-HtmlTableRow -Cells @("Site Redirection",           (Invoke-HtmlEncode "$($ci.SiteRedirectionEnabled)"))),
        (New-HtmlTableRow -Cells @("Site Redirection (no SSO)", (Invoke-HtmlEncode "$($ci.SiteRedirectionWithoutSso)")))
    )
    $null = $content.Append((New-HtmlTable -Headers @("Property","Value") -Rows $overviewRows))

    # Connection Server CPA statuses
    if ($ci.ConnectionServerStatuses.Count -gt 0) {
        $csRows = foreach ($cs in $ci.ConnectionServerStatuses) {
            $csBadge = switch ($cs.status) {
                "ENABLED"  { New-HtmlBadge -Text "ENABLED"  -Color "ok" }
                "DISABLED" { New-HtmlBadge -Text "DISABLED" -Color "neutral" }
                default    { New-HtmlBadge -Text "$($cs.status)" -Color "neutral" }
            }
            New-HtmlTableRow -Cells @(
                (Invoke-HtmlEncode $cs.name), $csBadge,
                (Invoke-HtmlEncode "$($cs.pending_percentage)%"),
                (Invoke-HtmlEncode $cs.message)
            )
        }
        $null = $content.Append("<h3 style='margin:16px 0 8px;font-size:14px;'>Connection Server CPA Status</h3>")
        $null = $content.Append((New-HtmlTable -Headers @("Connection Server","Status","Pending %","Message") -Rows $csRows))
    }

    # All sites from /federation/v2/sites
    if ($Cpa.Sites.Count -gt 0) {
        $sRows = foreach ($s in $Cpa.Sites) {
            New-HtmlTableRow -Cells @((Invoke-HtmlEncode $s.Name),(Invoke-HtmlEncode $s.Description))
        }
        $null = $content.Append("<h3 style='margin:16px 0 8px;font-size:14px;'>Sites</h3>")
        $null = $content.Append((New-HtmlTable -Headers @("Name","Description") -Rows $sRows))
    }

    # Pods from /federation/v1/pods
    if ($Cpa.Pods.Count -gt 0) {
        $pRows = foreach ($p in $Cpa.Pods) {
            $typeBadge = if ($p.Local) { New-HtmlBadge -Text "Local" -Color "ok" } else { New-HtmlBadge -Text "Remote" -Color "neutral" }
            New-HtmlTableRow -Cells @(
                (Invoke-HtmlEncode $p.Name),(Invoke-HtmlEncode $p.SiteName),
                (Invoke-HtmlEncode $p.EndpointUrl),$typeBadge
            )
        }
        $null = $content.Append("<h3 style='margin:16px 0 8px;font-size:14px;'>Pods</h3>")
        $null = $content.Append((New-HtmlTable -Headers @("Name","Site","Endpoint URL","Type") -Rows $pRows))
    }

    # Home Site Assignments from /federation/v2/home-sites
    if ($Cpa.HomeSites.Count -gt 0) {
        $hsRows = foreach ($hs in $Cpa.HomeSites) {
            New-HtmlTableRow -Cells @(
                (Invoke-HtmlEncode $hs.UserGroupName),(Invoke-HtmlEncode $hs.SiteName),
                (Invoke-HtmlEncode "$($hs.Override)")
            )
        }
        $null = $content.Append("<h3 style='margin:16px 0 8px;font-size:14px;'>Home Site Assignments</h3>")
        $null = $content.Append((New-HtmlTable -Headers @("User / Group","Home Site","Override") -Rows $hsRows))
    }
    return New-HtmlSection -Id "cpa" -Title "Cloud Pod Architecture" -Content $content.ToString()
}

