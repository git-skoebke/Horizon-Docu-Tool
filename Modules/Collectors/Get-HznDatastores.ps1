# =============================================================================
# Get-HznDatastores — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznDatastores {
    param($vcHealthList)
    try {
        if (-not $vcHealthList -or $vcHealthList.Count -eq 0) { return @() }
        $allDS = @()
        foreach ($vch in $vcHealthList) {
            $dsItems = $vch.datastoredata
            if (-not $dsItems) { continue }
            $allDS += $dsItems | Where-Object { $_.Name } | ForEach-Object {
                $capGB  = [math]::round($_.CapacityMB / 1KB)
                $freeGB = [math]::round($_.FreeSpaceMB / 1KB)
                $usedPct = if ($_.CapacityMB -gt 0) {
                    [math]::round((($_.CapacityMB - $_.FreeSpaceMB) / $_.CapacityMB) * 100, 1)
                } else { 0 }
                [PSCustomObject]@{
                    Name       = $_.Name
                    Type       = $_.DataStoreType
                    CapacityGB = $capGB
                    FreeGB     = $freeGB
                    UsedPct    = $usedPct
                    Accessible = $_.Accessible
                    Path       = $_.Path
                }
            }
        }
        return $allDS
    } catch {
        Write-RunspaceLog "WARNING: Datastore collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

