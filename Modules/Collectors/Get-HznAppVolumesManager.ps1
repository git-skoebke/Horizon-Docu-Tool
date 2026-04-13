# =============================================================================
# Get-HznAppVolumesManager — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznAppVolumesManager {
    if (-not $restToken) { return @() }
    try {
        $raw = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v2/app-volumes-manager","config/v1/app-volumes-manager")
        if (-not $raw) { return @() }
        return @($raw) | ForEach-Object {
            [PSCustomObject]@{
                ServerName           = $_.server_name
                Port                 = $_.port
                UserName             = $_.username
                CertificateOverride  = $_.certificate_override
            }
        }
    } catch {
        Write-RunspaceLog "WARNING: App Volumes Manager collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

