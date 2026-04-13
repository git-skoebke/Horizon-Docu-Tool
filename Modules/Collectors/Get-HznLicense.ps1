# =============================================================================
# Get-HznLicense — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznLicense {
    if (-not $restToken) { return $null }
    try {
        $lic = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
            "config/v4/licenses","config/v3/licenses","config/v2/licenses","config/v1/licenses"
        )
        if (-not $lic) { return $null }

        # Helper: convert epoch-ms or ISO timestamp to readable format
        $toReadable = {
            param($val)
            if (-not $val) { return "" }
            try {
                if ($val -match '^\d+$') {
                    # Epoch milliseconds
                    return ([DateTimeOffset]::FromUnixTimeMilliseconds([long]$val)).LocalDateTime.ToString("yyyy-MM-dd HH:mm")
                }
                return ([datetime]$val).ToString("yyyy-MM-dd HH:mm")
            } catch { return "$val" }
        }

        return [PSCustomObject]@{
            ExpirationTime         = & $toReadable $lic.expiration_time
            LicenseEdition         = $lic.license_edition
            LicenseHealth          = $lic.license_health
            LicenseKey             = $lic.license_key
            LicenseMode            = $lic.license_mode
            LicenseSyncTime        = & $toReadable $lic.license_sync_time
            SubscriptionSliceExpiry = & $toReadable $lic.subscription_slice_expiry
            UsageModel             = $lic.usage_model
        }
    } catch {
        Write-RunspaceLog "WARNING: License collection failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}

