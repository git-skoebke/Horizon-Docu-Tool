# =============================================================================
# Render-ConnectionServers — New-HtmlConnectionServersSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlConnectionServersSection {
    param($Servers)
    if (-not $Servers -or $Servers.Count -eq 0) {
        return ""
    }
    $rows = foreach ($cs in $Servers) {
        $statusBadge = switch ($cs.Status) {
            "OK"      { New-HtmlBadge -Text "OK"    -Color "ok" }
            "WARN"    { New-HtmlBadge -Text "WARN"  -Color "warn" }
            "ERROR"   { New-HtmlBadge -Text "ERROR" -Color "error" }
            default   { New-HtmlBadge -Text "$($cs.Status)" -Color "neutral" }
        }
        $certBadge = if ($null -eq $cs.CertValid)  { New-HtmlBadge -Text "N/A"     -Color "neutral" }
                     elseif ($cs.CertValid -eq $true)  { New-HtmlBadge -Text "Valid"   -Color "ok" }
                     else                              { New-HtmlBadge -Text "Invalid" -Color "error" }
        $freeMemDisplay  = if ($null -ne $cs.BrokerFreeMemMB)  { "$($cs.BrokerFreeMemMB) MB"  } else { "N/A" }
        $totalMemDisplay = if ($null -ne $cs.BrokerTotalMemMB) { "$($cs.BrokerTotalMemMB) MB" } else { "N/A" }

        # Local Admins — collapsible list with DOMAIN\name format
        $adminsHtml = if ($cs.LocalAdmins -and $cs.LocalAdmins.Count -gt 0) {
            $lines = ($cs.LocalAdmins | ForEach-Object { Invoke-HtmlEncode $_ }) -join "<br>"
            "<details class='inline-detail'><summary>" + $cs.LocalAdmins.Count + " members</summary>" + $lines + "</details>"
        } else { "N/A" }

        # locked.properties — collapsible pre block
        $lockedHtml = if ($cs.LockedProperties) {
            $enc = Invoke-HtmlEncode ($cs.LockedProperties.Trim())
            "<details class='inline-detail'><summary>View</summary><pre style='margin:2px 0;font-size:0.8em;white-space:pre-wrap'>" + $enc + "</pre></details>"
        } else { "N/A" }

        # C: disk space with color coding (red <15% free, orange <25%)
        $diskHtml = if ($null -ne $cs.DiskFreeGB) {
            $pct = if ($cs.DiskTotalGB -gt 0) { [math]::Round(100 * $cs.DiskFreeGB / $cs.DiskTotalGB) } else { 0 }
            if ($pct -lt 15) {
                "<span style='color:red'>" + $cs.DiskFreeGB + " GB free</span> / " + $cs.DiskTotalGB + " GB"
            } elseif ($pct -lt 25) {
                "<span style='color:orange'>" + $cs.DiskFreeGB + " GB free</span> / " + $cs.DiskTotalGB + " GB"
            } else {
                [string]$cs.DiskFreeGB + " GB free / " + [string]$cs.DiskTotalGB + " GB"
            }
        } else { "N/A" }

        # Last Windows patch
        $patchHtml = if ($cs.LastPatchId) {
            $pStr = $cs.LastPatchId
            if ($cs.LastPatchDate) { $pStr = $pStr + " (" + $cs.LastPatchDate + ")" }
            Invoke-HtmlEncode $pStr
        } else { "N/A" }

        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $cs.Name),
            (Invoke-HtmlEncode $cs.Version),
            $statusBadge,
            (Invoke-HtmlEncode $cs.ReplicationPartners),
            (Invoke-HtmlEncode $cs.ExternalURL),
            $certBadge,
            (Invoke-HtmlEncode $cs.CertValidFrom),
            (Invoke-HtmlEncode $cs.CertValidTo),
            (Invoke-HtmlEncode $freeMemDisplay),
            (Invoke-HtmlEncode $totalMemDisplay),
            (Invoke-HtmlEncode $cs.OsVersion),
            $adminsHtml,
            $lockedHtml,
            $diskHtml,
            $patchHtml
        )
    }
    $table = New-HtmlTable -Headers @("Name","Version","Status","Replication Partners","External URL","Cert Valid","Cert From","Cert To","Free Memory","Total Memory","OS Version","Local Admins","locked.properties","C: Disk","Last Patch") -Rows $rows
    return New-HtmlSection -Id "connection-servers" -Title "Connection Servers" -Content $table
}

