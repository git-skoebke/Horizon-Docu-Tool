# =============================================================================
# Get-HznInternalTemplateVMs — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznInternalTemplateVMs {
    param($DesktopPools, $RdsFarms)
    if (-not $viConnected) { return @() }
    try {
        # Fetch all cp-template* and cp-replica* VMs from vCenter in one call
        $internalVMs = @()
        try {
            $cpViews = Get-View -ViewType VirtualMachine `
                -Property Name,Config.ExtraConfig,Config.InstanceUuid `
                -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "cp-template*" -or $_.Name -like "cp-replica*" }
            if ($cpViews) { $internalVMs = @($cpViews) }
        } catch {
            Write-RunspaceLog "WARNING: Internal Template VM query failed: $($_.Exception.Message)" "WARN"
            return @()
        }

        if ($internalVMs.Count -eq 0) { return @() }

        # Build InstanceUuid -> VM name map for template<->replica cross-reference
        $uuidToName = @{}
        foreach ($vm in $internalVMs) {
            if ($vm.Config -and $vm.Config.InstanceUuid) {
                $uuidToName[$vm.Config.InstanceUuid] = $vm.Name
            }
        }

        # Build map: VM name -> ExtraConfig hashtable
        $vmExtraCfg = @{}
        foreach ($vm in $internalVMs) {
            $cfg = @{}
            if ($vm.Config -and $vm.Config.ExtraConfig) {
                foreach ($kv in $vm.Config.ExtraConfig) { $cfg[$kv.Key] = $kv.Value }
            }
            $vmExtraCfg[$vm.Name] = $cfg
        }

        # Build lookup: cp-template UUID -> replica VM name
        $tplUuidToReplica = @{}
        foreach ($vm in ($internalVMs | Where-Object { $_.Name -like "cp-replica*" })) {
            $cfg     = $vmExtraCfg[$vm.Name]
            $tplUuid = $cfg['cloneprep.internal.template.uuid']
            if ($tplUuid) {
                $tplUuidToReplica[$tplUuid] = $vm.Name
            }
        }

        # Build lookup: Golden Image + Snapshot + Pools from Desktop Pools and RDS Farms
        # Key: GoldenImagePath  Value: { Name, Snapshot, Pools[] }
        # Key: CpTemplate name  Value: same  (fallback when path matching fails)
        $giByPath    = @{}
        $giByTplName = @{}
        $giByRepName = @{}

        foreach ($pool in @($DesktopPools)) {
            $entry = [PSCustomObject]@{
                GoldenImage = "$($pool.GoldenImage)"
                Snapshot    = "$($pool.Snapshot)"
                Pools       = [System.Collections.Generic.List[string]]::new()
            }
            $entry.Pools.Add($pool.Name)

            if ($pool.GoldenImagePath) { $giByPath[$pool.GoldenImagePath] = $entry }
            if ($pool.CpTemplate)      { $giByTplName[$pool.CpTemplate]   = $entry }
            if ($pool.CpReplica)       { $giByRepName[$pool.CpReplica]    = $entry }
        }
        foreach ($farm in @($RdsFarms)) {
            $label = $farm.Name + " (RDS)"
            $entry = [PSCustomObject]@{
                GoldenImage = "$($farm.GoldenImage)"
                Snapshot    = "$($farm.Snapshot)"
                Pools       = [System.Collections.Generic.List[string]]::new()
            }
            $entry.Pools.Add($label)

            if ($farm.GoldenImagePath) { $giByPath[$farm.GoldenImagePath] = $entry }
            if ($farm.CpTemplate)      { $giByTplName[$farm.CpTemplate]   = $entry }
            if ($farm.CpReplica)       { $giByRepName[$farm.CpReplica]    = $entry }
        }

        # Helper: resolve GI info for a given template VM
        $resolveGI = {
            param([string]$tplName, [string]$repName)
            # 1. Match via src-path in replica ExtraConfig
            if ($repName -and $vmExtraCfg.ContainsKey($repName)) {
                $srcPath = $vmExtraCfg[$repName]['managed.vm.src-path']
                if ($srcPath -and $giByPath.ContainsKey($srcPath)) {
                    return $giByPath[$srcPath]
                }
            }
            # 2. Match via src-path in template ExtraConfig
            if ($tplName -and $vmExtraCfg.ContainsKey($tplName)) {
                $srcPath = $vmExtraCfg[$tplName]['managed.vm.src-path']
                if ($srcPath -and $giByPath.ContainsKey($srcPath)) {
                    return $giByPath[$srcPath]
                }
            }
            # 3. Match by template VM name from pool's CpTemplate field
            if ($tplName -and $giByTplName.ContainsKey($tplName)) {
                return $giByTplName[$tplName]
            }
            # 4. Match by replica VM name from pool's CpReplica field
            if ($repName -and $giByRepName.ContainsKey($repName)) {
                return $giByRepName[$repName]
            }
            return $null
        }

        # Build result: one row per cp-template VM
        $templates = $internalVMs | Where-Object { $_.Name -like "cp-template*" } | Sort-Object { $_.Name }

        $result = foreach ($tpl in $templates) {
            $tplName  = $tpl.Name
            $tplUuid  = if ($tpl.Config) { $tpl.Config.InstanceUuid } else { "" }

            # Find associated replica
            $repName  = if ($tplUuid -and $tplUuidToReplica.ContainsKey($tplUuid)) {
                $tplUuidToReplica[$tplUuid]
            } else { "" }

            # Resolve Golden Image / Snapshot / Pool(s)
            $gi = & $resolveGI $tplName $repName

            [PSCustomObject]@{
                TemplateName = $tplName
                ReplicaName  = $repName
                GoldenImage  = if ($gi) { $gi.GoldenImage } else { "" }
                Snapshot     = if ($gi) { $gi.Snapshot    } else { "" }
                DesktopPools = if ($gi) { $gi.Pools -join ", " } else { "" }
            }
        }

        # Also surface any orphaned replicas (no matching template found)
        $matchedReplicas = @($result | Where-Object { $_.ReplicaName } | ForEach-Object { $_.ReplicaName })
        $orphanReplicas  = $internalVMs |
            Where-Object { $_.Name -like "cp-replica*" -and $matchedReplicas -notcontains $_.Name }

        $orphanRows = foreach ($rep in ($orphanReplicas | Sort-Object { $_.Name })) {
            $repName = $rep.Name
            $gi      = & $resolveGI "" $repName
            [PSCustomObject]@{
                TemplateName = ""
                ReplicaName  = $repName
                GoldenImage  = if ($gi) { $gi.GoldenImage } else { "" }
                Snapshot     = if ($gi) { $gi.Snapshot    } else { "" }
                DesktopPools = if ($gi) { $gi.Pools -join ", " } else { "" }
            }
        }

        return @($result) + @($orphanRows)
    } catch {
        Write-RunspaceLog "WARNING: Internal Template VMs collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}
