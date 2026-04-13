# =============================================================================
# Render-Datastores — New-HtmlDatastoresSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlDatastoresSection {
    param($Datastores, $VcVmInventory = $null)
    if (-not $Datastores -or $Datastores.Count -eq 0) {
        return ""
    }
    $rows = foreach ($ds in ($Datastores | Sort-Object Name)) {
        $usedGB = $ds.CapacityGB - $ds.FreeGB
        $poweredOnCount = "N/A"
        if ($VcVmInventory) {
            $ref = $VcVmInventory.DsNameToRef["$($ds.Name)"]
            if ($ref -and $VcVmInventory.DsVmCount.ContainsKey($ref)) {
                $poweredOnCount = "$($VcVmInventory.DsVmCount[$ref])"
            } elseif ($ref) {
                $poweredOnCount = "0"
            }
        }
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $ds.Name),
            (Invoke-HtmlEncode $ds.Type),
            (Invoke-HtmlEncode "$($ds.CapacityGB)"),
            (Invoke-HtmlEncode "$usedGB"),
            (Invoke-HtmlEncode "$($ds.UsedPct)%"),
            (Invoke-HtmlEncode "$($ds.FreeGB)"),
            (Invoke-HtmlEncode $poweredOnCount)
        )
    }
    $table = New-HtmlTable -Headers @("Name","Type","Total GB","Used GB","Usage %","Free GB","Powered-On VMs") -Rows $rows
    return New-HtmlSection -Id "datastores" -Title "Datastores" -Content $table
}

