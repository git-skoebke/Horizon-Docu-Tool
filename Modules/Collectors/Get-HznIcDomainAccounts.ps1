# =============================================================================
# Get-HznIcDomainAccounts — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznIcDomainAccounts {
    if (-not $restToken) { return @() }
    try {
        $raw = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v2/ic-domain-accounts","config/v1/ic-domain-accounts")
        if (-not $raw) { return @() }
        return @($raw) | ForEach-Object {
            [PSCustomObject]@{
                UserName    = $_.username
                DnsName     = $_.dns_name
                AdDomainId  = $_.ad_domain_id
            }
        }
    } catch {
        Write-RunspaceLog "WARNING: IC Domain Accounts collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

