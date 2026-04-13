# =============================================================================
# Render-DesktopPools — New-HtmlDesktopPoolsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlDesktopPoolsSection {
    param($Pools, $GlobalEntitlements = $null)
    if (-not $Pools -or $Pools.Count -eq 0) {
        return ""
    }

    $content = [System.Text.StringBuilder]::new()

    # Overview table
    $ovRows = foreach ($p in ($Pools | Sort-Object Name)) {
        $statusBadge = if ($p.Enabled -eq "True") { New-HtmlBadge -Text "Enabled" -Color "ok" } else { New-HtmlBadge -Text "Disabled" -Color "neutral" }
        $typeBadge   = New-HtmlBadge -Text "$($p.Type)" -Color "neutral"
        $srcBadge    = New-HtmlBadge -Text "$($p.Source)" -Color "neutral"
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $p.Name),
            (Invoke-HtmlEncode $p.DisplayName),
            $typeBadge, $srcBadge, $statusBadge,
            (Invoke-HtmlEncode $p.UserAssignment),
            (Invoke-HtmlEncode $p.NumMachines),
            (Invoke-HtmlEncode $p.MinVMs),
            (Invoke-HtmlEncode $p.MaxVMs),
            (Invoke-HtmlEncode $p.SpareVMs),
            (Invoke-HtmlEncode $p.GoldenImage),
            (Invoke-HtmlEncode $p.Snapshot)
        )
    }
    $null = $content.Append((New-HtmlTable -Headers @("Name","Display Name","Type","Source","Status","User Assignment","Current","Min","Max","Spare","Golden Image","Snapshot") -Rows $ovRows))

    # Per-pool detail cards
    foreach ($p in ($Pools | Sort-Object Name)) {
        $statusBadge = if ($p.Enabled -eq "True") { New-HtmlBadge -Text "Enabled" -Color "ok" } else { New-HtmlBadge -Text "Disabled" -Color "neutral" }
        $typeBadge   = New-HtmlBadge -Text "$($p.Type)" -Color "neutral"
        $srcBadge    = New-HtmlBadge -Text "$($p.Source)" -Color "neutral"

        $null = $content.Append("<details class='pool-detail' style='margin-top:16px;border:1px solid #d1d9e6;border-radius:4px;'>")
        $null = $content.Append("<summary style='padding:10px 14px;font-weight:600;cursor:pointer;background:#f7f9fc;border-radius:4px;'>")
        $null = $content.Append("$(Invoke-HtmlEncode $p.Name) $typeBadge $srcBadge")
        $null = $content.Append("</summary>")
        $null = $content.Append("<div style='padding:14px 18px;'>")

        # General
        $null = $content.Append("<h4 style='margin:0 0 8px;font-size:13px;color:#2c5282;'>General</h4>")
        $genRows = @(
            (New-HtmlTableRow -Cells @("Status",          $statusBadge)),
            (New-HtmlTableRow -Cells @("User Assignment",  (Invoke-HtmlEncode $p.UserAssignment))),
            (New-HtmlTableRow -Cells @("Naming Pattern",   (Invoke-HtmlEncode $p.NamingPattern))),
            (New-HtmlTableRow -Cells @("Display Protocol", (Invoke-HtmlEncode $p.DisplayProtocol)))
        )
        if ($p.DisconnectTimeoutPolicy) {
            $tPolicy  = Invoke-HtmlEncode $p.DisconnectTimeoutPolicy
            $tMin     = if ($p.DisconnectTimeoutMin) { Invoke-HtmlEncode $p.DisconnectTimeoutMin } else { "" }
            $tDisplay = $tPolicy
            if ($tMin) { $tDisplay = $tDisplay + " - " + $tMin + " min" }
            $genRows += New-HtmlTableRow -Cells @("Disconnect Timeout", $tDisplay)
        }
        if ($p.GridVgpusEnabled -and $p.GridVgpusEnabled -ne "" -and $p.GridVgpusEnabled -ne "False") {
            $genRows += New-HtmlTableRow -Cells @("vGPU / GRID", "$(Invoke-HtmlEncode $p.VgpuGridProfile)")
        }
        if ($p.Renderer3d -and $p.Renderer3d -ne "") {
            $genRows += New-HtmlTableRow -Cells @("3D Renderer", (Invoke-HtmlEncode $p.Renderer3d))
        }
        if ($p.SessionType)              { $genRows += New-HtmlTableRow -Cells @("Session Type",          (Invoke-HtmlEncode $p.SessionType)) }
        if ($p.UsedVmPolicy)             { $genRows += New-HtmlTableRow -Cells @("Used VM Policy",        (Invoke-HtmlEncode $p.UsedVmPolicy)) }
        if ($p.AllowChooseProtocol -ne "")  { $genRows += New-HtmlTableRow -Cells @("User Chooses Protocol", (Invoke-HtmlEncode $p.AllowChooseProtocol)) }
        $provBadge = if ($p.EnableProvisioning -eq "True") { New-HtmlBadge -Text "Active" -Color "ok" } else { New-HtmlBadge -Text "Paused" -Color "warn" }
        $genRows += New-HtmlTableRow -Cells @("Provisioning", $provBadge)
        if ($p.StopProvisioningOnError -eq "True") { $genRows += New-HtmlTableRow -Cells @("Stop on Error",    (New-HtmlBadge -Text "Yes" -Color "warn")) }
        if ($p.AddVirtualTpm -ne "")     { $genRows += New-HtmlTableRow -Cells @("Virtual TPM",           (Invoke-HtmlEncode $p.AddVirtualTpm)) }
        if ($p.ReusePreExistingAccounts -ne "") { $genRows += New-HtmlTableRow -Cells @("Reuse AD Accounts", (Invoke-HtmlEncode $p.ReusePreExistingAccounts)) }
        if ($p.CreatedAt)                { $genRows += New-HtmlTableRow -Cells @("Created",               (Invoke-HtmlEncode $p.CreatedAt)) }
        if ($p.UpdatedAt)                { $genRows += New-HtmlTableRow -Cells @("Last Updated",          (Invoke-HtmlEncode $p.UpdatedAt)) }
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $genRows))

        # Provisioning (only for non-MANUAL, non-RDS)
        $isRds    = ($p.Type -eq "RDS")
        $isManual = ($p.Source -eq "VIRTUAL_CENTER" -and $p.UserAssignment -eq "DEDICATED" -and -not $p.NamingPattern)
        if (-not $isRds -and $p.GoldenImage) {
            $null = $content.Append("<h4 style='margin:14px 0 8px;font-size:13px;color:#2c5282;'>Provisioning</h4>")
            $provRows = @(
                (New-HtmlTableRow -Cells @("Golden Image",  (Invoke-HtmlEncode $p.GoldenImage))),
                (New-HtmlTableRow -Cells @("GI Path",       (Invoke-HtmlEncode $p.GoldenImagePath))),
                (New-HtmlTableRow -Cells @("Snapshot",      (Invoke-HtmlEncode $p.Snapshot)))
            )
            if ($p.HostOrCluster)  { $provRows += New-HtmlTableRow -Cells @("Host / Cluster",  (Invoke-HtmlEncode $p.HostOrCluster)) }
            if ($p.ResourcePool)   { $provRows += New-HtmlTableRow -Cells @("Resource Pool",   (Invoke-HtmlEncode $p.ResourcePool)) }
            if ($p.VmFolder)       { $provRows += New-HtmlTableRow -Cells @("VM Folder",       (Invoke-HtmlEncode $p.VmFolder)) }
            if ($p.NumCpus) {
                $cpuStr = (Invoke-HtmlEncode $p.NumCpus) + " cores, " + (Invoke-HtmlEncode $p.NumCoresPerSocket) + " per socket"
                $provRows += New-HtmlTableRow -Cells @("CPUs", $cpuStr)
            }
            if ($p.RamMB)          { $provRows += New-HtmlTableRow -Cells @("RAM",             "$(Invoke-HtmlEncode $p.RamMB) MB") }
            $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $provRows))
        }

        # IC Internal VMs (Instant Clone only)
        if ($p.Source -eq "INSTANT_CLONE") {
            $null = $content.Append("<h4 style='margin:14px 0 8px;font-size:13px;color:#2c5282;'>Instant Clone Chain</h4>")
            if ($p.CpTemplate -or $p.CpReplica) {
                $tplDisplay = if ($p.CpTemplate) { $p.CpTemplate } else { "-" }
                $repDisplay = if ($p.CpReplica)  { $p.CpReplica  } else { "-" }
                $icRows = @(
                    (New-HtmlTableRow -Cells @("cp-template", (Invoke-HtmlEncode $tplDisplay))),
                    (New-HtmlTableRow -Cells @("cp-replica",  (Invoke-HtmlEncode $repDisplay)))
                )
                $null = $content.Append((New-HtmlTable -Headers @("Role","VM Name") -Rows $icRows))
            } elseif (-not $viConnected) {
                $null = $content.Append("<p style='color:#888;font-style:italic;'>vCenter not connected. Provide vCenter credentials to see cp-template/replica details.</p>")
            } else {
                $null = $content.Append("<p style='color:#888;font-style:italic;'>No machines provisioned yet.</p>")
            }
        }

        # RDS Farm
        if ($isRds -and $p.FarmName) {
            $null = $content.Append("<h4 style='margin:14px 0 8px;font-size:13px;color:#2c5282;'>RDS Farm</h4>")
            $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows @(
                (New-HtmlTableRow -Cells @("Farm", (Invoke-HtmlEncode $p.FarmName)))
            )))
        }

        # Entitlements
        $null = $content.Append("<h4 style='margin:14px 0 8px;font-size:13px;color:#2c5282;'>Entitlements</h4>")
        if ($p.Entitlements -and $p.Entitlements.Count -gt 0) {
            $null = $content.Append("<p>$(($p.Entitlements | ForEach-Object { Invoke-HtmlEncode $_ }) -join ", ")</p>")
        } else {
            $null = $content.Append("<p><em style='color:#888'>None configured</em></p>")
        }

        # Global Entitlement — name already returned by API in global_entitlement_name
        if ($p.GlobalEntitlementName -and $p.GlobalEntitlementName -ne "") {
            $null = $content.Append("<h4 style='margin:14px 0 8px;font-size:13px;color:#2c5282;'>Global Entitlement</h4>")
            $null = $content.Append("<p>$(Invoke-HtmlEncode $p.GlobalEntitlementName)</p>")
        }

        # vCenter
        if ($p.VcenterName -and $p.VcenterName -ne "") {
            $null = $content.Append("<h4 style='margin:14px 0 8px;font-size:13px;color:#2c5282;'>vCenter</h4>")
            $null = $content.Append("<p>$(Invoke-HtmlEncode $p.VcenterName)</p>")
        }

        $null = $content.Append("</div></details>")
    }

    return New-HtmlSection -Id "desktop-pools" -Title "Desktop Pools" -Content $content.ToString()
}

