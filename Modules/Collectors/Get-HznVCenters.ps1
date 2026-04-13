# =============================================================================
# Get-HznVCenters — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznVCenters {
    if (-not $restToken) { return @() }
    try {
        $raw = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
            "config/v6/virtual-centers","config/v5/virtual-centers",
            "config/v4/virtual-centers","config/v3/virtual-centers"
        )
        if (-not $raw) { return @() }
        $result = @($raw | ForEach-Object {
            $vc = $_
            $cbrcEnabled  = $null
            $cbrcCacheMB  = $null
            if ($vc.storage_accelerator_data) {
                $cbrcEnabled = $vc.storage_accelerator_data.enabled
                $cbrcCacheMB = $vc.storage_accelerator_data.default_cache_size_mb
            }
            [PSCustomObject]@{
                Name            = $vc.server_name
                Version         = $vc.version
                UserName        = $vc.user_name
                Enabled         = $vc.enabled
                Port            = $vc.port
                DeploymentType  = $vc.deployment_type
                MaintenanceMode = $vc.maintenance_mode
                CbrcEnabled     = $cbrcEnabled
                CbrcCacheSizeMB = $cbrcCacheMB
                # Counts populated from VCenterHealth_Internal step
                ClusterCount    = 0
                HostCount       = 0
                DatastoreCount  = 0
                # PowerCLI-enriched fields
                Build           = ""
                SecurityRole    = ""
                RolePrivileges  = @()
            }
        })

        # Enrich with PowerCLI data (version/build + security role)
        if ($viConnected) {
            $viServer = $global:DefaultVIServer
            if ($viServer) {
                foreach ($vcObj in $result) {
                    if ($vcObj.Name -eq $viServer.Name) {
                        $vcObj.Build = "$($viServer.Build)"
                    }
                }
            }

            # Security role for the Horizon vCenter service account.
            # Strategy: extract the sAMAccountName from the stored username, find the
            # exact Principal string via a wildcard search across all permissions, then
            # use that exact string for the -Principal lookup to get the role.
            try {
                # Fetch all permissions once and log what we see for diagnostics
                $allPerms = Get-VIPermission -ErrorAction SilentlyContinue
                $allPrincipals = @($allPerms | Select-Object -ExpandProperty Principal)
                Write-RunspaceLog "INFO: VIPermission principals found ($($allPrincipals.Count))" "INFO"

                foreach ($vcObj in $result) {
                    if (-not $vcObj.UserName) { continue }

                    # Extract sAMAccountName from any format:
                    #   user@domain.fqdn  -> user
                    #   DOMAIN\user       -> user
                    #   user              -> user
                    $samPart = if ($vcObj.UserName -match '^([^@\\]+)@') {
                        $Matches[1]
                    } elseif ($vcObj.UserName -match '^[^\\]+\\(.+)$') {
                        $Matches[1]
                    } else {
                        $vcObj.UserName
                    }
                    Write-RunspaceLog "INFO: VIPermission search for '$($vcObj.UserName)' -> samPart='$samPart'" "INFO"

                    # Find the exact Principal string vCenter uses for this account
                    $exactPrincipal = $allPrincipals |
                        Select-String -Pattern $samPart -SimpleMatch |
                        Select-Object -First 1 -ExpandProperty Line

                    if ($exactPrincipal) {
                        Write-RunspaceLog "INFO: VIPermission matched principal '$exactPrincipal'" "INFO"
                        $perm = $allPerms | Where-Object { $_.Principal -eq $exactPrincipal } |
                            Select-Object -First 1
                        if ($perm) {
                            $roleName = $perm.Role
                            $vcObj.SecurityRole = "$roleName"
                            $role = Get-VIRole -Name $roleName -ErrorAction SilentlyContinue
                            if ($role) {
                                $vcObj.RolePrivileges = @($role.PrivilegeList)
                            }
                        } else {
                            Write-RunspaceLog "WARNING: Get-VIPermission -Principal '$exactPrincipal' returned nothing" "WARN"
                        }
                    } else {
                        Write-RunspaceLog "WARNING: No VIPermission principal found matching '$samPart' in: $($allPrincipals -join ' | ')" "WARN"
                    }
                }
            } catch {
                Write-RunspaceLog "WARNING: VIPermission lookup failed: $($_.Exception.Message)" "WARN"
            }
        }

        return $result
    } catch {
        Write-RunspaceLog "WARNING: vCenter collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

