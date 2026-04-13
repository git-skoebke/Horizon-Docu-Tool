# =============================================================================
# Get-HznTrueSSO — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznTrueSSO {
    if (-not $restToken) { return $null }
    try {
        $connectors       = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v1/true-sso")
        $enrollmentSrvs   = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v1/true-sso-enrollment-servers")
        return [PSCustomObject]@{
            Connectors      = if ($connectors)     { @($connectors)     } else { @() }
            EnrollmentSrvs  = if ($enrollmentSrvs) { @($enrollmentSrvs) } else { @() }
        }
    } catch {
        Write-RunspaceLog "WARNING: TrueSSO collection failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}

