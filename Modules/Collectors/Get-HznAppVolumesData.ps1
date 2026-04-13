# =============================================================================
# Get-HznAppVolumesData — App Volumes Manager REST API collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $collectedData.AppVolumesManager (server names), $avUsername, $avPassword
#
# Auth: POST /app_volumes/sessions  — session cookie based, no token
# Logout: DELETE /app_volumes/sessions
# =============================================================================

function Format-AvTimestamp {
    # Strip trailing " +0100" / " +0200" / any " ±HHMM" suffix and return clean local datetime string.
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return "" }
    return ($Value -replace '\s+[+-]\d{4}\s*$','').Trim()
}

function Invoke-AvLogin {
    param([string]$Server, [string]$Username, [string]$Password)
    $uri  = "https://$Server/app_volumes/sessions"
    $body = [ordered]@{ username = $Username; password = $Password } | ConvertTo-Json
    $resp = Invoke-WebRequest -Uri $uri -Method POST -Body $body `
                -ContentType "application/json" `
                -Headers @{ Accept = "application/json" } `
                -SkipCertificateCheck `
                -SessionVariable "avSession" `
                -ErrorAction Stop
    $parsed = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($parsed.success -notmatch '^(ok|Ok|OK)$') { throw "Login rejected: $($resp.Content)" }
    return $avSession
}

function Invoke-AvGet {
    # GET against the /app_volumes/* namespace (documented REST API).
    param(
        [string]$Server,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string]$Path
    )
    return Invoke-RestMethod -Uri "https://$Server/app_volumes/$Path" -Method GET `
               -WebSession $Session `
               -Headers @{ Accept = "application/json" } `
               -SkipCertificateCheck -ErrorAction Stop
}

function Invoke-AvCvGet {
    # GET against the internal /cv_api/* namespace (used by the UI — shares the same cookie session).
    # Returns $null on failure so callers can degrade gracefully.
    param(
        [string]$Server,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [string]$Path
    )
    try {
        return Invoke-RestMethod -Uri "https://$Server/cv_api/$Path" -Method GET `
                   -WebSession $Session `
                   -Headers @{ Accept = "application/json" } `
                   -SkipCertificateCheck -ErrorAction Stop
    } catch {
        Write-RunspaceLog "AppVolumes [$Server]: cv_api/$Path failed — $($_.Exception.Message)" "WARN"
        return $null
    }
}

function Build-AvPermissionMap {
    # Walks a permission_tree (array of nodes with text/children/id) iteratively
    # and returns an id -> "Category > Sub > Leaf" hashtable.
    param($PermissionTree)
    $map = @{}
    if (-not $PermissionTree) { return $map }

    $stack = [System.Collections.Stack]::new()
    foreach ($root in @($PermissionTree)) {
        $stack.Push([PSCustomObject]@{ Node = $root; Path = "" })
    }
    while ($stack.Count -gt 0) {
        $cur     = $stack.Pop()
        $n       = $cur.Node
        $label   = $n.text
        $newPath = if ($cur.Path) { "$($cur.Path) > $label" } else { $label }

        if ($null -ne $n.id) {
            $map[[int]$n.id] = $newPath
        }
        if ($n.children -and $n.children -is [System.Collections.IEnumerable] -and $n.children -isnot [string]) {
            foreach ($child in $n.children) {
                $stack.Push([PSCustomObject]@{ Node = $child; Path = $newPath })
            }
        }
    }
    return $map
}

function Resolve-AvPermissionIds {
    # Map a list of permission IDs to sorted human-readable labels using a pre-built map.
    param([hashtable]$Map, $Ids)
    if (-not $Map -or $Map.Count -eq 0 -or -not $Ids) { return @() }
    $labels = foreach ($id in $Ids) {
        if ($Map.ContainsKey([int]$id)) { $Map[[int]$id] } else { "#$id" }
    }
    return ($labels | Sort-Object -Unique)
}

function Invoke-AvLogout {
    param([string]$Server, [Microsoft.PowerShell.Commands.WebRequestSession]$Session)
    try {
        Invoke-RestMethod -Uri "https://$Server/app_volumes/sessions" -Method DELETE `
            -WebSession $Session -SkipCertificateCheck -ErrorAction SilentlyContinue | Out-Null
    } catch { }
}

