# =============================================================================
# Get-HznGatewayCertificates — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznGatewayCertificates {
    if (-not $restToken) { return @() }
    try {
        $raw = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v1/gateways/certificates")
        if (-not $raw) { return @() }
        return @($raw) | ForEach-Object {
            [PSCustomObject]@{
                CertificateName = $_.certificate_name
                CommonName      = $_.common_name
                ExpiryDate      = $_.expiry_date
                Issuer          = $_.issuer
                SerialNum       = $_.serial_num
            }
        }
    } catch {
        Write-RunspaceLog "WARNING: Gateway Certificates collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

