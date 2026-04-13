# =============================================================================
# Render-InternalTemplateVMs >/dev/null 2>&1 &#8212; New-HtmlInternalTemplateVMsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlInternalTemplateVMsSection {
    param($TemplateVMs)
    if (-not $TemplateVMs -or $TemplateVMs.Count -eq 0) {
        return ""
    }

    $redStyle     = " style='color:#c53030'"
    $missingHtml  = "<span style='color:#c53030;font-style:italic'>missing</span>"
    $dashHtml     = "<span style='color:#a0aec0;font-style:italic'>>/dev/null 2>&1 &#8212;</span>"

    # Sort: normal entries first, orphan (missing GoldenImage or Snapshot or DesktopPools) last
    $sortedVMs = @($TemplateVMs | Sort-Object {
        [int]([string]::IsNullOrEmpty($_.GoldenImage) -or [string]::IsNullOrEmpty($_.Snapshot) -or [string]::IsNullOrEmpty($_.DesktopPools))
    })

    $rows = foreach ($vm in $sortedVMs) {
        # Red name styling when Golden Image, Snapshot or Desktop Pool is missing
        $isOrphan = [string]::IsNullOrEmpty($vm.GoldenImage) -or [string]::IsNullOrEmpty($vm.Snapshot) -or [string]::IsNullOrEmpty($vm.DesktopPools)

        $tplCell = if ($vm.TemplateName) {
            if ($isOrphan) {
                "<span" + $redStyle + ">" + (Invoke-HtmlEncode $vm.TemplateName) + "</span>"
            } else {
                Invoke-HtmlEncode $vm.TemplateName
            }
        } else { $dashHtml }

        $repCell = if ($vm.ReplicaName) {
            if ($isOrphan) {
                "<span" + $redStyle + ">" + (Invoke-HtmlEncode $vm.ReplicaName) + "</span>"
            } else {
                Invoke-HtmlEncode $vm.ReplicaName
            }
        } else { $dashHtml }

        $giCell   = if ($vm.GoldenImage)  { Invoke-HtmlEncode $vm.GoldenImage  } else { $missingHtml }
        $snapCell = if ($vm.Snapshot)     { Invoke-HtmlEncode $vm.Snapshot     } else { $missingHtml }
        $poolCell = if ($vm.DesktopPools) { Invoke-HtmlEncode $vm.DesktopPools } else { $missingHtml }

        New-HtmlTableRow -Cells @($tplCell, $repCell, $giCell, $snapCell, $poolCell)
    }

    $tplCount    = @($TemplateVMs | Where-Object { $_.TemplateName }).Count
    $repCount    = @($TemplateVMs | Where-Object { $_.ReplicaName  }).Count
    $orphanCount = @($TemplateVMs | Where-Object {
        [string]::IsNullOrEmpty($_.GoldenImage) -or [string]::IsNullOrEmpty($_.Snapshot) -or [string]::IsNullOrEmpty($_.DesktopPools)
    }).Count

    $summary = "<p style='margin-top:8px;color:#4a5568'>Total: $tplCount cp-template, $repCount cp-replica VMs"
    if ($orphanCount -gt 0) {
        $summary += " &nbsp;|&nbsp; <span style='color:#c53030;font-weight:600'>$orphanCount without Golden Image / Snapshot / Desktop Pool</span>"
    }
    $summary += "</p>"

    $table = New-HtmlTable -Headers @("Template (cp-template)","Replica (cp-replica)","Golden Image","Snapshot","Desktop Pool(s)") -Rows $rows
    return New-HtmlSection -Id "internal-template-vms" -Title "Internal Template VMs" -Content ($table + $summary)
}
