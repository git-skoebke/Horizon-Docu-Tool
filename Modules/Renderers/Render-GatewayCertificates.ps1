# =============================================================================
# Render-GatewayCertificates — New-HtmlGatewayCertificatesSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlGatewayCertificatesSection {
    param($Certs)
    if (-not $Certs -or $Certs.Count -eq 0) {
        return ""
    }
    $rows = foreach ($c in $Certs) {
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $c.CertificateName),
            (Invoke-HtmlEncode $c.CommonName),
            (Invoke-HtmlEncode $c.ExpiryDate),
            (Invoke-HtmlEncode $c.Issuer),
            (Invoke-HtmlEncode $c.SerialNum)
        )
    }
    $table = New-HtmlTable -Headers @("Certificate Name","Common Name","Expiry Date","Issuer","Serial Number") -Rows $rows
    return New-HtmlSection -Id "gateway-certificates" -Title "Gateway Certificates" -Content $table
}

