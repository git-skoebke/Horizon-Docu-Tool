# =============================================================================
# Render-ADDomains — New-HtmlADDomainsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlADDomainsSection {
    param($ADDomains)
    if (-not $ADDomains -or $ADDomains.Count -eq 0) {
        return ""
    }
    $rows = foreach ($d in $ADDomains) {
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $d.DNSName),
            (Invoke-HtmlEncode $d.NetBIOSName),
            (Invoke-HtmlEncode $d.Status),
            (Invoke-HtmlEncode $d.TrustRelationship),
            (Invoke-HtmlEncode $d.Contactable)
        )
    }
    $table = New-HtmlTable -Headers @("DNS Name","NetBIOS Name","Status","Trust Relationship","Contactable") -Rows $rows
    return New-HtmlSection -Id "ad-domains" -Title "AD Domains" -Content $table
}

