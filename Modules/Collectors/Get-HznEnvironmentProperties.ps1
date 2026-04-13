# =============================================================================
# Get-HznEnvironmentProperties — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznEnvironmentProperties {
    if (-not $restToken) { return $null }
    try {
        $ep = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v2/environment-properties","config/v1/environment-properties")
        if (-not $ep) { return $null }
        return [PSCustomObject]@{
            ClusterName                    = $ep.cluster_name
            ClusterGuid                    = $ep.cluster_guid
            DeploymentType                 = $ep.deployment_type
            LocalConnectionServerVersion   = $ep.local_connection_server_version
            LocalConnectionServerBuild     = $ep.local_connection_server_build
            IpMode                         = $ep.ip_mode
            TimezoneOffset                 = $ep.timezone_offset
            FipsModeEnabled                = $ep.fips_mode_enabled
        }
    } catch {
        Write-RunspaceLog "WARNING: Environment Properties collection failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}

