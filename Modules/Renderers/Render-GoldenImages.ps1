# =============================================================================
# Render-GoldenImages — New-HtmlGoldenImagesSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlGoldenImagesSection {
    param($Images)
    if (-not $Images -or @($Images).Count -eq 0) {
        return ""
    }

    $htmlBr = "<" + "br>"

    $rows = foreach ($img in ($Images | Sort-Object VmName)) {

        # ------------------------------------------------------------------ #
        # VM name with badge if not found in vCenter
        $nameHtml = if (-not $img.Found) {
            (Invoke-HtmlEncode $img.VmName) + " " + (New-HtmlBadge -Text "not found in vCenter" -Color "warn")
        } else { Invoke-HtmlEncode $img.VmName }

        # CPU topology: e.g. "4 vCPU - 2S x 2C"
        $cpuSockStr = "$($img.Sockets)S x $($img.CoresPerSocket)C"
        $cpuHtml    = if ($img.vCPU -ne "") { "$($img.vCPU) vCPU - $cpuSockStr" } else { "N/A" }

        # RAM
        $ramHtml = if ($img.RamGB -ne "") { "$($img.RamGB) GB" } else { "N/A" }

        # Disks: collapsible if more than one
        $disksHtml = if ($img.Disks -and $img.Disks.Count -gt 0) {
            $diskLines = ($img.Disks | ForEach-Object {
                (Invoke-HtmlEncode $_.Label) + ": " + $_.SizeGB + " GB - " + $_.Type
            }) -join $htmlBr
            if ($img.Disks.Count -gt 1) {
                $totalGB  = [int]($img.Disks | Measure-Object -Property SizeGB -Sum).Sum
                $diskSumm = "$($img.Disks.Count) disks, $totalGB GB total"
                "<details class='inline-detail'><summary>" + $diskSumm + "</summary>" + $diskLines + "</details>"
            } else { $diskLines }
        } else { "N/A" }

        # Network adapters
        $nicsHtml = if ($img.NetworkAdapters -and $img.NetworkAdapters.Count -gt 0) {
            ($img.NetworkAdapters | ForEach-Object {
                (Invoke-HtmlEncode $_.Type) + ": " + (Invoke-HtmlEncode $_.Network)
            }) -join $htmlBr
        } else { "N/A" }

        # vGPU
        $vgpuHtml = if (-not [string]::IsNullOrEmpty($img.VgpuProfile)) {
            New-HtmlBadge -Text (Invoke-HtmlEncode $img.VgpuProfile) -Color "ok"
        } else { "None" }

        # Snapshot count: warn badge if any snapshots exist
        $snapCount = $img.SnapshotCount
        $snapHtml  = if ($snapCount -gt 0) {
            New-HtmlBadge -Text "$snapCount" -Color "warn"
        } else { "0" }

        # ------------------------------------------------------------------ #
        # Main row
        $mainRow = New-HtmlTableRow -Cells @(
            $nameHtml,
            (Invoke-HtmlEncode $img.UsedByPools),
            $cpuHtml,
            $ramHtml,
            $disksHtml,
            $nicsHtml,
            $vgpuHtml,
            $snapHtml
        )

        # ------------------------------------------------------------------ #
        # Detail row — only rendered if guest scan was attempted OR IPs known
        $showDetail = $img.GuestScanned -or ($img.IpAddresses -and $img.IpAddresses.Count -gt 0) -or
                      (-not [string]::IsNullOrEmpty($img.GuestHostName))

        $detailRow = ""
        if ($showDetail) {

            # IP Addresses
            $ipHtml = if ($img.IpAddresses -and $img.IpAddresses.Count -gt 0) {
                ($img.IpAddresses | ForEach-Object { Invoke-HtmlEncode $_ }) -join ", "
            } else { "<span style='color:#585B70'>—</span>" }

            # Hostname (DNS name from VMware Tools)
            $hostnameHtml = if (-not [string]::IsNullOrEmpty($img.GuestHostName)) {
                "<code style='font-size:0.9em'>" + (Invoke-HtmlEncode $img.GuestHostName) + "</code>"
            } else { "<span style='color:#585B70'>—</span>" }

            # Software versions table
            $swRows = @()

            $horizonHtml = if (-not [string]::IsNullOrEmpty($img.HorizonAgentVer)) {
                Invoke-HtmlEncode $img.HorizonAgentVer
            } else { "<span style='color:#585B70'>not detected</span>" }
            $swRows += "<tr><td style='padding:2px 10px 2px 0;color:#A6ADC8;white-space:nowrap'>Horizon Agent</td><td style='padding:2px 0'>$horizonHtml</td></tr>"

            $avHtml = if (-not [string]::IsNullOrEmpty($img.AppVolumesVer)) {
                Invoke-HtmlEncode $img.AppVolumesVer
            } else { "<span style='color:#585B70'>not detected</span>" }
            $swRows += "<tr><td style='padding:2px 10px 2px 0;color:#A6ADC8;white-space:nowrap'>App Volumes Agent</td><td style='padding:2px 0'>$avHtml</td></tr>"

            $demHtml = if (-not [string]::IsNullOrEmpty($img.DemVer)) {
                Invoke-HtmlEncode $img.DemVer
            } else { "<span style='color:#585B70'>not detected</span>" }
            $swRows += "<tr><td style='padding:2px 10px 2px 0;color:#A6ADC8;white-space:nowrap'>DEM</td><td style='padding:2px 0'>$demHtml</td></tr>"

            $fsHtml = if (-not [string]::IsNullOrEmpty($img.FsLogixVer)) {
                Invoke-HtmlEncode $img.FsLogixVer
            } else { "<span style='color:#585B70'>not detected</span>" }
            $swRows += "<tr><td style='padding:2px 10px 2px 0;color:#A6ADC8;white-space:nowrap'>FSLogix</td><td style='padding:2px 0'>$fsHtml</td></tr>"

            $toolsHtml = if (-not [string]::IsNullOrEmpty($img.VmwareToolsVer)) {
                Invoke-HtmlEncode $img.VmwareToolsVer
            } else { "<span style='color:#585B70'>not detected</span>" }
            $swRows += "<tr><td style='padding:2px 10px 2px 0;color:#A6ADC8;white-space:nowrap'>VMware Tools</td><td style='padding:2px 0'>$toolsHtml</td></tr>"

            $nvidiaHtml = if (-not [string]::IsNullOrEmpty($img.NvidiaDriverVer)) {
                Invoke-HtmlEncode $img.NvidiaDriverVer
            } else { "<span style='color:#585B70'>not detected</span>" }
            $swRows += "<tr><td style='padding:2px 10px 2px 0;color:#A6ADC8;white-space:nowrap'>NVIDIA Driver</td><td style='padding:2px 0'>$nvidiaHtml</td></tr>"

            $swTableHtml = "<table style='border:none;background:none;font-size:0.92em'>" + ($swRows -join "") + "</table>"

            # Last patch
            $patchHtml = if (-not [string]::IsNullOrEmpty($img.LastPatchDate)) {
                Invoke-HtmlEncode $img.LastPatchDate
            } else { "<span style='color:#585B70'>—</span>" }

            # System disk C:
            $diskCHtml = if ($img.SystemDiskGB -ne "" -and $img.SystemDiskGB -ne $null) {
                $free = $img.SystemDiskFreeGB
                $total = $img.SystemDiskGB
                # Warn if free < 10 GB
                $freeStr = if ([double]$free -lt 10) {
                    New-HtmlBadge -Text "$free GB free" -Color "warn"
                } else {
                    "$free GB free"
                }
                "$total GB total &bull; $freeStr"
            } else { "<span style='color:#585B70'>—</span>" }

            # Local admins
            $adminsHtml = if ($img.LocalAdmins -and $img.LocalAdmins.Count -gt 0) {
                $adminLines = ($img.LocalAdmins | ForEach-Object { Invoke-HtmlEncode $_ }) -join $htmlBr
                if ($img.LocalAdmins.Count -gt 3) {
                    "<details class='inline-detail'><summary>$($img.LocalAdmins.Count) members</summary>$adminLines</details>"
                } else { $adminLines }
            } else { "<span style='color:#585B70'>—</span>" }

            # Error indicator
            $errorHtml = ""
            if (-not [string]::IsNullOrEmpty($img.GuestQueryError)) {
                $errorHtml = "<div style='margin-bottom:6px'>" +
                             (New-HtmlBadge -Text "Guest scan: $(Invoke-HtmlEncode $img.GuestQueryError)" -Color "warn") +
                             "</div>"
            }

            # Build detail inner table
            $detailInner = @"
<table style="border:none;background:none;width:100%;font-size:0.93em;border-collapse:collapse">
  <tbody>
    <tr>
      <td style="padding:4px 16px 4px 0;vertical-align:top;white-space:nowrap;color:#A6ADC8;font-weight:600;width:1%">Hostname</td>
      <td style="padding:4px 0;vertical-align:top">$hostnameHtml</td>
      <td style="padding:4px 16px 4px 24px;vertical-align:top;white-space:nowrap;color:#A6ADC8;font-weight:600;width:1%">IP Address</td>
      <td style="padding:4px 0;vertical-align:top">$ipHtml</td>
    </tr>
    <tr>
      <td style="padding:4px 16px 4px 0;vertical-align:top;white-space:nowrap;color:#A6ADC8;font-weight:600">Software</td>
      <td style="padding:4px 0;vertical-align:top">$swTableHtml</td>
      <td style="padding:4px 16px 4px 24px;vertical-align:top;white-space:nowrap;color:#A6ADC8;font-weight:600">Local Admins</td>
      <td style="padding:4px 0;vertical-align:top">$adminsHtml</td>
    </tr>
    <tr>
      <td style="padding:4px 16px 4px 0;vertical-align:top;white-space:nowrap;color:#A6ADC8;font-weight:600">Last Patch</td>
      <td style="padding:4px 0;vertical-align:top">$patchHtml</td>
      <td style="padding:4px 16px 4px 24px;vertical-align:top;white-space:nowrap;color:#A6ADC8;font-weight:600">Disk C:</td>
      <td style="padding:4px 0;vertical-align:top">$diskCHtml</td>
    </tr>
  </tbody>
</table>
"@

            $detailContent = $errorHtml + $detailInner

            $detailRow = @"
<tr class="gi-detail-row">
  <td colspan="8" style="padding:0;border-top:none">
    <details class="gi-details">
      <summary class="gi-summary">Guest Details</summary>
      <div class="gi-detail-body">$detailContent</div>
    </details>
  </td>
</tr>
"@
        }

        $mainRow + "`n" + $detailRow
    }

    $table = New-HtmlTable `
        -Headers @("VM Name","Used by Pools / Farms","CPU","RAM","Disks","Network Adapters","vGPU","Snapshots") `
        -Rows $rows

    # Inline CSS for the detail rows (scoped to this section)
    $css = @"
<style>
.gi-detail-row td { background: #1E1E2E; }
.gi-details { margin: 0; }
.gi-summary {
    cursor: pointer;
    padding: 4px 10px;
    font-size: 0.88em;
    color: #89B4FA;
    user-select: none;
}
.gi-summary::before { color: #89B4FA; }
.gi-detail-body {
    padding: 8px 16px 10px 28px;
    background: #181825;
    border-top: 1px solid #313244;
}
</style>
"@

    return $css + (New-HtmlSection -Id "golden-images" -Title "Golden Images" -Content $table)
}
