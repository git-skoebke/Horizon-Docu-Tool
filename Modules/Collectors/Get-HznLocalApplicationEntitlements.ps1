# =============================================================================
# Get-HznLocalApplicationEntitlements — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznLocalApplicationEntitlements {
    if (-not $restToken) { return @() }
    try {
        # Fetch application pool inventory (lightweight — just need id + name)
        $appPools = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
            "inventory/v8/application-pools",
            "inventory/v7/application-pools",
            "inventory/v6/application-pools",
            "inventory/v5/application-pools",
            "inventory/v4/application-pools",
            "inventory/v3/application-pools",
            "inventory/v2/application-pools",
            "inventory/v1/application-pools"
        )
        if (-not $appPools) { return @() }

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

        # Helper: get group member sAMAccountNames
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

        foreach ($p in @($appPools)) {
            try {
                $ents = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
                    "entitlements/v1/application-pools/$($p.id)"
                )
                if (-not $ents -or -not $ents.ad_user_or_group_ids) { continue }
                foreach ($sid in @($ents.ad_user_or_group_ids)) {
                    $resolvedName = & $resolveSid $sid
                    if (-not $resolvedName) { continue }

                    $isGroup     = $false
                    $memberCount = 0
                    $memberNames = @()
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
                                $memberCount = 1
                                $memberNames = @($domainUser[1])
                            }
                        }
                    } catch {
                        $memberCount = 0
                    }

                    $rows.Add([PSCustomObject]@{
                        PoolName    = "$($p.name)"
                        Name        = "$resolvedName"
                        IsGroup     = $isGroup
                        MemberCount = $memberCount
                        MemberNames = $memberNames
                    })
                }
            } catch {}
        }

        return @($rows)
    } catch {
        Write-RunspaceLog "WARNING: Local Application Entitlements collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}
