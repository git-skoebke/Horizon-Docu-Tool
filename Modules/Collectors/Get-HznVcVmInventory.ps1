# =============================================================================
# Get-HznVcVmInventory — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznVcVmInventory {
    if (-not $viConnected) { return $null }
    try {
        Write-RunspaceLog "Collecting vCenter VM inventory (powered-on counts)..." "INFO"
        $vms = Get-View -ViewType VirtualMachine -Property Runtime.Host,Datastore,Runtime.PowerState,Config.Hardware.NumCPU -ErrorAction Stop
        $poweredOn = @($vms) | Where-Object { $_.Runtime.PowerState -eq "poweredOn" }

        $hostVmCount   = @{}
        $hostVcpuCount = @{}
        $dsVmCount     = @{}
        foreach ($vm in $poweredOn) {
            $hRef = "$($vm.Runtime.Host)"
            if ($hRef) {
                $hostVmCount[$hRef]   = ($hostVmCount[$hRef] + 1)
                $hostVcpuCount[$hRef] = ($hostVcpuCount[$hRef] + [int]$vm.Config.Hardware.NumCPU)
            }
            foreach ($dRef in @($vm.Datastore)) {
                $dStr = "$dRef"
                if ($dStr) { $dsVmCount[$dStr] = ($dsVmCount[$dStr] + 1) }
            }
        }

        # Host name → MoRef map
        $hostViews = Get-View -ViewType HostSystem -Property Name -ErrorAction Stop
        $hostNameToRef = @{}
        foreach ($h in $hostViews) { $hostNameToRef["$($h.Name)"] = "$($h.MoRef)" }

        # Datastore name → MoRef map
        $dsViews = Get-View -ViewType Datastore -Property Name -ErrorAction Stop
        $dsNameToRef = @{}
        foreach ($d in $dsViews) { $dsNameToRef["$($d.Name)"] = "$($d.MoRef)" }

        return [PSCustomObject]@{
            HostVmCount    = $hostVmCount
            HostVcpuCount  = $hostVcpuCount
            DsVmCount      = $dsVmCount
            HostNameToRef  = $hostNameToRef
            DsNameToRef    = $dsNameToRef
        }
    } catch {
        Write-RunspaceLog "WARNING: vCenter VM inventory failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}

