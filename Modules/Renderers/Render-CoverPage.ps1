# =============================================================================
# Render-CoverPage — PDF cover page with company/contact information
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlCoverPage {
    <#
    .SYNOPSIS
        Generates an HTML cover page block for the PDF report.
        Returns empty string if no company info fields are filled.
    .PARAMETER CompanyInfo
        Hashtable with optional keys: CompanyName, ContactPerson, ContactRole,
        Street, ZipCity, Country, Phone, Email
    .PARAMETER ReportMeta
        Hashtable with keys: ServerName, HorizonVersion, GeneratedAt
    #>
    param(
        [hashtable]$CompanyInfo,
        [hashtable]$ReportMeta
    )

    # Check if any company info field has a value
    if (-not $CompanyInfo) { return "" }
    $hasData = $false
    foreach ($key in @("CompanyName","ContactPerson","ContactRole","Street","ZipCity","Country","Phone","Email")) {
        if ($CompanyInfo[$key] -and $CompanyInfo[$key].Trim()) { $hasData = $true; break }
    }
    if (-not $hasData) { return "" }

    # Helper: only render a line if the value is non-empty
    $line = {
        param([string]$Value, [string]$CssClass = "cover-detail")
        if ($Value -and $Value.Trim()) {
            return "<div class=`"$CssClass`">$(Invoke-HtmlEncode $Value)</div>"
        }
        return ""
    }

    # Build contact block — only filled fields
    $contactLines = @()

    $companyName = & $line $CompanyInfo.CompanyName "cover-company"
    if ($companyName) { $contactLines += $companyName }

    # Contact person + role on one logical block
    $personLine = & $line $CompanyInfo.ContactPerson "cover-person"
    if ($personLine) { $contactLines += $personLine }
    $roleLine = & $line $CompanyInfo.ContactRole "cover-role"
    if ($roleLine) { $contactLines += $roleLine }

    # Address block
    $streetLine = & $line $CompanyInfo.Street "cover-detail"
    if ($streetLine) { $contactLines += $streetLine }
    $zipLine = & $line $CompanyInfo.ZipCity "cover-detail"
    if ($zipLine) { $contactLines += $zipLine }
    $countryLine = & $line $CompanyInfo.Country "cover-detail"
    if ($countryLine) { $contactLines += $countryLine }

    # Contact info
    $phoneLine = & $line $CompanyInfo.Phone "cover-detail"
    if ($phoneLine) { $contactLines += $phoneLine }
    $emailLine = & $line $CompanyInfo.Email "cover-detail"
    if ($emailLine) { $contactLines += $emailLine }

    $contactHtml = $contactLines -join "`n        "

    # Report metadata
    $server       = if ($ReportMeta.ServerName) { Invoke-HtmlEncode $ReportMeta.ServerName } else { "" }
    $version      = if ($ReportMeta.HorizonVersion) { Invoke-HtmlEncode $ReportMeta.HorizonVersion } else { "" }
    $genDate      = if ($ReportMeta.GeneratedAt) { $ReportMeta.GeneratedAt.ToString("yyyy-MM-dd") } else { (Get-Date).ToString("yyyy-MM-dd") }
    $avStandalone = [bool]$ReportMeta.AvStandalone

    if ($avStandalone) {
        $coverTitle    = "Omnissa App Volumes"
        $coverSubtitle = "Environment Documentation"
        $metaServer    = "Manager: $server"
        $metaVersion   = "" # App Volumes version is shown in the body section
    } else {
        $coverTitle    = "Omnissa Horizon"
        $coverSubtitle = "Environment Documentation"
        $metaServer    = "Connection Server: $server"
        $metaVersion   = "<div class=`"cover-meta`">Horizon Version: $version</div>"
    }

    return @"
<div class="cover-page">
    <div class="cover-top">
        <div class="cover-title">$coverTitle</div>
        <div class="cover-subtitle">$coverSubtitle</div>
    </div>
    <div class="cover-middle">
        $contactHtml
    </div>
    <div class="cover-bottom">
        <div class="cover-meta">$metaServer</div>
        $metaVersion
        <div class="cover-meta">Generated: $genDate</div>
    </div>
</div>
"@
}
