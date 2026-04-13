# =============================================================================
# Get-HznESXiHosts — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznESXiHosts {
    param($vcHealthList)
    try {
        if (-not $vcHealthList -or $vcHealthList.Count -eq 0) { return @() }

        # Fetch Version and vgpu_types from REST monitor/v4/virtual-centers
        $monitorMap = @{}
        try {
            $monRaw = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
                "monitor/v4/virtual-centers","monitor/v3/virtual-centers","monitor/v2/virtual-centers"
            )
            if ($monRaw) {
                foreach ($vc in @($monRaw)) {
                    $hostsNode = if ($vc.hosts_v3) { $vc.hosts_v3 } elseif ($vc.hosts_v2) { $vc.hosts_v2 } else { $null }
                    if (-not $hostsNode) { continue }
                    foreach ($mh in @($hostsNode)) {
                        $hName = if ($mh.details -and $mh.details.name) { $mh.details.name } else { $null }
                        if (-not $hName) { continue }
                        $monitorMap[$hName] = [PSCustomObject]@{
                            Version   = if ($mh.details.version) { "$($mh.details.version)" } else { "" }
                            VGPUTypes = if ($mh.details.vgpu_types) { @($mh.details.vgpu_types) } else { @() }
                        }
                    }
                }
            }
        } catch {
            Write-RunspaceLog "WARNING: ESXi monitor REST fetch failed: $($_.Exception.Message)" "WARN"
        }

        # PowerCLI build lookup + vGPU driver version via esxcli VIB list
        $esxiBuildMap    = @{}
        $esxiVgpuVibMap  = @{}
        if ($viConnected) {
            try {
                $vmHosts = Get-VMHost -ErrorAction SilentlyContinue
                foreach ($vmh in $vmHosts) {
                    $esxiBuildMap[$vmh.Name] = "$($vmh.Build)"

                    # Query VIB list for NVD-VMware (NVIDIA vGPU host driver)
                    try {
                        $esxcli = Get-EsxCli -VMHost $vmh -V2 -ErrorAction SilentlyContinue
                        if ($esxcli) {
                            $nvdVib = $esxcli.software.vib.list.Invoke() |
                                Where-Object { $_.Name -like "NVD-VMware*" } |
                                Select-Object -First 1
                            if ($nvdVib) {
                                # Version format: "580.82.02-10EM.800.1.0.20613240"
                                # Extract the driver part before the first "-"
                                $vibVer = ($nvdVib.Version -split '-')[0]
                                $esxiVgpuVibMap[$vmh.Name] = $vibVer
                            }
                        }
                    } catch {
                        Write-RunspaceLog "WARNING: VIB query failed for $($vmh.Name): $($_.Exception.Message)" "WARN"
                    }
                }
            } catch {
                Write-RunspaceLog "WARNING: Get-VMHost build lookup failed: $($_.Exception.Message)" "WARN"
            }
        }

        $allHosts = @()
        foreach ($vch in $vcHealthList) {
            $hostItems = $vch.hostdata
            if (-not $hostItems) { continue }
            $allHosts += $hostItems | ForEach-Object {
                $mon = $monitorMap[$_.Name]
                $hBuild = if ($esxiBuildMap.ContainsKey($_.Name)) { $esxiBuildMap[$_.Name] } else { "" }
                [PSCustomObject]@{
                    Name          = $_.Name
                    Version       = if ($mon -and $mon.Version) { $mon.Version } else { "$($_.Version)" }
                    Build         = $hBuild
                    APIVersion    = $_.APIVersion
                    ClusterName   = $_.ClusterName
                    NumCpuCores   = $_.NumCpuCores
                    CpuMhz        = $_.CpuMhz
                    MemoryGB      = [math]::round($_.MemorySizeBytes / 1GB)
                    NumMachines   = $_.NumMachines
                    VGPUTypes     = if ($mon -and $mon.VGPUTypes.Count -gt 0) { $mon.VGPUTypes } elseif ($_.VGPUTypes) { @($_.VGPUTypes) } else { @() }
                    VgpuVibVer    = if ($esxiVgpuVibMap.ContainsKey($_.Name)) { $esxiVgpuVibMap[$_.Name] } else { "" }
                }
            }
        }
        # INFRA-06a: pCPU:vCPU ratio note — NumCpuCores = physical cores per host.
        # NumMachines = VM count on host (not vCPU count). Actual per-VM vCPU requires
        # PowerCLI against vCenter — outside Horizon API scope. Collector stores NumCpuCores
        # and NumMachines; renderer notes this limitation for the ratio column.
        return $allHosts
    } catch {
        Write-RunspaceLog "WARNING: ESXi host collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

