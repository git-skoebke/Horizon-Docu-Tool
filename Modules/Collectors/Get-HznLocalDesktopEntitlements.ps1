# =============================================================================
# Get-HznLocalDesktopEntitlements — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznLocalDesktopEntitlements {
    if (-not $restToken) { return @() }
    try {
        # Fetch pool inventory (lightweight — just need id + name)
        $pools = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
            "inventory/v12/desktop-pools","inventory/v11/desktop-pools","inventory/v10/desktop-pools",
            "inventory/v9/desktop-pools","inventory/v8/desktop-pools","inventory/v7/desktop-pools",
            "inventory/v6/desktop-pools","inventory/v5/desktop-pools","inventory/v4/desktop-pools",
            "inventory/v3/desktop-pools"
        )
        if (-not $pools) { return @() }

        # SID resolver
        $resolveSid = {
            param([string]$sid)
            if ([string]::IsNullOrEmpty($sid)) { return $null }
            try {
                $sidObj = New-Object System.Security.Principal.SecurityIdentifier($sid)
                return $sidObj.Translate([System.Security.Principal.NTAccount]).Value
            } catch { return $sid }
        }

        $rows = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Helper: get group member sAMAccountNames recursively
        $getGroupMembers = {
            param([string]$groupDN)
            $memberNames = [System.Collections.Generic.List[string]]::new()
            try {
                $entry = [ADSI]"LDAP://$groupDN"
                $members = $entry.Properties['member']
                if (-not $members) { return $memberNames }
                foreach ($dn in $members) {
                    try {
                        $mEntry = [ADSI]"LDAP://$dn"
                        $objClass = @($mEntry.objectClass)
                        if ($objClass -contains 'user') {
                            $sam = "$($mEntry.sAMAccountName)"
                            if ($sam) { $memberNames.Add($sam) }
                        }
                    } catch {}
                }
            } catch {}
            return $memberNames
        }

        foreach ($p in @($pools)) {
            try {
                $ents = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("entitlements/v1/desktop-pools/$($p.id)")
                if (-not $ents -or -not $ents.ad_user_or_group_ids) { continue }
                foreach ($sid in @($ents.ad_user_or_group_ids)) {
                    $resolvedName = & $resolveSid $sid
                    if (-not $resolvedName) { continue }

                    # Determine if group or user and collect member names
                    $isGroup      = $false
                    $memberCount  = 0
                    $memberNames  = @()
                    try {
                        $domainUser = $resolvedName -split '\\'
                        if ($domainUser.Count -eq 2) {
                            $adObj = ([adsisearcher]"(&(objectCategory=group)(sAMAccountName=$($domainUser[1])))").FindOne()
                            if ($adObj) {
                                $isGroup = $true
                                $groupDN = "$($adObj.Properties['distinguishedname'][0])"
                                $memberNames = @(& $getGroupMembers $groupDN)
                                $memberCount = $memberNames.Count
                            } else {
                                # Not a group - single user
                                $memberCount = 1
                                $memberNames = @($domainUser[1])
                            }
                        }
                    } catch {
                        $memberCount = 0
                    }

                    $rows.Add([PSCustomObject]@{
                        PoolName     = "$($p.name)"
                        Name         = "$resolvedName"
                        IsGroup      = $isGroup
                        MemberCount  = $memberCount
                        MemberNames  = $memberNames
                    })
                }
            } catch {}
        }

        return @($rows)
    } catch {
        Write-RunspaceLog "WARNING: Local Desktop Entitlements collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

