# =============================================================================
# Render-UagData — New-HtmlUagDataSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

# Translate camelCase/lowercase API field names to readable labels
function Convert-UagFieldLabel {
    param([string]$Name)
    $map = @{
        # General / network
        'ip0'                    = 'IP Address'
        'netmask0'               = 'Netmask'
        'forceNetmask0'          = 'Forced Netmask'
        'ip0AllocationMode'      = 'IP Allocation Mode'
        'ipMode0'                = 'IP Mode'
        'defaultGateway'         = 'Default Gateway'
        'deploymentOption'       = 'Deployment Option'
        'DNS'                    = 'DNS Servers'
        # Edge service
        'identifier'             = 'Service Type'
        'enabled'                = 'Enabled'
        'proxyDestinationUrl'    = 'Connection Server URL'
        'proxyDestinationUrlThumbprints' = 'CS Thumbprints'
        'blastEnabled'           = 'Blast Enabled'
        'blastExternalUrl'       = 'Blast External URL'
        'blastReverseConnectionEnabled' = 'Blast Reverse Connection'
        'pcoipEnabled'           = 'PCoIP Enabled'
        'pcoipExternalUrl'       = 'PCoIP External URL'
        'tunnelEnabled'          = 'Tunnel Enabled'
        'tunnelExternalUrl'      = 'Tunnel External URL'
        'udpTunnelServerEnabled' = 'UDP Tunnel Enabled'
        'authMethods'            = 'Auth Methods'
        'canonicalizationEnabled'= 'Canonicalization'
        'clientEncryptionMode'   = 'Client Encryption Mode'
        'complianceCheckOnAuthentication' = 'Compliance Check on Auth'
        'disableWebClient'       = 'Disable Web Client'
        'enableApplianceCertBluCheck' = 'Cert BLU Check'
        'enableAuthOnRedirectSite'    = 'Auth on Redirect Site'
        'forwardAppAppsEnabled'  = 'Forward App Apps'
        'gatewayLocation'        = 'Gateway Location'
        'healthCheckUrl'         = 'Health Check URL'
        'securityHeaders'        = 'Security Headers'
        'smartCardHintPrompt'    = 'Smart Card Hint Prompt'
        # Admin users
        'name'                   = 'Username'
        'role'                   = 'Role'
        'adminUsersList'         = 'Admin Users'
        # SSL certs
        'commonName'             = 'Common Name'
        'issuer'                 = 'Issuer'
        'expirationDate'         = 'Expiry Date'
        'expiryDate'             = 'Expiry Date'
        'serialNumber'           = 'Serial Number'
        'thumbprint'             = 'Thumbprint'
        'subjectAltNames'        = 'Subject Alt Names'
        'validFrom'              = 'Valid From'
        'validTo'                = 'Valid To'
        'keyAlgorithm'           = 'Key Algorithm'
        'signatureAlgorithm'     = 'Signature Algorithm'
        # Auth methods
        'authMethod'             = 'Auth Method'
    }
    if ($map.ContainsKey($Name)) { return $map[$Name] }
    # Fallback: insert space before capitals, title-case
    $spaced = [System.Text.RegularExpressions.Regex]::Replace($Name, '([A-Z])', ' $1').Trim()
    return (Get-Culture).TextInfo.ToTitleCase($spaced.ToLower())
}

# Render a consistent 2-column property/value table with fixed column widths
function New-UagPropertyTable {
    param([object[]]$Rows)
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.Append('<table style="width:100%;table-layout:fixed;">')
    $null = $sb.Append('<colgroup><col style="width:35%"><col style="width:65%"></colgroup>')
    $null = $sb.Append('<thead><tr><th>Setting</th><th>Value</th></tr></thead><tbody>')
    foreach ($row in $Rows) { $null = $sb.Append($row) }
    $null = $sb.Append('</tbody></table>')
    return $sb.ToString()
}

# Sub-heading style used consistently throughout
function New-UagSubHeading {
    param([string]$Text)
    return "<h3 style='font-size:13px;font-weight:600;margin:14px 0 5px;color:#2c5282;" +
           "padding-bottom:3px;border-bottom:1px solid #d1d9e6;'>$(Invoke-HtmlEncode $Text)</h3>"
}

