# =============================================================================
# Get-HznRdsFarms — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznRdsFarms {
    if (-not $restToken) { return @() }
    try {
        $farms = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
            "inventory/v9/farms","inventory/v8/farms","inventory/v7/farms","inventory/v6/farms",
            "inventory/v5/farms","inventory/v4/farms","inventory/v3/farms","inventory/v2/farms","inventory/v1/farms"
        )
        if (-not $farms) { return @() }
        $result = foreach ($f in @($farms)) {
            # AUTOMATED farms nest everything under automated_farm_settings (v9+)
            $afs  = $f.automated_farm_settings
            $prov = if ($afs) { $afs.provisioning_settings } else { $f.provisioning_settings }
            $pat  = if ($afs) { $afs.pattern_naming_settings } else { $f.pattern_naming_settings }

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

            # Provisioning paths
            $hostOrCluster = if ($prov) { "$($prov.host_or_cluster_path)" } else { "" }
            $resourcePool  = if ($prov) { "$($prov.resource_pool_path)" } else { "" }
            $vmFolder      = if ($prov) { "$($prov.vm_folder_path)" } else { "" }
            $datacenter    = if ($prov) { "$($prov.datacenter_name)" } else { "" }

            # Naming / capacity
            $namingPattern = if ($pat) { "$($pat.naming_pattern)" } else { "" }
            $maxServers    = if ($pat) { "$($pat.max_number_of_rds_servers)" } else { "" }
            # Fallback: top-level max_number_of_rds_servers
            if (-not $maxServers -and $f.max_number_of_rds_servers) { $maxServers = "$($f.max_number_of_rds_servers)" }
            $minReadyVMs   = if ($afs) { "$($afs.min_ready_vms)" } else { "" }

            # Provisioning control
            $enableProv    = if ($afs) { "$($afs.enable_provisioning)" } else { "$($f.enable_provisioning)" }
            $stopOnError   = if ($afs) { "$($afs.stop_provisioning_on_error)" } else { "$($f.stop_provisioning_on_error)" }

            # Display protocol
            $disp = $f.display_protocol_settings
            $dispProto        = if ($disp) { "$($disp.default_display_protocol)" } else { "" }
            $allowChooseProto = if ($disp) { "$($disp.allow_users_to_choose_protocol)" } else { "" }
            $sessionCollab    = if ($disp) { "$($disp.session_collaboration_enabled)" } else { "" }
            $gpuEnabled       = if ($disp) { "$($disp.grid_vgpus_enabled)" } else { "" }

            # Session settings
            $sess = $f.session_settings
            $discTimeoutPolicy = ""; $discTimeoutMin = ""
            $emptyTimeoutPolicy = ""; $emptyTimeoutMin = ""
            $preLaunchPolicy = ""; $preLaunchMin = ""
            $logoffAfterTimeout = ""
            if ($sess) {
                $discTimeoutPolicy  = "$($sess.disconnected_session_timeout_policy)"
                $discTimeoutMin     = "$($sess.disconnected_session_timeout_minutes)"
                $emptyTimeoutPolicy = "$($sess.empty_session_timeout_policy)"
                $emptyTimeoutMin    = "$($sess.empty_session_timeout_minutes)"
                $preLaunchPolicy    = "$($sess.pre_launch_session_timeout_policy)"
                $preLaunchMin       = "$($sess.pre_launch_session_timeout_minutes)"
                $logoffAfterTimeout = "$($sess.logoff_after_timeout)"
            }

            # Provisioning status (IC image state, scheduled maintenance)
            $icImageState = ""
            $icOperation  = ""
            $schedMaintNext = ""
            $schedMaintLogoff = ""
            $schedMaintPeriod = ""
            $schedMaintTime   = ""
            if ($afs -and $afs.provisioning_status_data) {
                $psd = $afs.provisioning_status_data
                $icImageState = "$($psd.instant_clone_current_image_state)"
                $icOperation  = "$($psd.instant_clone_operation)"
                if ($psd.instant_clone_scheduled_maintenance_data) {
                    $smd = $psd.instant_clone_scheduled_maintenance_data
                    if ($smd.next_scheduled_time) {
                        try { $schedMaintNext = ([datetime]'1970-01-01T00:00:00Z').AddMilliseconds([long]$smd.next_scheduled_time).ToLocalTime().ToString("yyyy-MM-dd HH:mm") } catch {}
                    }
                    $schedMaintLogoff = "$($smd.logoff_policy)"
                    if ($smd.recurring_maintenance_settings) {
                        $rms = $smd.recurring_maintenance_settings
                        $schedMaintPeriod = "$($rms.maintenance_period)"
                        $schedMaintTime   = "$($rms.start_time)"
                    }
                }
            }

            # Customization
            $adContainer = ""
            $customType  = ""
            $reuseAccounts = ""
            $icDomainAccountId = ""
            $custSettings = if ($afs) { $afs.customization_settings } else { $null }
            if ($custSettings) {
                $adContainer       = "$($custSettings.ad_container_rdn)"
                $customType        = "$($custSettings.customization_type)"
                $reuseAccounts     = "$($custSettings.reuse_pre_existing_accounts)"
                $icDomainAccountId = "$($custSettings.instant_clone_domain_account_id)"
            }

            # OS and other
            $operatingSystem = if ($afs) { "$($afs.operating_system)" } else { "" }
            $maxSessionType  = if ($afs) { "$($afs.max_session_type)" } else { "" }
            $tpsScope        = if ($afs) { "$($afs.transparent_page_sharing_scope)" } else { "" }

            # Storage
            $useVsan = ""
            $useViewAccel = ""
            if ($afs -and $afs.storage_settings) {
                $useVsan      = "$($afs.storage_settings.use_vsan)"
                $useViewAccel = "$($afs.storage_settings.use_view_storage_accelerator)"
            }

            # Timestamps
            $createdAt = ""
            $updatedAt = ""
            if ($f.created_at) {
                try { $createdAt = ([datetime]'1970-01-01T00:00:00Z').AddMilliseconds([long]$f.created_at).ToLocalTime().ToString("yyyy-MM-dd HH:mm") } catch {}
            }
            if ($f.updated_at) {
                try { $updatedAt = ([datetime]'1970-01-01T00:00:00Z').AddMilliseconds([long]$f.updated_at).ToLocalTime().ToString("yyyy-MM-dd HH:mm") } catch {}
            }

            # IC Internal VM chain (cp-template, cp-replica) for AUTOMATED farms
            $cpTemplate = ""; $cpReplica = ""
            if ($viConnected -and $f.type -eq "AUTOMATED") {
                try {
                    $firstServerName = $null
                    foreach ($srvApiVer in @("v4","v3","v2","v1")) {
                        try {
                            $filterJson = '{"type":"Equals","name":"farm_id","value":"' + $f.id + '"}'
                            $serversRaw = Invoke-RestMethod -Uri "$restBase/inventory/$srvApiVer/rds-servers" `
                                -Method Get `
                                -Headers @{ Authorization = "Bearer $restToken"; filter = $filterJson } `
                                -ErrorAction Stop
                            $filtered = @($serversRaw) | Where-Object { $_.farm_id -eq $f.id }
                            if ($filtered.Count -gt 0) {
                                $firstServerName = "$($filtered[0].name)"
                                break
                            }
                        } catch { }
                    }

                    if ($firstServerName) {
                        $poolVm = Get-VM -Name $firstServerName -ErrorAction SilentlyContinue | Select-Object -First 1
                        $machineView = if ($poolVm) {
                            Get-View -Id $poolVm.Id -Property Name,Config.ExtraConfig -ErrorAction SilentlyContinue
                        } else {
                            Get-View -ViewType VirtualMachine -Filter @{"Name" = $firstServerName} `
                                -Property Name,Config.ExtraConfig -ErrorAction SilentlyContinue |
                                Where-Object { $_.Name -eq $firstServerName } | Select-Object -First 1
                        }

                        if ($machineView -and $machineView.Config -and $machineView.Config.ExtraConfig) {
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
                } catch { Write-RunspaceLog "IC chain lookup failed for RDS farm $($f.name): $($_.Exception.Message)" "WARN" }
            }

            [PSCustomObject]@{
                Id                      = "$($f.id)"
                Name                    = "$($f.name)"
                DisplayName             = "$($f.display_name)"
                Type                    = "$($f.type)"
                Source                  = "$($f.source)"
                Enabled                 = "$($f.enabled)"
                GoldenImage             = $goldenImage
                GoldenImagePath         = $goldenImagePath
                Snapshot                = $snapshotName
                HostOrCluster           = $hostOrCluster
                ResourcePool            = $resourcePool
                VmFolder                = $vmFolder
                Datacenter              = $datacenter
                NamingPattern           = $namingPattern
                MaxServers              = $maxServers
                MinReadyVMs             = $minReadyVMs
                EnableProvisioning      = $enableProv
                StopProvisioningOnError = $stopOnError
                DisplayProtocol         = $dispProto
                AllowChooseProtocol     = $allowChooseProto
                SessionCollaboration    = $sessionCollab
                GridVgpusEnabled        = $gpuEnabled
                DiscTimeoutPolicy       = $discTimeoutPolicy
                DiscTimeoutMin          = $discTimeoutMin
                EmptyTimeoutPolicy      = $emptyTimeoutPolicy
                EmptyTimeoutMin         = $emptyTimeoutMin
                PreLaunchPolicy         = $preLaunchPolicy
                PreLaunchMin            = $preLaunchMin
                LogoffAfterTimeout      = $logoffAfterTimeout
                IcImageState            = $icImageState
                IcOperation             = $icOperation
                SchedMaintNext          = $schedMaintNext
                SchedMaintLogoff        = $schedMaintLogoff
                SchedMaintPeriod        = $schedMaintPeriod
                SchedMaintTime          = $schedMaintTime
                AdContainer             = $adContainer
                CustomizationType       = $customType
                ReusePreExistingAccounts = $reuseAccounts
                OperatingSystem         = $operatingSystem
                MaxSessionType          = $maxSessionType
                TpsScope                = $tpsScope
                UseVsan                 = $useVsan
                UseViewAccel            = $useViewAccel
                CpTemplate              = $cpTemplate
                CpReplica               = $cpReplica
                CreatedAt               = $createdAt
                UpdatedAt               = $updatedAt
            }
        }
        return @($result)
    } catch {
        Write-RunspaceLog "WARNING: RDS Farms collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

