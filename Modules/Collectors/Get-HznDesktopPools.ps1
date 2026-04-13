# =============================================================================
# Get-HznDesktopPools — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznDesktopPools {
    if (-not $restToken) { return @() }
    try {
        $pools = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
            "inventory/v12/desktop-pools","inventory/v11/desktop-pools","inventory/v10/desktop-pools",
            "inventory/v9/desktop-pools","inventory/v8/desktop-pools","inventory/v7/desktop-pools",
            "inventory/v6/desktop-pools","inventory/v5/desktop-pools","inventory/v4/desktop-pools",
            "inventory/v3/desktop-pools"
        )
        if (-not $pools) { return @() }

        # SID resolver closure
        $resolveSid = {
            param([string]$sid)
            if ([string]::IsNullOrEmpty($sid)) { return $null }
            try {
                $sidObj = New-Object System.Security.Principal.SecurityIdentifier($sid)
                return $sidObj.Translate([System.Security.Principal.NTAccount]).Value
            } catch { return $sid }
        }

        $result = foreach ($p in @($pools)) {
            $prov = $p.provisioning_settings
            $pat  = $p.pattern_naming_settings
            $disp = $p.display_protocol_settings

            # Golden Image — path fields are direct in provisioning_settings
            $goldenImage     = ""
            $goldenImagePath = ""
            $snapshotName    = ""

            if ($prov) {
                $goldenImagePath = "$($prov.parent_vm_path)"
                if ($goldenImagePath) {
                    $goldenImage = $goldenImagePath -replace '^.*/', ''
                } elseif ($prov.parent_vm_id) {
                    try {
                        $bvmDetail = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
                            "external/v2/base-vms/$($prov.parent_vm_id)",
                            "external/v1/base-vms/$($prov.parent_vm_id)"
                        )
                        if ($bvmDetail) { $goldenImage = "$($bvmDetail.name)"; $goldenImagePath = "$($bvmDetail.path)" }
                    } catch {}
                }

                $snapshotName = if ($prov.snapshot_path) {
                    # snapshot_path may be "/SnapshotName" — strip leading slash
                    ($prov.snapshot_path -replace '^/', '') -replace '^.*/', ''
                } elseif ($prov.base_snapshot_id -and $prov.parent_vm_id) {
                    try {
                        $snaps = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
                            "external/v1/base-snapshots?parent_vm_id=$($prov.parent_vm_id)"
                        )
                        $sn = @($snaps) | Where-Object { $_.id -eq $prov.base_snapshot_id } | Select-Object -First 1
                        if ($sn) { "$($sn.name)" } else { "" }
                    } catch { "" }
                } else { "" }
            }

            # Min/Max/Spare capacities — field is number_of_spare_machines (not ..._powered_on)
            $minVMs   = if ($pat) { "$($pat.min_number_of_machines)" } else { "" }
            $maxVMs   = if ($pat) { "$($pat.max_number_of_machines)" } else { "" }
            $spareVMs = if ($pat) { "$($pat.number_of_spare_machines)" } else { "" }
            $naming   = if ($pat) { "$($pat.naming_pattern)" } else { "" }

            # Entitlements via /entitlements/v1/desktop-pools/{id}
            $entitlements = @()
            try {
                $ents = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("entitlements/v1/desktop-pools/$($p.id)")
                if ($ents -and $ents.ad_user_or_group_ids) {
                    $entitlements = @($ents.ad_user_or_group_ids) | ForEach-Object { & $resolveSid $_ } | Where-Object { $_ }
                }
            } catch {}

            # Farm name (RDS pools only)
            $farmName = ""
            if ($p.farm_id) {
                try {
                    $farm = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
                        "inventory/v5/farms/$($p.farm_id)","inventory/v4/farms/$($p.farm_id)",
                        "inventory/v3/farms/$($p.farm_id)","inventory/v2/farms/$($p.farm_id)"
                    )
                    if ($farm) { $farmName = "$($farm.name)" }
                } catch {}
            }

            # IC Internal VM chain (cp-template, cp-replica) — requires vCenter
            # Pattern from reference: filter header on machines API, Get-VM->Get-View-Id, -ViewType VirtualMachine on UUID lookups
            $cpTemplate = ""; $cpReplica = ""
            if ($viConnected -and $p.source -eq "INSTANT_CLONE") {
                try {
                    # Step 1: get first machine in pool — Horizon API requires filter header (not query param)
                    $firstMachineName = $null
                    foreach ($machineApiVer in @("v8","v7","v6","v5","v4","v3","v2","v1")) {
                        try {
                            $filterJson = '{"type":"Equals","name":"desktop_pool_id","value":"' + $p.id + '"}'
                            $machinesRaw = Invoke-RestMethod -Uri "$restBase/inventory/$machineApiVer/machines" `
                                -Method Get `
                                -Headers @{ Authorization = "Bearer $restToken"; filter = $filterJson } `
                                -ErrorAction Stop
                            $filtered = @($machinesRaw) | Where-Object { $_.desktop_pool_id -eq $p.id }
                            if ($filtered.Count -gt 0) {
                                $firstMachineName = "$($filtered[0].name)"
                                break
                            }
                        } catch { }
                    }

                    if ($firstMachineName) {
                        # Step 2: Get-VM by name (exact match), then Get-View by Id for ExtraConfig
                        $poolVm = Get-VM -Name $firstMachineName -ErrorAction SilentlyContinue | Select-Object -First 1
                        $machineView = if ($poolVm) {
                            Get-View -Id $poolVm.Id -Property Name,Config.ExtraConfig -ErrorAction SilentlyContinue
                        } else {
                            # Fallback: Get-View -Filter (substring match — no regex anchors)
                            Get-View -ViewType VirtualMachine -Filter @{"Name" = $firstMachineName} `
                                -Property Name,Config.ExtraConfig -ErrorAction SilentlyContinue |
                                Where-Object { $_.Name -eq $firstMachineName } | Select-Object -First 1
                        }

                        if ($machineView -and $machineView.Config -and $machineView.Config.ExtraConfig) {
                            # Step 3: read UUIDs from ExtraConfig, look up cp-template/replica VMs
                            $tplUuid = $machineView.Config.ExtraConfig |
                                Where-Object { $_.Key -eq "cloneprep.internal.template.uuid" } |
                                Select-Object -ExpandProperty Value
                            if ($tplUuid) {
                                $tplView = Get-View -ViewType VirtualMachine `
                                    -Filter @{"Config.InstanceUuid" = $tplUuid} `
                                    -Property Name -ErrorAction SilentlyContinue |
                                    Where-Object { $_.Name -like "cp-template*" } | Select-Object -First 1
                                if ($tplView) { $cpTemplate = "$($tplView.Name)" }
                            }

                            $repUuid = $machineView.Config.ExtraConfig |
                                Where-Object { $_.Key -eq "cloneprep.replica.uuid" } |
                                Select-Object -ExpandProperty Value
                            if ($repUuid) {
                                $repView = Get-View -ViewType VirtualMachine `
                                    -Filter @{"Config.InstanceUuid" = $repUuid} `
                                    -Property Name -ErrorAction SilentlyContinue |
                                    Where-Object { $_.Name -like "cp-replica*" } | Select-Object -First 1
                                if ($repView) { $cpReplica = "$($repView.Name)" }
                            }
                        }
                    }
                } catch { Write-RunspaceLog "IC chain lookup failed for pool $($p.name): $($_.Exception.Message)" "WARN" }
            }

            # Display / 3D settings — nested under display_protocol_settings
            $dispProto          = if ($disp) { "$($disp.default_display_protocol)" } else { "" }
            $gpuEnabled         = if ($disp) { "$($disp.grid_vgpus_enabled)" } else { "" }
            $gpuProfile         = if ($disp) { "$($disp.vgpu_grid_profile)" } else { "" }
            $renderer3d         = if ($disp) { "$($disp.renderer3d)" } else { "" }
            $allowChooseProto   = if ($disp) { "$($disp.allow_users_to_choose_protocol)" } else { "" }

            # Session settings
            $discTimeoutPolicy  = ""
            $discTimeoutMin     = ""
            $usedVmPolicy       = ""
            if ($p.session_settings) {
                $discTimeoutPolicy = "$($p.session_settings.disconnected_session_timeout_policy)"
                $discTimeoutMin    = "$($p.session_settings.disconnected_session_timeout_minutes)"
                $usedVmPolicy      = "$($p.session_settings.used_vm_policy)"
            }

            # Hardware — fields are direct on provisioning_settings
            $numCpus            = if ($prov) { "$($prov.compute_profile_num_cpus)" } else { "" }
            $numCoresSocket     = if ($prov) { "$($prov.compute_profile_num_cores_per_socket)" } else { "" }
            $ramMB              = if ($prov) { "$($prov.compute_profile_ram_mb)" } else { "" }
            $vmFolder           = if ($prov) { "$($prov.vm_folder_path)" } else { "" }
            $resourcePool       = if ($prov) { "$($prov.resource_pool_path)" } else { "" }
            $hostOrCluster      = if ($prov) { "$($prov.host_or_cluster_path)" } else { "" }
            $addVirtualTpm      = if ($prov) { "$($prov.add_virtual_tpm)" } else { "" }

            # Customization settings
            $reuseAccounts      = if ($p.customization_settings) { "$($p.customization_settings.reuse_pre_existing_accounts)" } else { "" }

            # Timestamps (epoch ms → local datetime)
            $createdAt = ""
            $updatedAt = ""
            if ($p.created_at) {
                try { $createdAt = ([datetime]'1970-01-01T00:00:00Z').AddMilliseconds([long]$p.created_at).ToLocalTime().ToString("yyyy-MM-dd HH:mm") } catch {}
            }
            if ($p.updated_at) {
                try { $updatedAt = ([datetime]'1970-01-01T00:00:00Z').AddMilliseconds([long]$p.updated_at).ToLocalTime().ToString("yyyy-MM-dd HH:mm") } catch {}
            }

            [PSCustomObject]@{
                Id                      = "$($p.id)"
                Name                    = "$($p.name)"
                DisplayName             = "$($p.display_name)"
                Type                    = "$($p.type)"
                Source                  = "$($p.source)"
                SessionType             = "$($p.session_type)"
                Enabled                 = "$($p.enabled)"
                EnableProvisioning      = "$($p.enable_provisioning)"
                StopProvisioningOnError = "$($p.stop_provisioning_on_error)"
                UserAssignment          = "$($p.user_assignment)"
                NumMachines             = "$($p.num_machines)"
                VcenterName             = "$($p.vcenter_name)"
                GoldenImage             = $goldenImage
                GoldenImagePath         = $goldenImagePath
                Snapshot                = $snapshotName
                MinVMs                  = $minVMs
                MaxVMs                  = $maxVMs
                SpareVMs                = $spareVMs
                NamingPattern           = $naming
                CpTemplate              = $cpTemplate
                CpReplica               = $cpReplica
                Entitlements            = $entitlements
                FarmName                = $farmName
                DisplayProtocol         = $dispProto
                AllowChooseProtocol     = $allowChooseProto
                GridVgpusEnabled        = $gpuEnabled
                VgpuGridProfile         = $gpuProfile
                Renderer3d              = $renderer3d
                DisconnectTimeoutPolicy = $discTimeoutPolicy
                DisconnectTimeoutMin    = $discTimeoutMin
                UsedVmPolicy            = $usedVmPolicy
                VmFolder                = $vmFolder
                ResourcePool            = $resourcePool
                HostOrCluster           = $hostOrCluster
                NumCpus                 = $numCpus
                NumCoresPerSocket       = $numCoresSocket
                RamMB                   = $ramMB
                AddVirtualTpm           = $addVirtualTpm
                ReusePreExistingAccounts = $reuseAccounts
                CreatedAt               = $createdAt
                UpdatedAt               = $updatedAt
                GlobalEntitlementId     = "$($p.global_desktop_entitlement_id)"
                GlobalEntitlementName   = "$($p.global_entitlement_name)"
            }
        }
        return @($result)
    } catch {
        Write-RunspaceLog "WARNING: Desktop Pools collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

