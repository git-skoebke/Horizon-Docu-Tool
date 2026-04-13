# =============================================================================
# Render-ESXiHosts — New-HtmlESXiHostsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlESXiHostsSection {
    param($ESXiHosts, $VcVmInventory = $null)
    if (-not $ESXiHosts -or $ESXiHosts.Count -eq 0) {
        return ""
    }

    # NVIDIA vGPU Software version lookup table
    # Key   = Linux vGPU Manager version prefix (from VIB, before first "-")
    # Value = vGPU Software release (e.g. "19.1")
    # Source: https://docs.nvidia.com/vgpu/index.html — Driver Versions tab
    $vgpuVersionMap = @{
        # vGPU 20.x — R595
        "595.58.02" = "20.0"
        # vGPU 19.x — R580
        "580.126.08" = "19.4"
        "580.105.06" = "19.3"
        "580.95.02"  = "19.2"
        "580.82.02"  = "19.1"
        "580.65.05"  = "19.0"
        # vGPU 18.x — R570
        "570.211.01" = "18.6"
        "570.195.02" = "18.5"
        "570.172.07" = "18.4"
        "570.158.02" = "18.3"
        "570.148.06" = "18.2"
        "570.133.10" = "18.1"
        "570.124.03" = "18.0"
        # vGPU 17.x — R550
        "550.163.02" = "17.6"
        "550.144.02" = "17.5"
        "550.127.06" = "17.4"
        "550.90.05"  = "17.3"
        "550.54.16"  = "17.1"
        "550.54.10"  = "17.0"
        # vGPU 16.x — R535
        "535.288.01" = "16.13"
        "535.274.03" = "16.12"
        "535.261.04" = "16.11"
        "535.247.02" = "16.10"
        "535.230.02" = "16.9"
        "535.216.01" = "16.8"
        "535.183.04" = "16.7"
        "535.161.05" = "16.5"
        "535.154.02" = "16.3"
        "535.129.03" = "16.2"
        "535.104.06" = "16.1"
        "535.54.06"  = "16.0"
        # vGPU 15.x — R525
        "525.147.01" = "15.4"
        "525.125.03" = "15.3"
        "525.105.14" = "15.2"
        "525.85.07"  = "15.1"
        "525.60.12"  = "15.0"
        # vGPU 14.x — R510
        "510.108.03" = "14.4"
        "510.85.03"  = "14.2"
        "510.73.06"  = "14.1"
        "510.47.03"  = "14.0"
        # vGPU 13.x — R470
        "470.256.02" = "13.12"
        "470.239.01" = "13.10"
        "470.223.02" = "13.9"
        "470.199.03" = "13.8"
        "470.182.02" = "13.7"
        "470.161.02" = "13.6"
        "470.141.05" = "13.4"
        "470.129.04" = "13.3"
        "470.103.02" = "13.2"
        "470.82"     = "13.1"
        "470.63"     = "13.0"
        # vGPU 12.x — R460
        "460.107"    = "12.4"
        "460.91.03"  = "12.3"
        "460.73.02"  = "12.2"
        "460.32.04"  = "12.1"
        # vGPU 11.x — R450
        "450.248.03" = "11.13"
        "450.236.03" = "11.12"
        "450.216.04" = "11.11"
        "450.203"    = "11.9"
        "450.191"    = "11.8"
        "450.172"    = "11.7"
        "450.156"    = "11.6"
        "450.142"    = "11.5"
        "450.124"    = "11.4"
        "450.102"    = "11.3"
        "450.89"     = "11.2"
        "450.80"     = "11.1"
        "450.55"     = "11.0"
        # vGPU 10.x — R440
        "440.121"    = "10.4"
        "440.107"    = "10.3"
        "440.87"     = "10.2"
        "440.53"     = "10.1"
        "440.43"     = "10.0"
    }

    $rows = foreach ($h in ($ESXiHosts | Sort-Object Name)) {
        $poweredOnCount = "N/A"
        $vcpuRatioHtml  = "N/A"
        if ($VcVmInventory) {
            $ref = $VcVmInventory.HostNameToRef["$($h.Name)"]
            if ($ref -and $VcVmInventory.HostVmCount.ContainsKey($ref)) {
                $poweredOnCount = "$($VcVmInventory.HostVmCount[$ref])"
            } elseif ($ref) {
                $poweredOnCount = "0"
            }
            if ($ref -and $h.NumCpuCores -gt 0) {
                $totalVcpu = if ($VcVmInventory.HostVcpuCount.ContainsKey($ref)) { [int]$VcVmInventory.HostVcpuCount[$ref] } else { 0 }
                $pCpu      = [int]$h.NumCpuCores
                $ratioVal  = [math]::Round($totalVcpu / $pCpu, 1)
                $color     = if ($ratioVal -gt 4) { "#c53030" } else { "#276749" }
                $vcpuRatioHtml = "<span style='color:$color;font-weight:600'>" + $ratioVal + ":1</span>"
            }
        }
        $vgpuHtml = if ($h.VGPUTypes -and $h.VGPUTypes.Count -gt 0) {
            $lines = ($h.VGPUTypes | ForEach-Object { Invoke-HtmlEncode $_ }) -join "<br>"
            "<details class='inline-detail'><summary>" + $h.VGPUTypes.Count + " types</summary>" + $lines + "</details>"
        } else { "None" }

        # vGPU driver version + mapped vGPU Software release
        $vgpuDriverHtml = if ($h.VgpuVibVer) {
            $release = $vgpuVersionMap[$h.VgpuVibVer]
            if ($release) {
                "<span style='font-weight:600'>$release</span>" +
                "<br><span style='color:#718096;font-size:11px'>" + (Invoke-HtmlEncode $h.VgpuVibVer) + "</span>"
            } else {
                # VIB found but version not in lookup table — show raw version with note
                "<span style='color:#718096;font-size:11px'>" + (Invoke-HtmlEncode $h.VgpuVibVer) + "</span>"
            }
        } else {
            if ($h.VGPUTypes -and $h.VGPUTypes.Count -gt 0) {
                # Has vGPU types but no VIB found (no vCenter connection or VIB query failed)
                "<span style='color:#a0aec0;font-style:italic;font-size:11px'>N/A</span>"
            } else {
                "—"
            }
        }

        $buildDisplay = if ($h.Build) { $h.Build } else { "N/A" }
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $h.Name),
            (Invoke-HtmlEncode $h.ClusterName),
            (Invoke-HtmlEncode $h.Version),
            (Invoke-HtmlEncode $buildDisplay),
            (Invoke-HtmlEncode "$($h.NumCpuCores)"),
            (Invoke-HtmlEncode "$($h.MemoryGB)"),
            (Invoke-HtmlEncode $poweredOnCount),
            $vcpuRatioHtml,
            $vgpuHtml,
            $vgpuDriverHtml
        )
    }
    $table = New-HtmlTable -Headers @("Name","Cluster","Version","Build","CPUs (physical)","RAM GB","Powered-On VMs","vCPU:pCPU","vGPU Types","vGPU Driver") -Rows $rows
    $clusters = $ESXiHosts | Select-Object -ExpandProperty ClusterName -Unique
    $clusterSummary = ""
    foreach ($clusterName in $clusters) {
        $clusterHosts  = $ESXiHosts | Where-Object { $_.ClusterName -eq $clusterName }
        $totalPCpu     = ($clusterHosts | Measure-Object -Property NumCpuCores -Sum).Sum
        $clusterVcpu   = 0
        $clusterRatioHtml = ""
        if ($VcVmInventory -and $totalPCpu -gt 0) {
            foreach ($ch in $clusterHosts) {
                $cRef = $VcVmInventory.HostNameToRef["$($ch.Name)"]
                if ($cRef -and $VcVmInventory.HostVcpuCount.ContainsKey($cRef)) {
                    $clusterVcpu += [int]$VcVmInventory.HostVcpuCount[$cRef]
                }
            }
            $cRatioVal = [math]::Round($clusterVcpu / $totalPCpu, 1)
            $cColor    = if ($cRatioVal -gt 4) { "#c53030" } else { "#276749" }
            $clusterRatioHtml = " &nbsp;|&nbsp; vCPU:pCPU <span style='color:$cColor;font-weight:600'>" + $cRatioVal + ":1</span>"
        }
        $clusterLabel = "<p><strong>Cluster: " + (Invoke-HtmlEncode $clusterName) + "</strong> - Total pCPU cores: $totalPCpu$clusterRatioHtml</p>"
        $clusterSummary += $clusterLabel
    }
    $content = $table + $clusterSummary
    return New-HtmlSection -Id "esxi-hosts" -Title "ESXi Hosts" -Content $content
}

