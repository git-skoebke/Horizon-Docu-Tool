# =============================================================================
# Render-ConnectionServers — New-HtmlConnectionServersSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlConnectionServersSection {
    param($Servers)
    if (-not $Servers -or $Servers.Count -eq 0) {
        return ""
    }

    $content = [System.Text.StringBuilder]::new()

    foreach ($cs in $Servers) {
        $statusBadge = switch ($cs.Status) {
            "OK"      { New-HtmlBadge -Text "OK"    -Color "ok" }
            "WARN"    { New-HtmlBadge -Text "WARN"  -Color "warn" }
            "ERROR"   { New-HtmlBadge -Text "ERROR" -Color "error" }
            default   { New-HtmlBadge -Text "$($cs.Status)" -Color "neutral" }
        }
        $certBadge = if ($null -eq $cs.CertValid)      { New-HtmlBadge -Text "N/A"     -Color "neutral" }
                     elseif ($cs.CertValid -eq $true)   { New-HtmlBadge -Text "Valid"   -Color "ok" }
                     else                               { New-HtmlBadge -Text "Invalid" -Color "error" }

        $null = $content.Append("<details class='detail-card'>")
        $null = $content.Append("<summary>")
        $null = $content.Append((Invoke-HtmlEncode $cs.Name))
        $null = $content.Append(" <span class='card-meta'>$(Invoke-HtmlEncode $cs.Version) &nbsp;$statusBadge &nbsp;$certBadge</span>")
        $null = $content.Append("</summary>")
        $null = $content.Append("<div>")

        # General
        $null = $content.Append("<h4>General</h4>")
        $genRows = @(
            (New-HtmlTableRow -Cells @("Version",       (Invoke-HtmlEncode $cs.Version))),
            (New-HtmlTableRow -Cells @("Status",        $statusBadge)),
            (New-HtmlTableRow -Cells @("Enabled",       (Invoke-HtmlEncode $cs.Enabled)))
        )
        if ($cs.ExternalURL)          { $genRows += New-HtmlTableRow -Cells @("External URL",          (Invoke-HtmlEncode $cs.ExternalURL)) }
        if ($cs.Tags)                 { $genRows += New-HtmlTableRow -Cells @("Tags",                  (Invoke-HtmlEncode $cs.Tags)) }
        if ($cs.OsVersion)            { $genRows += New-HtmlTableRow -Cells @("OS Version",            (Invoke-HtmlEncode $cs.OsVersion)) }
        if ($cs.ReplicationPartners)  { $genRows += New-HtmlTableRow -Cells @("Replication Partners",  (Invoke-HtmlEncode $cs.ReplicationPartners)) }
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $genRows))

        # Network Configuration
        $null = $content.Append("<h4>Network Configuration</h4>")
        if ($cs.NetIPAddress) {
            $netRows = @(
                (New-HtmlTableRow -Cells @("IP Address",     (Invoke-HtmlEncode $cs.NetIPAddress))),
                (New-HtmlTableRow -Cells @("Subnet Mask",    (Invoke-HtmlEncode $cs.NetSubnet))),
                (New-HtmlTableRow -Cells @("Gateway",        (Invoke-HtmlEncode $cs.NetGateway))),
                (New-HtmlTableRow -Cells @("Primary DNS",    (Invoke-HtmlEncode $cs.NetDNS1))),
                (New-HtmlTableRow -Cells @("Secondary DNS",  $(if ($cs.NetDNS2) { Invoke-HtmlEncode $cs.NetDNS2 } else { "N/A" })))
            )
            $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $netRows))
        } else {
            $null = $content.Append("<p><em style='color:#888'>N/A (remote query failed)</em></p>")
        }

        # Certificate
        $null = $content.Append("<h4>Certificate</h4>")
        $certRows = @(
            (New-HtmlTableRow -Cells @("Valid",      $certBadge)),
            (New-HtmlTableRow -Cells @("Valid From", (Invoke-HtmlEncode $cs.CertValidFrom))),
            (New-HtmlTableRow -Cells @("Valid To",   (Invoke-HtmlEncode $cs.CertValidTo)))
        )
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $certRows))

        # Memory
        $freeMemDisplay  = if ($null -ne $cs.BrokerFreeMemMB)  { "$($cs.BrokerFreeMemMB) MB"  } else { "N/A" }
        $totalMemDisplay = if ($null -ne $cs.BrokerTotalMemMB) { "$($cs.BrokerTotalMemMB) MB" } else { "N/A" }
        $null = $content.Append("<h4>Broker Memory</h4>")
        $memRows = @(
            (New-HtmlTableRow -Cells @("Free Memory",  (Invoke-HtmlEncode $freeMemDisplay))),
            (New-HtmlTableRow -Cells @("Total Memory", (Invoke-HtmlEncode $totalMemDisplay)))
        )
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $memRows))

        # C: Disk
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
        $null = $content.Append("<h4>Disk Space (C:)</h4>")
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows @(
            (New-HtmlTableRow -Cells @("C: Drive", $diskHtml))
        )))

        # Last Windows Patch
        $patchDisplay = if ($cs.LastPatchId) {
            $pStr = $cs.LastPatchId
            if ($cs.LastPatchDate) { $pStr = $pStr + " (" + $cs.LastPatchDate + ")" }
            Invoke-HtmlEncode $pStr
        } else { "N/A" }
        $null = $content.Append("<h4>Windows Patches</h4>")
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows @(
            (New-HtmlTableRow -Cells @("Last Patch", $patchDisplay))
        )))

        # Local Admins
        $null = $content.Append("<h4>Local Administrators</h4>")
        if ($cs.LocalAdmins -and $cs.LocalAdmins.Count -gt 0) {
            $adminRows = foreach ($admin in $cs.LocalAdmins) {
                New-HtmlTableRow -Cells @((Invoke-HtmlEncode $admin))
            }
            $null = $content.Append((New-HtmlTable -Headers @("Member") -Rows $adminRows))
        } else {
            $null = $content.Append("<p><em style='color:#888'>N/A</em></p>")
        }

        # locked.properties
        $null = $content.Append("<h4>locked.properties</h4>")
        if ($cs.LockedProperties) {
            $enc = Invoke-HtmlEncode ($cs.LockedProperties.Trim())
            $null = $content.Append("<pre style='margin:2px 0;font-size:0.8em;white-space:pre-wrap;background:#f7f9fc;padding:8px;border-radius:4px;'>$enc</pre>")
        } else {
            $null = $content.Append("<p><em style='color:#888'>N/A</em></p>")
        }

        $null = $content.Append("</div></details>")
    }

    return New-HtmlSection -Id "connection-servers" -Title "Connection Servers" -Content $content.ToString()
}
