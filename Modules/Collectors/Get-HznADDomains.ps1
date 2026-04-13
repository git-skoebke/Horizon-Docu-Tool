# =============================================================================
# Get-HznADDomains — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznADDomains {
    param($hzSvc)
    try {
        # Use ADDomainHealth_List (NOT ADDomain_List) — returns NetBiosName + ConnectionServerState
        $raw = $hzSvc.ADDomainHealth.ADDomainHealth_List()
        return $raw | ForEach-Object {
            $state = $null
            if ($_.ConnectionServerState -and $_.ConnectionServerState.Count -gt 0) {
                $state = $_.ConnectionServerState[0]
            }
            [PSCustomObject]@{
                DNSName           = $_.DNSName
                NetBIOSName       = $_.NetBiosName
                Status            = if ($state) { $state.Status } else { "UNKNOWN" }
                TrustRelationship = if ($state) { $state.TrustRelationship } else { "" }
                Contactable       = if ($state) { $state.Contactable } else { $false }
            }
        }
    } catch {
        Write-RunspaceLog "WARNING: AD Domain collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

