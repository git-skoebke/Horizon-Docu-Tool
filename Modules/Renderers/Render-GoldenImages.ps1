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
    $content = [System.Text.StringBuilder]::new()

    foreach ($img in ($Images | Sort-Object VmName)) {

        # VM name with badge if not found in vCenter
        $nameHtml = if (-not $img.Found) {
            (Invoke-HtmlEncode $img.VmName) + " " + (New-HtmlBadge -Text "not found in vCenter" -Color "warn")
        } else { Invoke-HtmlEncode $img.VmName }

        # CPU topology for summary
        $cpuSummary = if ($img.vCPU -ne "") { "$($img.vCPU) vCPU" } else { "" }
        $ramSummary = if ($img.RamGB -ne "") { "$($img.RamGB) GB RAM" } else { "" }
        $metaParts = @($cpuSummary, $ramSummary) | Where-Object { $_ -ne "" }
        $metaStr = if ($metaParts.Count -gt 0) { ($metaParts -join " &bull; ") } else { "" }

        $null = $content.Append("<details class='detail-card'>")
        $null = $content.Append("<summary>")
        $null = $content.Append($nameHtml)
        if ($img.UsedByPools) {
            $null = $content.Append(" <span class='card-meta'>$(Invoke-HtmlEncode $img.UsedByPools)</span>")
        }
        if ($metaStr) {
            $null = $content.Append(" <span class='card-meta'>$metaStr</span>")
        }
        $null = $content.Append("</summary>")
        $null = $content.Append("<div>")

        # Hardware
        $null = $content.Append("<h4>Hardware</h4>")
        $cpuSockStr = "$($img.Sockets)S x $($img.CoresPerSocket)C"
        $cpuHtml    = if ($img.vCPU -ne "") { "$($img.vCPU) vCPU - $cpuSockStr" } else { "N/A" }
        $ramHtml    = if ($img.RamGB -ne "") { "$($img.RamGB) GB" } else { "N/A" }

        $hwRows = @(
            (New-HtmlTableRow -Cells @("CPU",  $cpuHtml)),
            (New-HtmlTableRow -Cells @("RAM",  $ramHtml))
        )

        # Disks
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
        $hwRows += New-HtmlTableRow -Cells @("Disks", $disksHtml)

        # Network adapters
        $nicsHtml = if ($img.NetworkAdapters -and $img.NetworkAdapters.Count -gt 0) {
            ($img.NetworkAdapters | ForEach-Object {
                (Invoke-HtmlEncode $_.Type) + ": " + (Invoke-HtmlEncode $_.Network)
            }) -join $htmlBr
        } else { "N/A" }
        $hwRows += New-HtmlTableRow -Cells @("Network Adapters", $nicsHtml)

        # vGPU
        $vgpuHtml = if (-not [string]::IsNullOrEmpty($img.VgpuProfile)) {
            New-HtmlBadge -Text (Invoke-HtmlEncode $img.VgpuProfile) -Color "ok"
        } else { "None" }
        $hwRows += New-HtmlTableRow -Cells @("vGPU", $vgpuHtml)

        # Snapshot count
        $snapCount = $img.SnapshotCount
        $snapHtml  = if ($snapCount -gt 0) {
            New-HtmlBadge -Text "$snapCount" -Color "warn"
        } else { "0" }
        $hwRows += New-HtmlTableRow -Cells @("Snapshots", $snapHtml)

        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $hwRows))

        # Guest Details (only if scan was attempted or IPs known)
        $showDetail = $img.GuestScanned -or ($img.IpAddresses -and $img.IpAddresses.Count -gt 0) -or
                      (-not [string]::IsNullOrEmpty($img.GuestHostName))

        if ($showDetail) {
            $null = $content.Append("<h4>Guest Details</h4>")

            # Error indicator
            if (-not [string]::IsNullOrEmpty($img.GuestQueryError)) {
                $null = $content.Append("<div style='margin-bottom:8px'>")
                $null = $content.Append((New-HtmlBadge -Text "Guest scan: $(Invoke-HtmlEncode $img.GuestQueryError)" -Color "warn"))
                $null = $content.Append("</div>")
            }

            $guestRows = @()

            # Hostname
            $hostnameHtml = if (-not [string]::IsNullOrEmpty($img.GuestHostName)) {
                Invoke-HtmlEncode $img.GuestHostName
            } else { "N/A" }
            $guestRows += New-HtmlTableRow -Cells @("Hostname", $hostnameHtml)

            # IP Addresses
            $ipHtml = if ($img.IpAddresses -and $img.IpAddresses.Count -gt 0) {
                ($img.IpAddresses | ForEach-Object { Invoke-HtmlEncode $_ }) -join ", "
            } else { "N/A" }
            $guestRows += New-HtmlTableRow -Cells @("IP Address", $ipHtml)

            # Software versions
            $swItems = @(
                @{ Label = "Horizon Agent";     Val = $img.HorizonAgentVer },
                @{ Label = "App Volumes Agent"; Val = $img.AppVolumesVer },
                @{ Label = "DEM";               Val = $img.DemVer },
                @{ Label = "FSLogix";           Val = $img.FsLogixVer },
                @{ Label = "VMware Tools";      Val = $img.VmwareToolsVer },
                @{ Label = "NVIDIA Driver";     Val = $img.NvidiaDriverVer }
            )
            foreach ($sw in $swItems) {
                $val = if (-not [string]::IsNullOrEmpty($sw.Val)) { Invoke-HtmlEncode $sw.Val } else { "<span style='color:#888'>not detected</span>" }
                $guestRows += New-HtmlTableRow -Cells @($sw.Label, $val)
            }

            # Last patch
            $patchHtml = if (-not [string]::IsNullOrEmpty($img.LastPatchDate)) {
                Invoke-HtmlEncode $img.LastPatchDate
            } else { "N/A" }
            $guestRows += New-HtmlTableRow -Cells @("Last Patch", $patchHtml)

            # System disk C:
            $diskCHtml = if ($img.SystemDiskGB -ne "" -and $img.SystemDiskGB -ne $null) {
                $free = $img.SystemDiskFreeGB
                $total = $img.SystemDiskGB
                $freeStr = if ([double]$free -lt 10) {
                    New-HtmlBadge -Text "$free GB free" -Color "warn"
                } else {
                    "$free GB free"
                }
                "$total GB total &bull; $freeStr"
            } else { "N/A" }
            $guestRows += New-HtmlTableRow -Cells @("Disk C:", $diskCHtml)

            # Local admins
            $adminsHtml = if ($img.LocalAdmins -and $img.LocalAdmins.Count -gt 0) {
                $adminLines = ($img.LocalAdmins | ForEach-Object { Invoke-HtmlEncode $_ }) -join $htmlBr
                if ($img.LocalAdmins.Count -gt 3) {
                    "<details class='inline-detail'><summary>$($img.LocalAdmins.Count) members</summary>$adminLines</details>"
                } else { $adminLines }
            } else { "N/A" }
            $guestRows += New-HtmlTableRow -Cells @("Local Admins", $adminsHtml)

            $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $guestRows))
        }

        $null = $content.Append("</div></details>")
    }

    return New-HtmlSection -Id "golden-images" -Title "Golden Images" -Content $content.ToString()
}
