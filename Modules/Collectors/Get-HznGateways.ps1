# =============================================================================
# Get-HznGateways — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznGateways {
    if (-not $restToken) { return @() }
    try {
        $raw = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v1/gateways")
        if (-not $raw) { return @() }
        return @($raw) | ForEach-Object {
            [PSCustomObject]@{
                Name     = $_.name
                Address  = $_.address
                Version  = $_.version
                Internal = $_.internal
            }
        }
    } catch {
        Write-RunspaceLog "WARNING: Gateway collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

