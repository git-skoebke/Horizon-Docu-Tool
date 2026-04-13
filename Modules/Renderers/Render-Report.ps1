# =============================================================================
# Render-Report — New-HorizonHtmlReport
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HorizonHtmlReport {
    param(
        [hashtable]$Data,
        [hashtable]$CompanyInfo = @{}
    )

    $meta         = $Data.ReportMeta
    $genDate      = $meta.GeneratedAt.ToString("yyyy-MM-dd HH:mm:ss")
    $server       = Invoke-HtmlEncode $meta.ServerName
    $version      = Invoke-HtmlEncode $meta.HorizonVersion
    $avStandalone = [bool]$meta.AvStandalone

    # Title + header vary between a full Horizon documentation run and an AV-only run.
    if ($avStandalone) {
        $docTitleShort = "App Volumes Report"
        $docHeadline   = "Omnissa App Volumes &mdash; Environment Documentation"
        $metaLine      = "Generated: $genDate &nbsp;|&nbsp; Manager: $server"
    } else {
        $docTitleShort = "Horizon Report"
        $docHeadline   = "Omnissa Horizon &mdash; Environment Documentation"
        $metaLine      = "Generated: $genDate &nbsp;|&nbsp; Server: $server &nbsp;|&nbsp; Horizon: $version"
    }

    $css = @"
/* === Reset & Base === */
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Segoe UI', Arial, sans-serif; font-size: 14px;
       background: #f5f7fa; color: #1a202c; }

/* === Layout === */
.report-layout { display: flex; align-items: flex-start; min-height: 100vh; }
.toc-sidebar { width: 220px; flex-shrink: 0; position: sticky; top: 0;
       height: 100vh; overflow-y: auto; padding: 20px 16px;
       background: #fff; border-right: 1px solid #d1d9e6; }
.toc-sidebar h3 { font-size: 11px; text-transform: uppercase; letter-spacing: 0.08em;
          color: #718096; margin-bottom: 12px; }
.toc-sidebar ul { list-style: none; }
.toc-sidebar li { margin-bottom: 6px; }
.toc-sidebar a { text-decoration: none; color: #0070D2; font-size: 13px; }
.toc-sidebar a:hover { text-decoration: underline; }
.report-content { flex: 1; padding: 24px 32px; min-width: 0; }

/* === Report Header === */
.report-header { background: #1a3c5e; color: #fff; padding: 24px 32px;
         margin-bottom: 24px; border-radius: 4px; }
.report-header h1 { font-size: 22px; font-weight: 600; }
.report-header .meta { font-size: 13px; opacity: 0.85; margin-top: 8px; }

/* === Sections === */
section { margin-bottom: 32px; background: #fff; border-radius: 4px;
  border: 1px solid #d1d9e6; padding: 20px 24px;
  scroll-margin-top: 16px; }
section h2 { font-size: 16px; font-weight: 600; color: #1a3c5e;
     margin-bottom: 16px; padding-bottom: 8px;
     border-bottom: 2px solid #0070D2; }

/* === Tables === */
table { width: 100%; border-collapse: collapse; font-size: 13px; }
th { background: #2c5282; color: #fff; text-align: left;
     padding: 8px 12px; font-weight: 600; }
td { padding: 7px 12px; border-bottom: 1px solid #e2e8f0; vertical-align: top; overflow-wrap: anywhere; }
tr:nth-child(even) td { background: #f0f4f8; }
tr:hover td { background: #e6f0fa; }

/* === Status Badges === */
.badge { display: inline-block; padding: 2px 8px; border-radius: 3px;
 font-size: 11px; font-weight: 600; }
.badge-ok      { background: #c6f6d5; color: #276749; }
.badge-warn    { background: #fefcbf; color: #b7791f; }
.badge-error   { background: #fed7d7; color: #c53030; }
.badge-neutral { background: #e2e8f0; color: #4a5568; }

/* === Cover Page === */
.cover-page {
    display: flex; flex-direction: column; justify-content: space-between;
    text-align: center; padding: 60px 50px;
    height: 100vh; box-sizing: border-box;
    page-break-after: always; break-after: page;
}
.cover-top { margin-top: 40px; }
.cover-title { font-size: 36px; font-weight: 700; color: #1a3c5e; letter-spacing: 0.02em; }
.cover-subtitle { font-size: 20px; font-weight: 400; color: #4a5568; margin-top: 8px; }
.cover-middle { padding: 20px 0; }
.cover-company { font-size: 22px; font-weight: 600; color: #1a3c5e; margin-bottom: 12px; }
.cover-person { font-size: 16px; color: #2d3748; margin-top: 16px; }
.cover-role { font-size: 14px; color: #718096; margin-bottom: 12px; }
.cover-detail { font-size: 14px; color: #4a5568; line-height: 1.7; }
.cover-bottom { margin-bottom: 40px; border-top: 2px solid #0070D2; padding-top: 16px; }
.cover-meta { font-size: 12px; color: #718096; line-height: 1.8; }

/* === Unified collapsible details/summary — triangle marker === */
details > summary {
    cursor: pointer;
    list-style: none;
}
details > summary::-webkit-details-marker { display: none; }
details > summary::before {
    content: "\25B6";   /* ▶ */
    display: inline-block;
    font-size: 0.7em;
    margin-right: 6px;
    transition: transform 0.2s;
    color: #1a202c;
    vertical-align: middle;
}
details[open] > summary::before {
    transform: rotate(90deg);
}

/* === Unified Detail Cards === */
details.detail-card {
    margin-bottom: 8px; border: 1px solid #d1d9e6;
    border-radius: 6px; overflow: hidden;
}
details.detail-card > summary {
    padding: 12px 16px; font-weight: 600; cursor: pointer;
    background: #f7f9fc;
    display: flex; align-items: center; gap: 8px;
}
details.detail-card[open] > summary {
    border-bottom: 1px solid #d1d9e6;
}
details.detail-card .card-meta {
    font-weight: 400; font-size: 0.88em; color: #718096;
    display: inline-flex; align-items: center; gap: 6px;
}
details.detail-card > div { padding: 16px 20px; }

/* === Section Sub-Headers (inside cards and sections) === */
section h4 {
    margin: 16px 0 8px; font-size: 13px;
    color: #2c5282; font-weight: 600;
}
section > h4:first-of-type,
details.detail-card > div > h4:first-child {
    margin-top: 0;
}

/* === Inline collapsible (table cells: member lists, disks, etc.) === */
details.inline-detail > summary {
    display: inline-flex; align-items: center; gap: 4px;
}
details.inline-detail > summary::before {
    font-size: 0.65em;
}

/* === Print === */
@media print {
    /* Hide sidebar navigation */
    .toc-sidebar { display: none !important; }

    /* Reset layout for print */
    .report-layout { display: block; }
    .report-content { padding: 0; width: 100%; }

    /* Sections: allow natural page flow, avoid breaking mid-section when possible */
    section { page-break-inside: auto;
              border: 1px solid #999; margin-bottom: 12px; }
    section h2 { page-break-after: avoid; }

    /* Tables: avoid splitting rows, repeat header on each page */
    tr { page-break-inside: avoid; }
    thead { display: table-header-group; }

    /* Remove hover effects */
    tr:hover td { background: inherit !important; }

    /* Ensure all text is dark on white */
    body { background: #fff !important; color: #000 !important; font-size: 11px; }
    section { background: #fff !important; }
    section h2 { color: #1a3c5e !important; font-size: 14px; }
    th { background: #2c5282 !important; color: #fff !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }
    tr:nth-child(even) td { background: #f5f5f5 !important; -webkit-print-color-adjust: exact; print-color-adjust: exact; }

    /* Badges: force color printing */
    .badge { -webkit-print-color-adjust: exact; print-color-adjust: exact; }

    /* Report header */
    .report-header { background: #1a3c5e !important; color: #fff !important;
                     -webkit-print-color-adjust: exact; print-color-adjust: exact;
                     break-after: avoid; page-break-after: avoid; }

    /* Links: show URL in print */
    a { color: #0070D2 !important; text-decoration: none; }

    /* All collapsible details: force open in PDF/print */
    details { display: block !important; }
    details > summary { display: block !important; }
    details > summary::before { display: none !important; }
    details > * { display: block !important; }
}
"@

    $htmlHead = @"
<!DOCTYPE html>
<html lang="de">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$docTitleShort — $server</title>
  <style>
$css
  </style>
</head>
<body>
"@

    $tocHtml = ""   # built dynamically below

    $layoutOpen = @"
<div class="report-layout">
  <nav class="toc-sidebar">
    <h3>Contents</h3>
    <ul>
__TOC_PLACEHOLDER__
    </ul>
  </nav>
  <main class="report-content">
    <div class="report-header">
      <h1>$docHeadline</h1>
      <div class="meta">$metaLine</div>
    </div>
"@

    $sb = [System.Text.StringBuilder]::new(524288)
    $null = $sb.Append($htmlHead)

    # Cover page (only rendered if company info is present — hidden on screen, visible in print/PDF)
    $coverHtml = New-HtmlCoverPage -CompanyInfo $CompanyInfo -ReportMeta $meta
    if ($coverHtml) { $null = $sb.Append($coverHtml) }

    # -------------------------------------------------------------------------
    # Render all sections — skip empty ones (renderers return "" when no data)
    # -------------------------------------------------------------------------
    $allSections = [ordered]@{
        "connection-servers"         = (New-HtmlConnectionServersSection     $Data.ConnectionServers)
        "vcenter-servers"            = (New-HtmlVCenterSection               $Data.VCenterServers)
        "datastores"                 = (New-HtmlDatastoresSection            $Data.Datastores $Data.VcVmInventory)
        "esxi-hosts"                 = (New-HtmlESXiHostsSection             $Data.ESXiHosts  $Data.VcVmInventory)
        "ad-domains"                 = (New-HtmlADDomainsSection             $Data.ADDomains)
        "gateways"                   = (New-HtmlGatewaysSection              $Data.Gateways)
        "gateway-certificates"       = (New-HtmlGatewayCertificatesSection   $Data.GatewayCertificates)
        "uag-api"                    = (New-HtmlUagDataSection               $Data.UagData)
        "license"                    = (New-HtmlLicenseSection               $Data.License)
        "general-settings"           = (New-HtmlGeneralSettingsSection       $Data.GeneralSettings)
        "global-policies"            = (New-HtmlGlobalPoliciesSection        $Data.GlobalPolicies)
        "event-database"             = (New-HtmlEventDatabaseSection         $Data.EventDatabase)
        "saml-authenticators"        = (New-HtmlSamlAuthenticatorsSection    $Data.SamlAuthenticators)
        "true-sso"                   = (New-HtmlTrueSSOSection               $Data.TrueSSO)
        "permissions"                = (New-HtmlPermissionsSection           $Data.Permissions)
        "ic-domain-accounts"         = (New-HtmlIcDomainAccountsSection      $Data.IcDomainAccounts)
        "environment"                = (New-HtmlEnvironmentPropertiesSection $Data.EnvironmentProperties)
        "app-volumes"                = (New-HtmlAppVolumesManagerSection     $Data.AppVolumesManager)
        "app-volumes-data"           = (New-HtmlAppVolumesDataSection         $Data.AppVolumesData)
        "syslog"                     = (New-HtmlSyslogSection                $Data.Syslog)
        "cpa"                        = (New-HtmlCpaSection                   $Data.Cpa)
        "global-entitlements"        = (New-HtmlGlobalEntitlementsSection    $Data.GlobalEntitlements)
        "local-desktop-entitlements" = (New-HtmlLocalDesktopEntitlementsSection    $Data.LocalDesktopEntitlements)
        "local-application-entitlements" = (New-HtmlLocalApplicationEntitlementsSection $Data.LocalApplicationEntitlements)
        "desktop-pools"              = (New-HtmlDesktopPoolsSection          $Data.DesktopPools $Data.GlobalEntitlements)
        "application-pools"          = (New-HtmlApplicationPoolsSection      $Data.ApplicationPools)
        "golden-images"              = (New-HtmlGoldenImagesSection          $Data.GoldenImages)
        "rds-farms"                  = (New-HtmlRdsFarmsSection              $Data.RdsFarms)
        "internal-template-vms"      = (New-HtmlInternalTemplateVMsSection   $Data.InternalTemplateVMs)
    }

    # TOC label map
    $tocLabels = @{
        "connection-servers"         = "Connection Servers"
        "vcenter-servers"            = "vCenter Servers"
        "datastores"                 = "Datastores"
        "esxi-hosts"                 = "ESXi Hosts"
        "ad-domains"                 = "AD Domains"
        "gateways"                   = "Gateways / UAG"
        "gateway-certificates"       = "Gateway Certificates"
        "uag-api"                    = "UAG Detailed Config"
        "license"                    = "License"
        "general-settings"           = "General Settings"
        "global-policies"            = "Global Policies"
        "event-database"             = "Event Database"
        "saml-authenticators"        = "SAML Authenticators"
        "true-sso"                   = "TrueSSO"
        "permissions"                = "Administrators"
        "ic-domain-accounts"         = "IC Domain Accounts"
        "environment"                = "Environment Properties"
        "app-volumes"                = "App Volumes Manager"
        "app-volumes-data"           = "App Volumes Config"
        "syslog"                     = "Syslog"
        "cpa"                        = "Cloud Pod Architecture"
        "global-entitlements"        = "Global Entitlements"
        "local-desktop-entitlements" = "Local Desktop Entitlements"
        "local-application-entitlements" = "Local Application Entitlements"
        "desktop-pools"              = "Desktop Pools"
        "application-pools"          = "Application Pools"
        "golden-images"              = "Golden Images"
        "rds-farms"                  = "RDS Farms"
        "internal-template-vms"      = "Internal Template VMs"
    }

    # Build TOC and body — only for non-empty sections
    $tocItems   = [System.Text.StringBuilder]::new()
    $bodySections = [System.Text.StringBuilder]::new()
    foreach ($id in $allSections.Keys) {
        $html = $allSections[$id]
        if ([string]::IsNullOrWhiteSpace($html)) { continue }
        $label = $tocLabels[$id]
        $null = $tocItems.Append("      <li><a href='#$id'>$label</a></li>`n")
        $null = $bodySections.Append($html)
    }

    $layout = $layoutOpen -replace '__TOC_PLACEHOLDER__', $tocItems.ToString()
    $null = $sb.Append($layout)
    $null = $sb.Append($bodySections.ToString())

    $null = $sb.Append("  </main>`n</div>`n</body>`n</html>`n")
    return $sb.ToString()
}

# Real collection steps — each Collector scriptblock returns data for $collectedData