function Get-AvAssignmentEntities {
    # Fetch /app_assignments/{id}/entities and flatten into display rows.
    param(
        [string]$Server,
        [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
        [int]$AssignmentId
    )
    try {
        $raw  = Invoke-AvGet -Server $Server -Session $Session -Path "app_assignments/$AssignmentId/entities"
        $list = if ($raw.data) { @($raw.data) } elseif ($raw -is [array]) { @($raw) } else { @($raw) }
        return $list | ForEach-Object {
            $t = $_.target
            $name = if ($t.upn) { $t.upn } elseif ($t.name) { $t.name } else { $t.account_name }
            [PSCustomObject]@{
                EntityName        = $name
                EntityType        = $_.target_type
                DistinguishedName = $t.distinguished_name
                AssignedAt        = (Format-AvTimestamp $_.created_at)
            }
        }
    } catch {
        Write-RunspaceLog "AppVolumes [$Server]: app_assignments/$AssignmentId/entities failed — $($_.Exception.Message)" "WARN"
        return @()
    }
}

function Get-HznAppVolumesData {
    param([string]$AvUsername, [string]$AvPassword)

    if ([string]::IsNullOrEmpty($AvUsername) -or [string]::IsNullOrEmpty($AvPassword)) {
        Write-RunspaceLog "AppVolumes: no credentials provided — skipping" "INFO"
        return @()
    }
    $managers = @($collectedData["AppVolumesManager"])
    if ($managers.Count -eq 0) {
        Write-RunspaceLog "AppVolumes: no App Volumes Manager in Horizon config — skipping" "INFO"
        return @()
    }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($mgr in $managers) {
        $server = $mgr.ServerName
        if ([string]::IsNullOrEmpty($server)) { continue }

        Write-RunspaceLog "AppVolumes: connecting to $server" "INFO"
        $session = $null
        try {
            $session = Invoke-AvLogin -Server $server -Username $AvUsername -Password $AvPassword
            Write-RunspaceLog "AppVolumes: authenticated $server" "INFO"
        } catch {
            $httpStatus = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "?" }
            $detail     = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
            Write-RunspaceLog "AppVolumes: login failed for $server — HTTP ${httpStatus}: $detail" "WARN"
            $results.Add([PSCustomObject]@{
                Server            = $server
                LoginFailed       = $true
                Version           = $null
                AppProducts       = @()
                Assignments       = @()
                Writables         = @()
                License           = $null
                LicenseUsage      = @()
                LdapDomains       = @()
                AdminRoles        = @()
                AdminAssignments  = @()
                StorageDefaults   = $null
                StorageDatastores = @()
                Storages          = @()
                FileShares        = @()
                MachineManagers   = @()
                ManagerServices   = @()
                Settings          = @()
            })
            continue
        }

        $version     = $null
        $appProducts = @()
        $assignments = @()
        $writables   = @()

        # ── Version ─────────────────────────────────────────────────────────
        try {
            $raw = Invoke-AvGet -Server $server -Session $session -Path "version"
            $version = $raw
        } catch {
            Write-RunspaceLog "AppVolumes [$server]: /version failed — $($_.Exception.Message)" "WARN"
        }

        # ── App Products (packages are embedded, assignments fetched per product) ─
        try {
            $raw  = Invoke-AvGet -Server $server -Session $session -Path "app_products"
            $list = if ($raw.data) { @($raw.data) } elseif ($raw -is [array]) { @($raw) } else { @($raw) }
            Write-RunspaceLog "AppVolumes [$server]: app_products: $($list.Count)" "INFO"

            $appProducts = foreach ($prod in $list) {
                $prodId   = $prod.id
                $packages = @()
                $prodAssignments = @()

                # Packages are embedded in app_products.data[].app_packages — no extra request needed.
                if ($prod.app_packages) {
                    $packages = @($prod.app_packages) | ForEach-Object {
                        [PSCustomObject]@{
                            Name         = $_.name
                            Version      = $_.version
                            Status       = $_.status
                            AgentVersion = $_.agent_version
                            OS           = $_.primordial_os_name
                            SizeMb       = $_.size_mb
                            Delivery     = $_.display_delivery
                            Created      = (Format-AvTimestamp $_.created_at)
                            Updated      = (Format-AvTimestamp $_.updated_at)
                        }
                    }
                }

                # Assignments per product — then resolve entities for each assignment
                try {
                    $asnRaw  = Invoke-AvGet -Server $server -Session $session -Path "app_products/$prodId/assignments"
                    $asnList = if ($asnRaw.data) { @($asnRaw.data) } elseif ($asnRaw -is [array]) { @($asnRaw) } else { @($asnRaw) }
                    $prodAssignments = foreach ($asn in $asnList) {
                        $entities = Get-AvAssignmentEntities -Server $server -Session $session -AssignmentId $asn.id
                        if (-not $entities -or $entities.Count -eq 0) {
                            # Still emit a placeholder so the row is visible
                            [PSCustomObject]@{
                                AssignmentId      = $asn.id
                                EntityName        = "(no entity)"
                                EntityType        = ""
                                DistinguishedName = ""
                                PackageName       = $asn.app_package_name
                                MarkerName        = $asn.app_marker_name
                                AssignedAt        = (Format-AvTimestamp $asn.created_at)
                            }
                        } else {
                            foreach ($e in $entities) {
                                [PSCustomObject]@{
                                    AssignmentId      = $asn.id
                                    EntityName        = $e.EntityName
                                    EntityType        = $e.EntityType
                                    DistinguishedName = $e.DistinguishedName
                                    PackageName       = $asn.app_package_name
                                    MarkerName        = $asn.app_marker_name
                                    AssignedAt        = (Format-AvTimestamp $asn.created_at)
                                }
                            }
                        }
                    }
                } catch {
                    Write-RunspaceLog "AppVolumes [$server]: app_products/$prodId/assignments failed — $($_.Exception.Message)" "WARN"
                }

                [PSCustomObject]@{
                    Id          = $prodId
                    Name        = $prod.name
                    Description = $prod.description
                    Status      = $prod.status
                    Updated     = (Format-AvTimestamp $prod.updated_at)
                    Packages    = @($packages)
                    Assignments = @($prodAssignments)
                }
            }
        } catch {
            Write-RunspaceLog "AppVolumes [$server]: /app_products failed — $($_.Exception.Message)" "WARN"
        }

        # ── All Assignments (flattened across all products, with entity resolution) ─
        try {
            $raw  = Invoke-AvGet -Server $server -Session $session -Path "app_assignments"
            $list = if ($raw.data) { @($raw.data) } elseif ($raw -is [array]) { @($raw) } else { @($raw) }

            # Build product id → name lookup so we can fill in product name missing from /app_assignments
            $productLookup = @{}
            foreach ($p in $appProducts) { $productLookup[[int]$p.Id] = $p.Name }

            $assignments = foreach ($asn in $list) {
                $pname = if ($asn.app_product_name) { $asn.app_product_name }
                         elseif ($productLookup.ContainsKey([int]$asn.app_product_id)) { $productLookup[[int]$asn.app_product_id] }
                         else { "" }
                $entities = Get-AvAssignmentEntities -Server $server -Session $session -AssignmentId $asn.id
                if (-not $entities -or $entities.Count -eq 0) {
                    [PSCustomObject]@{
                        EntityName        = "(no entity)"
                        EntityType        = ""
                        DistinguishedName = ""
                        ProductName       = $pname
                        AssignedAt        = (Format-AvTimestamp $asn.created_at)
                    }
                } else {
                    foreach ($e in $entities) {
                        [PSCustomObject]@{
                            EntityName        = $e.EntityName
                            EntityType        = $e.EntityType
                            DistinguishedName = $e.DistinguishedName
                            ProductName       = $pname
                            AssignedAt        = (Format-AvTimestamp $asn.created_at)
                        }
                    }
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: app_assignments: $(@($assignments).Count)" "INFO"
        } catch {
            Write-RunspaceLog "AppVolumes [$server]: /app_assignments failed — $($_.Exception.Message)" "WARN"
        }

        # ── Writables ───────────────────────────────────────────────────────
        try {
            $raw  = Invoke-AvGet -Server $server -Session $session -Path "writables"
            $list = if ($raw.data) { @($raw.data) } elseif ($raw -is [array]) { @($raw) } else { @($raw) }
            $writables = $list | ForEach-Object {
                [PSCustomObject]@{
                    Name       = $_.name
                    Owner      = $_.owner_name
                    OwnerType  = $_.owner_type
                    Status     = $_.status
                    Datastore  = $_.datastore
                    Size       = $_.size_mb
                    Created    = (Format-AvTimestamp $_.created_at)
                    Updated    = (Format-AvTimestamp $_.updated_at)
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: writables: $(@($writables).Count)" "INFO"
        } catch {
            Write-RunspaceLog "AppVolumes [$server]: /writables failed — $($_.Exception.Message)" "WARN"
        }

        # ── License (cv_api) ────────────────────────────────────────────────
        $license = $null
        $raw = Invoke-AvCvGet -Server $server -Session $session -Path "license"
        if ($raw -and $raw.license) {
            $l = $raw.license
            $features = @()
            if ($l.ft) {
                $features = foreach ($p in $l.ft.PSObject.Properties) {
                    [PSCustomObject]@{ Name = $p.Name; Enabled = ($p.Value -eq "true") }
                }
            }
            $details = @()
            if ($l.details) {
                $details = foreach ($p in $l.details.PSObject.Properties) {
                    if ($p.Name -eq "Name") { continue }
                    [PSCustomObject]@{ Key = $p.Name; Value = ($p.Value -as [string]) }
                }
            }
            $license = [PSCustomObject]@{
                Name     = $l.details.Name
                Invalid  = ($l.invalid -eq "true")
                Filename = $l.filename
                Details  = @($details)
                Features = @($features)
            }
            Write-RunspaceLog "AppVolumes [$server]: license: $($l.details.Name)" "INFO"
        }

        # ── License usage ───────────────────────────────────────────────────
        $licenseUsage = @()
        $raw = Invoke-AvCvGet -Server $server -Session $session -Path "license_usage"
        if ($raw -and $raw.licenses) {
            $licenseUsage = foreach ($u in $raw.licenses) {
                [PSCustomObject]@{
                    Label = ($u.label -replace ':\s*$','')
                    Used  = $u.num
                    Cap   = $u.cap
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: license_usage: $(@($licenseUsage).Count)" "INFO"
        }

        # ── LDAP Domains ────────────────────────────────────────────────────
        $ldapDomains = @()
        $raw = Invoke-AvCvGet -Server $server -Session $session -Path "ldap_domains"
        if ($raw -and $raw.ldap_domains) {
            $ldapDomains = foreach ($d in $raw.ldap_domains) {
                [PSCustomObject]@{
                    Domain       = $d.domain
                    NetBIOS      = $d.netbios
                    Host         = $d.host
                    Hosts        = $d.hosts
                    Base         = $d.base
                    Username     = $d.username
                    Ldaps        = $d.ldaps
                    LdapTls      = $d.ldap_tls
                    SslVerify    = $d.ssl_verify
                    Port         = if ($d.effective_port) { $d.effective_port } else { $d.port }
                    Created      = (Format-AvTimestamp $d.created_at)
                    Updated      = (Format-AvTimestamp $d.updated_at)
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: ldap_domains: $(@($ldapDomains).Count)" "INFO"
        }

        # ── Admin Roles: definitions (/roles) with resolved permissions + assignments (/group_permissions) ─
        $adminRoles       = @()
        $adminAssignments = @()
        $permTreeRaw = Invoke-AvCvGet -Server $server -Session $session -Path "permissions/permission_tree"
        # permission_tree may come wrapped or as bare array
        $permTree = if ($permTreeRaw -is [array]) { $permTreeRaw } elseif ($permTreeRaw.data) { $permTreeRaw.data } else { $permTreeRaw }
        $permMap  = Build-AvPermissionMap -PermissionTree $permTree

        $raw = Invoke-AvCvGet -Server $server -Session $session -Path "roles"
        if ($raw -and $raw.roles) {
            $adminRoles = foreach ($r in $raw.roles) {
                $permLabels = Resolve-AvPermissionIds -Map $permMap -Ids @($r.permission_ids)
                [PSCustomObject]@{
                    Name        = $r.name
                    Description = $r.description
                    Type        = $r.type
                    Predefined  = $r.is_predefined
                    Permissions = @($permLabels)
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: roles: $(@($adminRoles).Count)" "INFO"
        }

        $raw = Invoke-AvCvGet -Server $server -Session $session -Path "group_permissions"
        if ($raw -and $raw.group_permissions) {
            $adminAssignments = foreach ($g in $raw.group_permissions) {
                [PSCustomObject]@{
                    Role              = $g.display_role
                    AssigneeName      = $g.assignee_name
                    AssigneeType      = $g.assignee_type
                    DistinguishedName = $g.assignee_dn
                    Created           = (Format-AvTimestamp $g.created_at)
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: group_permissions: $(@($adminAssignments).Count)" "INFO"
        }

        # ── Storage: defaults + datastores (/datastores) + storages (/storages) + file shares ─
        $storageDefaults = $null
        $storageDatastores = @()
        # Strip the "<name>|<host>|" uniq_string separator that the UI uses internally.
        $cleanUniq = { param($s) if ($null -eq $s) { "" } else { ($s -as [string]) -replace '\|\|$','' -replace '\|$','' } }
        $raw = Invoke-AvCvGet -Server $server -Session $session -Path "datastores"
        if ($raw) {
            $storageDefaults = [PSCustomObject]@{
                WritableStorage                 = (& $cleanUniq $raw.writable_storage)
                AppstackStorage                 = (& $cleanUniq $raw.appstack_storage)
                PackageStorage                  = (& $cleanUniq $raw.package_storage)
                DataDiskStorage                 = (& $cleanUniq $raw.data_disk_storage)
                WritableBackupRecurrent         = (& $cleanUniq $raw.writable_backup_recurrent_datastore)
                DataDiskBackupRecurrent         = (& $cleanUniq $raw.data_disk_backup_recurrent_datastore)
                AppstackPath                    = $raw.appstack_path
                WritablePath                    = $raw.writable_path
                PackagePath                     = $raw.package_path
                DataDiskPath                    = $raw.data_disk_path
                WritableArchivePath             = $raw.writable_archive_path
                WritableBackupRecurrentPath     = $raw.writable_backup_recurrent_path
                DataDiskArchivePath             = $raw.data_disk_archive_path
                DataDiskBackupRecurrentPath     = $raw.data_disk_backup_recurrent_path
                AppstackTemplatePath            = $raw.appstack_template_path
                WritableTemplatePath            = $raw.writable_template_path
                PackageTemplatePath             = $raw.package_template_path
                DataDiskTemplatePath            = $raw.data_disk_template_path
            }
            if ($raw.datastores) {
                $storageDatastores = foreach ($d in $raw.datastores) {
                    [PSCustomObject]@{
                        Name        = $d.display_name
                        Category    = $d.category
                        Description = $d.description
                        Accessible  = $d.accessible
                        Datacenter  = $d.datacenter
                        Capacity    = [int64]([double]$d.capacity)
                        FreeSpace   = [int64]([double]$d.free_space)
                    }
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: datastores: $(@($storageDatastores).Count)" "INFO"
        }

        $storages = @()
        $raw = Invoke-AvCvGet -Server $server -Session $session -Path "storages"
        if ($raw -and $raw.storages) {
            $storages = foreach ($s in $raw.storages) {
                [PSCustomObject]@{
                    Name               = $s.name
                    Host               = $s.host
                    Status             = $s.status
                    Attachable         = $s.attachable
                    ReadOnly           = $s.read_only
                    SpaceUsedBytes     = [int64]$s.actual_space_used
                    SpaceTotalBytes    = [int64]([double]$s.actual_space_total)
                    SpaceUsedDisplay   = $s.space_used
                    SpaceTotalDisplay  = $s.space_total
                    NumPackages        = $s.num_packages
                    NumAppStacks       = $s.num_appstacks
                    NumCombinedStacks  = $s.num_combined_appstacks
                    NumWritables       = $s.num_writables
                    Created            = (Format-AvTimestamp $s.created_at)
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: storages: $(@($storages).Count)" "INFO"
        }

        $fileShares = @()
        $raw = Invoke-AvCvGet -Server $server -Session $session -Path "file_shares"
        if ($raw -and $raw.file_shares) {
            $fileShares = foreach ($f in $raw.file_shares) {
                [PSCustomObject]@{
                    Name     = $f.name
                    Computer = $f.computer
                    Unc      = $f.unc
                    Added    = (Format-AvTimestamp $f.added)
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: file_shares: $(@($fileShares).Count)" "INFO"
        }

        # ── Machine Managers (vSphere/Horizon integrations) ─────────────────
        $machineManagers = @()
        $raw = Invoke-AvCvGet -Server $server -Session $session -Path "machine_managers"
        if ($raw -and $raw.machine_managers) {
            $machineManagers = foreach ($m in $raw.machine_managers) {
                [PSCustomObject]@{
                    Name       = $m.name
                    Host       = $m.host
                    Username   = $m.username
                    Type       = $m.type
                    AdapterType= $m.adapter_type
                    Datacenter = $m.datacenter
                    Status     = $m.status
                    Created    = (Format-AvTimestamp $m.created_at)
                    Updated    = (Format-AvTimestamp $m.updated_at)
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: machine_managers: $(@($machineManagers).Count)" "INFO"
        }

        # ── Manager services (App Volumes Manager server instances) ─────────
        $managerServices = @()
        $raw = Invoke-AvCvGet -Server $server -Session $session -Path "manager_services"
        if ($raw -and $raw.services) {
            $managerServices = foreach ($m in $raw.services) {
                [PSCustomObject]@{
                    Name             = $m.name
                    Fqdn             = $m.fqdn
                    ProductVersion   = $m.product_version
                    InternalVersion  = $m.internal_version
                    DomainName       = $m.domain_name
                    ComputerName     = $m.computer_name
                    UserName         = $m.user_name
                    Registered       = $m.registered
                    Secure           = $m.secure
                    Status           = $m.status
                    LogLevel         = $m.log_level
                    FirstSeen        = (Format-AvTimestamp $m.first_seen_at)
                    LastSeen         = (Format-AvTimestamp $m.last_seen_at)
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: manager_services: $(@($managerServices).Count)" "INFO"
        }

        # ── Settings (flat key/value list, grouped by wrapper type) ─────────
        # /cv_api/settings returns data[] where each item is a hash with one wrapper key
        # (feature|setting|advanced_setting|bot_configuration|rbac_setting|hash). We use
        # -AsHashtable on the raw body so we can enumerate the dynamic wrapper key.
        $settings = @()
        # Sensitive keys we never want to expose in documentation:
        $sensitiveKeys = @('encryption_signature')
        try {
            $rawResp = Invoke-WebRequest -Uri "https://$server/cv_api/settings" `
                         -WebSession $session `
                         -Headers @{ Accept = "application/json" } `
                         -SkipCertificateCheck -ErrorAction Stop
            $parsed = $rawResp.Content | ConvertFrom-Json -AsHashtable
            if ($parsed.data) {
                $settings = foreach ($item in $parsed.data) {
                    $wrapper = @($item.Keys)[0]
                    $inner   = $item[$wrapper]
                    $key     = $inner.key
                    if (-not $key) { continue }
                    $val     = $inner.value
                    if ($key -in $sensitiveKeys) { $val = "(redacted)" }
                    # changed_at is parsed as [datetime] by -AsHashtable — format directly for consistency.
                    $changedStr = if ($inner.changed_at -is [datetime]) {
                        $inner.changed_at.ToString('yyyy-MM-dd HH:mm:ss')
                    } else {
                        Format-AvTimestamp (($inner.changed_at -as [string]) -replace 'T',' ' -replace 'Z','')
                    }
                    [PSCustomObject]@{
                        Type      = $wrapper
                        Key       = $key
                        Label     = $inner.key_i18n
                        Value     = ($val -as [string])
                        InputType = $inner.input_type
                        Changed   = $changedStr
                    }
                }
            }
            Write-RunspaceLog "AppVolumes [$server]: settings: $(@($settings).Count)" "INFO"
        } catch {
            Write-RunspaceLog "AppVolumes [$server]: /cv_api/settings failed — $($_.Exception.Message)" "WARN"
        }

        Invoke-AvLogout -Server $server -Session $session
        Write-RunspaceLog "AppVolumes: completed $server" "INFO"

        $results.Add([PSCustomObject]@{
            Server            = $server
            LoginFailed       = $false
            Version           = $version
            AppProducts       = @($appProducts)
            Assignments       = @($assignments)
            Writables         = @($writables)
            License           = $license
            LicenseUsage      = @($licenseUsage)
            LdapDomains       = @($ldapDomains)
            AdminRoles        = @($adminRoles)
            AdminAssignments  = @($adminAssignments)
            StorageDefaults   = $storageDefaults
            StorageDatastores = @($storageDatastores)
            Storages          = @($storages)
            FileShares        = @($fileShares)
            MachineManagers   = @($machineManagers)
            ManagerServices   = @($managerServices)
            Settings          = @($settings)
        })
    }

    return $results.ToArray()
}