function New-HtmlUagDataSection {
    param($UagData)

    if (-not $UagData -or $UagData.Count -eq 0) { return "" }

    $sb = [System.Text.StringBuilder]::new()

    foreach ($uag in $UagData) {
        $gwTitle = Invoke-HtmlEncode "$($uag.GatewayName) ($($uag.GatewayIP))"

        if ($uag.LoginFailed) {
            $null = $sb.Append("<details class='detail-card' open><summary>$gwTitle</summary>")
            $null = $sb.Append("<p style='padding:10px;color:#c53030;'>")
            $null = $sb.Append("UAG API login failed for $(Invoke-HtmlEncode $uag.GatewayIP) — check credentials and port 9443 reachability.")
            $null = $sb.Append("</p></details>")
            continue
        }

        $null = $sb.Append("<details class='detail-card'><summary>$gwTitle</summary>")
        $null = $sb.Append("<div style='padding:12px 0;'>")

        # ── General ──────────────────────────────────────────────────────────
        if ($uag.General) {
            $rows = foreach ($prop in ($uag.General.PSObject.Properties | Sort-Object Name)) {
                $val = $prop.Value
                if ($null -eq $val -or ($val -is [System.Collections.IEnumerable] -and $val -isnot [string])) { continue }
                $label = Convert-UagFieldLabel $prop.Name
                New-HtmlTableRow -Cells @(
                    (Invoke-HtmlEncode $label),
                    (Invoke-HtmlEncode ($val -as [string]))
                )
            }
            if ($rows) {
                $null = $sb.Append((New-UagSubHeading "General"))
                $null = $sb.Append((New-UagPropertyTable -Rows $rows))
            }
        }

        # ── Edge Services ─────────────────────────────────────────────────────
        # Skip fields that are internal/uninteresting or complex objects
        $edgeSkip = @('proxyDestinationUrlThumbprints','smartCardHintPrompt','securityHeaders',
                      'healthCheckUrl','radiusServerList','samlServiceProviderMetadata',
                      'devicePolicyServiceEndpointList','claimsTransformationList')

        if ($uag.EdgeServices -and $uag.EdgeServices.Count -gt 0) {
            $null = $sb.Append((New-UagSubHeading "Edge Services"))
            foreach ($svc in $uag.EdgeServices) {
                $svcLabel = if ($svc.identifier) { $svc.identifier }
                            elseif ($svc.edgeServiceType) { $svc.edgeServiceType }
                            else { "Service" }

                $rows = foreach ($prop in ($svc.PSObject.Properties | Sort-Object Name)) {
                    if ($edgeSkip -contains $prop.Name) { continue }
                    $val = $prop.Value
                    if ($null -eq $val) { continue }
                    $display = if ($val -is [string]) {
                        $val
                    } elseif ($val -is [bool]) {
                        if ($val) { "True" } else { "False" }
                    } elseif ($val -is [System.Collections.IEnumerable]) {
                        try { @($val | ForEach-Object { $_ -as [string] } | Where-Object { $_ }) -join ', ' } catch { continue }
                    } else {
                        $val -as [string]
                    }
                    if ([string]::IsNullOrEmpty($display)) { continue }
                    $label = Convert-UagFieldLabel $prop.Name
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $label),
                        (Invoke-HtmlEncode $display)
                    )
                }
                if ($rows) {
                    $null = $sb.Append("<p style='font-weight:600;margin:10px 0 4px;font-size:12px;color:#1a202c;'>")
                    $null = $sb.Append((Invoke-HtmlEncode $svcLabel))
                    $null = $sb.Append("</p>")
                    $null = $sb.Append((New-UagPropertyTable -Rows $rows))
                    $null = $sb.Append("<div style='margin-bottom:8px;'></div>")
                }
            }
        }

        # ── Admin Users ───────────────────────────────────────────────────────
        if ($uag.AdminUsers -and $uag.AdminUsers.Count -gt 0) {
            $null = $sb.Append((New-UagSubHeading "Admin Users"))
            $rows = foreach ($u in $uag.AdminUsers) {
                $uname = if ($u.name) { $u.name } elseif ($u.username) { $u.username } else { "?" }
                $role  = if ($u.role) { $u.role } else { "" }
                New-HtmlTableRow -Cells @(
                    (Invoke-HtmlEncode $uname),
                    (Invoke-HtmlEncode $role)
                )
            }
            $tbl = New-HtmlTable -Headers @("Username","Role") -Rows $rows
            $null = $sb.Append($tbl)
        }

        # ── SSL Certificates ──────────────────────────────────────────────────
        if ($uag.SslCerts -and $uag.SslCerts.Count -gt 0) {
            $null = $sb.Append((New-UagSubHeading "SSL Certificates"))
            foreach ($cert in $uag.SslCerts) {
                $entityLabel = (Get-Culture).TextInfo.ToTitleCase($cert.Entity)
                $d = $cert.Data
                $rows = foreach ($prop in ($d.PSObject.Properties | Sort-Object Name)) {
                    $val = $prop.Value
                    if ($null -eq $val -or ($val -is [System.Collections.IEnumerable] -and $val -isnot [string])) { continue }
                    $label = Convert-UagFieldLabel $prop.Name
                    New-HtmlTableRow -Cells @(
                        (Invoke-HtmlEncode $label),
                        (Invoke-HtmlEncode ($val -as [string]))
                    )
                }
                if ($rows) {
                    $null = $sb.Append("<p style='font-weight:600;margin:10px 0 4px;font-size:12px;color:#1a202c;'>")
                    $null = $sb.Append((Invoke-HtmlEncode $entityLabel))
                    $null = $sb.Append("</p>")
                    $null = $sb.Append((New-UagPropertyTable -Rows $rows))
                    $null = $sb.Append("<div style='margin-bottom:8px;'></div>")
                }
            }
        }

        # ── Auth Methods ──────────────────────────────────────────────────────
        if ($uag.AuthMethods -and $uag.AuthMethods.Count -gt 0) {
            $null = $sb.Append((New-UagSubHeading "Authentication Methods"))
            $rows = foreach ($m in $uag.AuthMethods) {
                $mname   = if ($m.name) { $m.name } elseif ($m.authMethod) { $m.authMethod } else { "?" }
                $enabled = $m.enabled
                $badge   = if ($null -ne $enabled) {
                    if ($enabled) { New-HtmlBadge -Text "Enabled" -Color "ok" }
                    else          { New-HtmlBadge -Text "Disabled" -Color "neutral" }
                } else { "" }
                New-HtmlTableRow -Cells @(
                    (Invoke-HtmlEncode $mname),
                    $badge
                )
            }
            $tbl = New-HtmlTable -Headers @("Auth Method","Status") -Rows $rows
            $null = $sb.Append($tbl)
        }

        $null = $sb.Append("</div></details>")
    }

    return New-HtmlSection -Id "uag-api" -Title "UAG — Detailed Configuration" -Content ($sb.ToString())
}
