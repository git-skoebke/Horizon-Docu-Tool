# =============================================================================
# Get-HznGlobalPolicies — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznGlobalPolicies {
    param($hzSvc)
    try {
        # SPECIAL CASE: PoliciesService is NOT a property of $hzServices
        # Use [Omnissa.Horizon.PoliciesService]::new() — VMware.Hv.PoliciesService does NOT exist
        # Verified live against Horizon 8.17.0: returns PoliciesInfo with .GlobalPolicies
        $polSvc = [Omnissa.Horizon.PoliciesService]::new()
        $gp     = $polSvc.Policies_Get($hzSvc, $null, $null)
        if ($null -eq $gp) { return $null }
        $gpData = $gp.GlobalPolicies
        return [PSCustomObject]@{
            AllowMultimediaRedirection        = $gpData.AllowMultimediaRedirection
            AllowUSBAccess                    = $gpData.AllowUSBAccess
            AllowRemoteMode                   = $gpData.AllowRemoteMode
            AllowPCoIPHardwareAcceleration    = $gpData.AllowPCoIPHardwareAcceleration
            PcoipHardwareAccelerationPriority = $gpData.PcoipHardwareAccelerationPriority
        }
    } catch {
        Write-RunspaceLog "WARNING: Global Policies collection failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}

