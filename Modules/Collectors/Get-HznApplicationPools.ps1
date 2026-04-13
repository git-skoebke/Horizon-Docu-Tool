# =============================================================================
# Get-HznApplicationPools — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznApplicationPools {
    if (-not $restToken) { return @() }
    try {
        # Build farm name lookup
        $farmRaw = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
            "inventory/v9/farms","inventory/v8/farms","inventory/v7/farms","inventory/v6/farms",
            "inventory/v5/farms","inventory/v4/farms","inventory/v3/farms"
        )
        $farmMap = @{}
        if ($farmRaw) { foreach ($f in @($farmRaw)) { $farmMap["$($f.id)"] = "$($f.name)" } }

        # Fetch application pools — prefer v8 for richer fields
        $apps = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
            "inventory/v8/application-pools",
            "inventory/v7/application-pools",
            "inventory/v6/application-pools",
            "inventory/v5/application-pools",
            "inventory/v4/application-pools",
            "inventory/v3/application-pools",
            "inventory/v2/application-pools",
            "inventory/v1/application-pools"
        )
        if (-not $apps) { return @() }

        # SID resolver closure
        $resolveSid = {
            param([string]$sid)
            if ([string]::IsNullOrEmpty($sid)) { return $null }
            try {
                $sidObj = New-Object System.Security.Principal.SecurityIdentifier($sid)
                return $sidObj.Translate([System.Security.Principal.NTAccount]).Value
            } catch { return $sid }
        }

        # AD group member resolver (same pattern as LocalDesktopEntitlements / Permissions)
        $getGroupMembers = {
            param([string]$groupDN)
            $memberNames = [System.Collections.Generic.List[string]]::new()
            try {
                $entry   = [ADSI]"LDAP://$groupDN"
                $members = $entry.Properties['member']
                if (-not $members) { return $memberNames }
                foreach ($dn in $members) {
                    try {
                        $mEntry   = [ADSI]"LDAP://$dn"
                        $objClass = @($mEntry.objectClass)
                        if ($objClass -contains 'user') {
                            $sam = "$($mEntry.sAMAccountName)"
                            if ($sam) { $memberNames.Add($sam) }
                        } elseif ($objClass -contains 'group') {
                            $subSam = "$($mEntry.sAMAccountName)"
                            if ($subSam) { $memberNames.Add("[Group] $subSam") }
                        }
                    } catch {}
                }
            } catch {}
            return $memberNames
        }

        $result = foreach ($a in @($apps)) {
            $farmId   = "$($a.farm_id)"
            $farmName = if ($farmMap[$farmId]) { $farmMap[$farmId] } else { $farmId }

            # ---------- v8 extended fields ----------
            $execPath     = "$($a.executable_path)"
            $prelaunch    = if ($null -ne $a.enable_pre_launch)         { "$($a.enable_pre_launch)"         } else { "" }
            $clientRestr  = if ($null -ne $a.enable_client_restriction) { "$($a.enable_client_restriction)" } else { "" }
            $appStatus    = "$($a.status)"
            $chooseMach   = if ($null -ne $a.allow_users_to_choose_machines) { "$($a.allow_users_to_choose_machines)" } else { "" }

            # ---------- Entitlements ----------
            $entitlements = [System.Collections.Generic.List[PSCustomObject]]::new()
            try {
                $ents = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
                    "entitlements/v1/application-pools/$($a.id)"
                )
                if ($ents -and $ents.ad_user_or_group_ids) {
                    foreach ($sid in @($ents.ad_user_or_group_ids)) {
                        $resolvedName = & $resolveSid $sid
                        if (-not $resolvedName) { continue }

                        $isGroup     = $false
                        $memberCount = 0
                        $memberNames = @()
                        try {
                            $parts   = $resolvedName -split '\\'
                            $samName = if ($parts.Count -ge 2) { $parts[-1] } else { $resolvedName }
                            $adObj   = ([adsisearcher]"(&(objectCategory=group)(sAMAccountName=$samName))").FindOne()
                            if ($adObj) {
                                $isGroup  = $true
                                $groupDN  = "$($adObj.Properties['distinguishedname'][0])"
                                $memberNames = @(& $getGroupMembers $groupDN)
                                $memberCount = $memberNames.Count
                            } else {
                                $memberCount = 1
                                $memberNames = @($samName)
                            }
                        } catch {}

                        $entitlements.Add([PSCustomObject]@{
                            Name        = $resolvedName
                            IsGroup     = $isGroup
                            MemberCount = $memberCount
                            MemberNames = $memberNames
                        })
                    }
                }
            } catch {
                Write-RunspaceLog "WARNING: App pool entitlements failed for '$($a.name)': $($_.Exception.Message)" "WARN"
            }

            [PSCustomObject]@{
                Id                    = "$($a.id)"
                Name                  = "$($a.name)"
                DisplayName           = "$($a.display_name)"
                Enabled               = "$($a.enabled)"
                FarmName              = $farmName
                ExecutablePath        = $execPath
                EnablePreLaunch       = $prelaunch
                EnableClientRestr     = $clientRestr
                AppStatus             = $appStatus
                AllowChooseMachines   = $chooseMach
                Publisher             = "$($a.publisher)"
                Version               = "$($a.version)"
                Entitlements          = $entitlements
            }
        }
        return @($result)
    } catch {
        Write-RunspaceLog "WARNING: Application Pools collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}
