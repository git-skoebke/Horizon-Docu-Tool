# =============================================================================
# Render-RdsFarms — New-HtmlRdsFarmsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlRdsFarmsSection {
    param($Farms)
    if (-not $Farms -or $Farms.Count -eq 0) {
        return ""
    }

    $content = [System.Text.StringBuilder]::new()

    foreach ($f in ($Farms | Sort-Object Name)) {
        $statusBadge = if ($f.Enabled -eq "True") { New-HtmlBadge -Text "Enabled" -Color "ok" } else { New-HtmlBadge -Text "Disabled" -Color "neutral" }
        $typeBadge   = New-HtmlBadge -Text "$($f.Type)" -Color "neutral"
        $srcBadge    = New-HtmlBadge -Text "$($f.Source)" -Color "neutral"

        $displayInfo = if ($f.DisplayName -and $f.DisplayName -ne $f.Name) {
            " <span class='card-meta'>($(Invoke-HtmlEncode $f.DisplayName))</span>"
        } else { "" }

        $null = $content.Append("<details class='detail-card'>")
        $null = $content.Append("<summary>")
        $null = $content.Append((Invoke-HtmlEncode $f.Name))
        $null = $content.Append($displayInfo)
        $null = $content.Append(" <span class='card-meta'>$typeBadge &nbsp;$srcBadge &nbsp;$statusBadge</span>")
        $null = $content.Append("</summary>")
        $null = $content.Append("<div>")

        # General
        $null = $content.Append("<h4>General</h4>")
        $genRows = @(
            (New-HtmlTableRow -Cells @("Status",            $statusBadge)),
            (New-HtmlTableRow -Cells @("Naming Pattern",    (Invoke-HtmlEncode $f.NamingPattern))),
            (New-HtmlTableRow -Cells @("Max Servers",       (Invoke-HtmlEncode $f.MaxServers))),
            (New-HtmlTableRow -Cells @("Min Ready VMs",     (Invoke-HtmlEncode $f.MinReadyVMs))),
            (New-HtmlTableRow -Cells @("Display Protocol",  (Invoke-HtmlEncode $f.DisplayProtocol)))
        )
        if ($f.AllowChooseProtocol -ne "") { $genRows += New-HtmlTableRow -Cells @("User Chooses Protocol", (Invoke-HtmlEncode $f.AllowChooseProtocol)) }
        if ($f.SessionCollaboration -ne "") { $genRows += New-HtmlTableRow -Cells @("Session Collaboration", (Invoke-HtmlEncode $f.SessionCollaboration)) }
        if ($f.OperatingSystem)     { $genRows += New-HtmlTableRow -Cells @("Operating System",  (Invoke-HtmlEncode $f.OperatingSystem)) }
        if ($f.MaxSessionType)      { $genRows += New-HtmlTableRow -Cells @("Max Sessions",      (Invoke-HtmlEncode $f.MaxSessionType)) }
        $provBadge = if ($f.EnableProvisioning -eq "True") { New-HtmlBadge -Text "Active" -Color "ok" } else { New-HtmlBadge -Text "Paused" -Color "warn" }
        $genRows += New-HtmlTableRow -Cells @("Provisioning", $provBadge)
        if ($f.StopProvisioningOnError -eq "True") { $genRows += New-HtmlTableRow -Cells @("Stop on Error", (New-HtmlBadge -Text "Yes" -Color "warn")) }
        if ($f.TpsScope)            { $genRows += New-HtmlTableRow -Cells @("TPS Scope",         (Invoke-HtmlEncode $f.TpsScope)) }
        if ($f.CreatedAt)           { $genRows += New-HtmlTableRow -Cells @("Created",            (Invoke-HtmlEncode $f.CreatedAt)) }
        if ($f.UpdatedAt)           { $genRows += New-HtmlTableRow -Cells @("Last Updated",       (Invoke-HtmlEncode $f.UpdatedAt)) }
        $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $genRows))

        # Session Settings
        if ($f.DiscTimeoutPolicy -or $f.EmptyTimeoutPolicy -or $f.PreLaunchPolicy) {
            $null = $content.Append("<h4>Session Settings</h4>")
            $sessRows = @()
            if ($f.DiscTimeoutPolicy) {
                $discVal = Invoke-HtmlEncode $f.DiscTimeoutPolicy
                if ($f.DiscTimeoutMin) { $discVal = $discVal + " - " + (Invoke-HtmlEncode $f.DiscTimeoutMin) + " min" }
                $sessRows += New-HtmlTableRow -Cells @("Disconnected Timeout", $discVal)
            }
            if ($f.EmptyTimeoutPolicy) {
                $emptyVal = Invoke-HtmlEncode $f.EmptyTimeoutPolicy
                if ($f.EmptyTimeoutMin) { $emptyVal = $emptyVal + " - " + (Invoke-HtmlEncode $f.EmptyTimeoutMin) + " min" }
                $sessRows += New-HtmlTableRow -Cells @("Empty Session Timeout", $emptyVal)
            }
            if ($f.PreLaunchPolicy) {
                $plVal = Invoke-HtmlEncode $f.PreLaunchPolicy
                if ($f.PreLaunchMin) { $plVal = $plVal + " - " + (Invoke-HtmlEncode $f.PreLaunchMin) + " min" }
                $sessRows += New-HtmlTableRow -Cells @("Pre-Launch Timeout", $plVal)
            }
            if ($f.LogoffAfterTimeout -ne "") { $sessRows += New-HtmlTableRow -Cells @("Logoff After Timeout", (Invoke-HtmlEncode $f.LogoffAfterTimeout)) }
            $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $sessRows))
        }

        # Provisioning
        if ($f.GoldenImage) {
            $null = $content.Append("<h4>Provisioning</h4>")
            $provRows = @(
                (New-HtmlTableRow -Cells @("Golden Image",  (Invoke-HtmlEncode $f.GoldenImage))),
                (New-HtmlTableRow -Cells @("GI Path",       (Invoke-HtmlEncode $f.GoldenImagePath))),
                (New-HtmlTableRow -Cells @("Snapshot",      (Invoke-HtmlEncode $f.Snapshot)))
            )
            if ($f.Datacenter)     { $provRows += New-HtmlTableRow -Cells @("Datacenter",      (Invoke-HtmlEncode $f.Datacenter)) }
            if ($f.HostOrCluster)   { $provRows += New-HtmlTableRow -Cells @("Host / Cluster",  (Invoke-HtmlEncode $f.HostOrCluster)) }
            if ($f.ResourcePool)    { $provRows += New-HtmlTableRow -Cells @("Resource Pool",   (Invoke-HtmlEncode $f.ResourcePool)) }
            if ($f.VmFolder)        { $provRows += New-HtmlTableRow -Cells @("VM Folder",       (Invoke-HtmlEncode $f.VmFolder)) }
            if ($f.UseVsan -ne "")  { $provRows += New-HtmlTableRow -Cells @("Use vSAN",        (Invoke-HtmlEncode $f.UseVsan)) }
            if ($f.UseViewAccel -ne "") { $provRows += New-HtmlTableRow -Cells @("View Storage Accelerator", (Invoke-HtmlEncode $f.UseViewAccel)) }
            $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $provRows))
        }

        # IC Image State / Scheduled Maintenance
        if ($f.IcImageState -or $f.SchedMaintNext) {
            $null = $content.Append("<h4>Image Status</h4>")
            $imgRows = @()
            if ($f.IcImageState) {
                $stateColor = if ($f.IcImageState -eq "READY") { "ok" } else { "warn" }
                $imgRows += New-HtmlTableRow -Cells @("IC Image State", (New-HtmlBadge -Text $f.IcImageState -Color $stateColor))
            }
            if ($f.IcOperation)      { $imgRows += New-HtmlTableRow -Cells @("Current Operation",  (Invoke-HtmlEncode $f.IcOperation)) }
            if ($f.SchedMaintNext)   { $imgRows += New-HtmlTableRow -Cells @("Next Maintenance",   (Invoke-HtmlEncode $f.SchedMaintNext)) }
            if ($f.SchedMaintPeriod) { $imgRows += New-HtmlTableRow -Cells @("Maintenance Period", (Invoke-HtmlEncode $f.SchedMaintPeriod)) }
            if ($f.SchedMaintTime)   { $imgRows += New-HtmlTableRow -Cells @("Maintenance Time",   (Invoke-HtmlEncode $f.SchedMaintTime)) }
            if ($f.SchedMaintLogoff) { $imgRows += New-HtmlTableRow -Cells @("Logoff Policy",      (Invoke-HtmlEncode $f.SchedMaintLogoff)) }
            $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $imgRows))
        }

        # Customization
        if ($f.AdContainer -or $f.CustomizationType) {
            $null = $content.Append("<h4>Customization</h4>")
            $custRows = @()
            if ($f.CustomizationType) { $custRows += New-HtmlTableRow -Cells @("Type",              (Invoke-HtmlEncode $f.CustomizationType)) }
            if ($f.AdContainer)       { $custRows += New-HtmlTableRow -Cells @("AD Container",      (Invoke-HtmlEncode $f.AdContainer)) }
            if ($f.ReusePreExistingAccounts -ne "") { $custRows += New-HtmlTableRow -Cells @("Reuse AD Accounts", (Invoke-HtmlEncode $f.ReusePreExistingAccounts)) }
            $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $custRows))
        }

        # Instant Clone Chain
        if ($f.Source -eq "INSTANT_CLONE") {
            $null = $content.Append("<h4>Instant Clone Chain</h4>")
            if ($f.CpTemplate -or $f.CpReplica) {
                $tplDisplay = if ($f.CpTemplate) { $f.CpTemplate } else { "-" }
                $repDisplay = if ($f.CpReplica)  { $f.CpReplica  } else { "-" }
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

        $null = $content.Append("</div></details>")
    }

    return New-HtmlSection -Id "rds-farms" -Title "RDS Farms" -Content $content.ToString()
}
