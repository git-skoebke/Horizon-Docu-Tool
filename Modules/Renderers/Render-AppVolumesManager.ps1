# =============================================================================
# Render-AppVolumesManager — New-HtmlAppVolumesManagerSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlAppVolumesManagerSection {
    param($AVM)
    if (-not $AVM -or $AVM.Count -eq 0) {
        return ""
    }

    $content = [System.Text.StringBuilder]::new()

    foreach ($a in $AVM) {
        # Service status badge
        $svcBadge = switch ($a.ServiceStatus) {
            "Running"   { New-HtmlBadge -Text "Running"  -Color "ok" }
            "Stopped"   { New-HtmlBadge -Text "Stopped"  -Color "error" }
            "Not Found" { New-HtmlBadge -Text "Not Found" -Color "neutral" }
            default     { New-HtmlBadge -Text "$($a.ServiceStatus)" -Color "warn" }
        }
        # Certificate badge
        $certBadge = if ($null -eq $a.CertValid)      { New-HtmlBadge -Text "N/A"     -Color "neutral" }
                     elseif ($a.CertValid -eq $true)   { New-HtmlBadge -Text "Valid"   -Color "ok" }
                     else                               { New-HtmlBadge -Text "Invalid" -Color "error" }

        $null = $content.Append("<details class='detail-card'>")
        $null = $content.Append("<summary>")
        $null = $content.Append((Invoke-HtmlEncode $a.ServerName))
        $versionDisplay = if ($a.AppVolumesVersion) { $a.AppVolumesVersion } else { "N/A" }
        $null = $content.Append(" <span class='card-meta'>$(Invoke-HtmlEncode $versionDisplay) &nbsp;$svcBadge &nbsp;$certBadge</span>")
        $null = $content.Append("</summary>")
        $null = $content.Append("<div>")

        # General
        $null = $content.Append("<h4>General</h4>")
        $genRows = @(
            (New-HtmlTableRow -Cells @("App Volumes Version", (Invoke-HtmlEncode $versionDisplay))),
            (New-HtmlTableRow -Cells @("Service (CVManager)", $svcBadge))
        )
        if ($a.OsVersion) { $genRows += New-HtmlTableRow -Cells @("OS Version", (Invoke-HtmlEncode $a.OsVersion)) }
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $genRows))

        # Network Configuration
        $null = $content.Append("<h4>Network Configuration</h4>")
        if ($a.NetIPAddress) {
            $netRows = @(
                (New-HtmlTableRow -Cells @("IP Address",     (Invoke-HtmlEncode $a.NetIPAddress))),
                (New-HtmlTableRow -Cells @("Subnet Mask",    (Invoke-HtmlEncode $a.NetSubnet))),
                (New-HtmlTableRow -Cells @("Gateway",        (Invoke-HtmlEncode $a.NetGateway))),
                (New-HtmlTableRow -Cells @("Primary DNS",    (Invoke-HtmlEncode $a.NetDNS1))),
                (New-HtmlTableRow -Cells @("Secondary DNS",  $(if ($a.NetDNS2) { Invoke-HtmlEncode $a.NetDNS2 } else { "N/A" })))
            )
            $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $netRows))
        } else {
            $null = $content.Append("<p><em style='color:#888'>N/A (remote query failed)</em></p>")
        }

        # Certificate (from nginx.conf)
        $null = $content.Append("<h4>Certificate</h4>")
        $certRows = @(
            (New-HtmlTableRow -Cells @("Valid", $certBadge))
        )
        if ($a.NginxCertFile) {
            $certRows += New-HtmlTableRow -Cells @("Certificate File", (Invoke-HtmlEncode $a.NginxCertFile))
        }
        if ($a.NginxKeyFile) {
            $certRows += New-HtmlTableRow -Cells @("Key File", (Invoke-HtmlEncode $a.NginxKeyFile))
        }
        $certRows += New-HtmlTableRow -Cells @("Valid From", (Invoke-HtmlEncode $a.CertValidFrom))
        $certRows += New-HtmlTableRow -Cells @("Valid To",   (Invoke-HtmlEncode $a.CertValidTo))
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $certRows))

        # Guest Memory
        $freeMemDisplay  = if ($null -ne $a.GuestFreeMemMB)  { "$($a.GuestFreeMemMB) MB"  } else { "N/A" }
        $totalMemDisplay = if ($null -ne $a.GuestTotalMemMB) { "$($a.GuestTotalMemMB) MB" } else { "N/A" }
        $null = $content.Append("<h4>Guest Memory</h4>")
        $memRows = @(
            (New-HtmlTableRow -Cells @("Free Memory",  (Invoke-HtmlEncode $freeMemDisplay))),
            (New-HtmlTableRow -Cells @("Total Memory", (Invoke-HtmlEncode $totalMemDisplay)))
        )
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $memRows))

        # C: Disk
        $diskHtml = if ($null -ne $a.DiskFreeGB) {
            $pct = if ($a.DiskTotalGB -gt 0) { [math]::Round(100 * $a.DiskFreeGB / $a.DiskTotalGB) } else { 0 }
            if ($pct -lt 15) {
                "<span style='color:red'>" + $a.DiskFreeGB + " GB free</span> / " + $a.DiskTotalGB + " GB"
            } elseif ($pct -lt 25) {
                "<span style='color:orange'>" + $a.DiskFreeGB + " GB free</span> / " + $a.DiskTotalGB + " GB"
            } else {
                [string]$a.DiskFreeGB + " GB free / " + [string]$a.DiskTotalGB + " GB"
            }
        } else { "N/A" }
        $null = $content.Append("<h4>Disk Space (C:)</h4>")
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows @(
            (New-HtmlTableRow -Cells @("C: Drive", $diskHtml))
        )))

        # Last Windows Patch
        $patchDisplay = if ($a.LastPatchId) {
            $pStr = $a.LastPatchId
            if ($a.LastPatchDate) { $pStr = $pStr + " (" + $a.LastPatchDate + ")" }
            Invoke-HtmlEncode $pStr
        } else { "N/A" }
        $null = $content.Append("<h4>Windows Patches</h4>")
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows @(
            (New-HtmlTableRow -Cells @("Last Patch", $patchDisplay))
        )))

        # Local Admins
        $null = $content.Append("<h4>Local Administrators</h4>")
        if ($a.LocalAdmins -and $a.LocalAdmins.Count -gt 0) {
            $adminRows = foreach ($admin in $a.LocalAdmins) {
                New-HtmlTableRow -Cells @((Invoke-HtmlEncode $admin))
            }
            $null = $content.Append((New-HtmlTable -Headers @("Member") -Rows $adminRows))
        } else {
            $null = $content.Append("<p><em style='color:#888'>N/A</em></p>")
        }

        # ODBC DSN
        $null = $content.Append("<h4>ODBC System DSN</h4>")
        if ($a.OdbcDsnEntries -and $a.OdbcDsnEntries.Count -gt 0) {
            $dsnRows = foreach ($dsn in $a.OdbcDsnEntries) {
                $serverDb = @()
                if ($dsn.Server)   { $serverDb += $dsn.Server }
                if ($dsn.Database) { $serverDb += $dsn.Database }
                $detail = if ($serverDb.Count -gt 0) { $serverDb -join " / " } else { "" }
                New-HtmlTableRow -Cells @(
                    (Invoke-HtmlEncode $dsn.Name),
                    (Invoke-HtmlEncode $dsn.Platform),
                    (Invoke-HtmlEncode $dsn.Driver),
                    (Invoke-HtmlEncode $detail)
                )
            }
            $null = $content.Append((New-HtmlTable -Headers @("Name","Platform","Driver","Server / Database") -Rows $dsnRows))
        } else {
            $null = $content.Append("<p><em style='color:#888'>N/A</em></p>")
        }

        $null = $content.Append("</div></details>")
    }

    return New-HtmlSection -Id "app-volumes" -Title "App Volumes Manager" -Content $content.ToString()
}
