# =============================================================================
# Render-TrueSSO — New-HtmlTrueSSOSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlTrueSSOSection {
    param($TrueSSO)
    if ($null -eq $TrueSSO -or ($TrueSSO.Connectors.Count -eq 0 -and $TrueSSO.EnrollmentSrvs.Count -eq 0)) {
        return ""
    }
    $content = [System.Text.StringBuilder]::new()
    if ($TrueSSO.Connectors.Count -gt 0) {
        $cRows = foreach ($c in $TrueSSO.Connectors) {
            New-HtmlTableRow -Cells @(
                (Invoke-HtmlEncode $c.name),
                (Invoke-HtmlEncode "$($c.enabled)"),
                (Invoke-HtmlEncode $c.ad_domain_id),
                (Invoke-HtmlEncode $c.template_name)
            )
        }
        $null = $content.Append("<h3 style='margin:12px 0 8px;font-size:14px;'>Connectors</h3>")
        $null = $content.Append((New-HtmlTable -Headers @("Name","Enabled","AD Domain ID","Template") -Rows $cRows))
    }
    if ($TrueSSO.EnrollmentSrvs.Count -gt 0) {
        # API: enrollment server → domains[] → certificate_servers[]
        # Flatten: one row per (server × domain × cert_server)
        $eRows = foreach ($e in $TrueSSO.EnrollmentSrvs) {
            $srvBadge = switch ("$($e.status)") {
                "ONLINE"  { New-HtmlBadge -Text "ONLINE"  -Color "ok" }
                "OFFLINE" { New-HtmlBadge -Text "OFFLINE" -Color "error" }
                default   { New-HtmlBadge -Text "$($e.status)" -Color "neutral" }
            }
            $domains = if ($e.domains) { @($e.domains) } else { @() }
            if ($domains.Count -eq 0) {
                New-HtmlTableRow -Cells @(
                    (Invoke-HtmlEncode $e.name), (Invoke-HtmlEncode $e.network_address),
                    $srvBadge, "", "", "", "", "", "", "", (Invoke-HtmlEncode $e.version)
                )
            } else {
                foreach ($d in $domains) {
                    $domBadge = switch ("$($d.domain_status)") {
                        "READY"   { New-HtmlBadge -Text "READY"   -Color "ok" }
                        "ERROR"   { New-HtmlBadge -Text "ERROR"   -Color "error" }
                        "WARNING" { New-HtmlBadge -Text "WARNING" -Color "warn" }
                        default   { New-HtmlBadge -Text "$($d.domain_status)" -Color "neutral" }
                    }
                    $certSrvs = if ($d.certificate_servers) { @($d.certificate_servers) } else { @() }
                    if ($certSrvs.Count -eq 0) {
                        New-HtmlTableRow -Cells @(
                            (Invoke-HtmlEncode $e.name), (Invoke-HtmlEncode $e.network_address),
                            $srvBadge, (Invoke-HtmlEncode $d.dns_name),
                            "", "", "", "", $domBadge,
                            (Invoke-HtmlEncode $d.domain_status_reason), (Invoke-HtmlEncode $e.version)
                        )
                    } else {
                        foreach ($cs in $certSrvs) {
                            # Only show fully healthy rows
                            if ($cs.certificate_status -ne "VALID" -or
                                $cs.connection_status  -ne "CONNECTED" -or
                                $d.domain_status       -ne "READY") { continue }
                            $connBadge = switch ("$($cs.connection_status)") {
                                "CONNECTED"    { New-HtmlBadge -Text "CONNECTED"    -Color "ok" }
                                "DISCONNECTED" { New-HtmlBadge -Text "DISCONNECTED" -Color "error" }
                                default        { New-HtmlBadge -Text "$($cs.connection_status)" -Color "neutral" }
                            }
                            $certBadge = switch ("$($cs.certificate_status)") {
                                "VALID"   { New-HtmlBadge -Text "VALID"   -Color "ok" }
                                "INVALID" { New-HtmlBadge -Text "INVALID" -Color "error" }
                                "EXPIRED" { New-HtmlBadge -Text "EXPIRED" -Color "error" }
                                default   { New-HtmlBadge -Text "$($cs.certificate_status)" -Color "neutral" }
                            }
                            New-HtmlTableRow -Cells @(
                                (Invoke-HtmlEncode $e.name),
                                (Invoke-HtmlEncode $e.network_address),
                                $srvBadge,
                                (Invoke-HtmlEncode $d.dns_name),
                                (Invoke-HtmlEncode $cs.certificate_server_name),
                                (Invoke-HtmlEncode $cs.certificate_server_network_address),
                                $certBadge,
                                $connBadge,
                                $domBadge,
                                (Invoke-HtmlEncode $d.domain_status_reason),
                                (Invoke-HtmlEncode $e.version)
                            )
                        }
                    }
                }
            }
        }
        $null = $content.Append("<h3 style='margin:12px 0 8px;font-size:14px;'>Enrollment Servers</h3>")
        $null = $content.Append((New-HtmlTable -Headers @("Name","Network Address","Status","Domain","Cert Server","Cert Server Address","Cert Status","Connection","Domain Status","Domain Reason","Version") -Rows $eRows))
    }
    return New-HtmlSection -Id "true-sso" -Title "TrueSSO" -Content $content.ToString()
}

