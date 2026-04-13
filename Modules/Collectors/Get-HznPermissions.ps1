# =============================================================================
# Get-HznPermissions — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznPermissions {
    if (-not $restToken) { return @() }
    try {
        $perms = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v2/permissions","config/v1/permissions")
        $roles = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v1/roles")
        if (-not $perms) { return @() }

        # Build role lookup map (id -> display_name)
        $roleMap = @{}
        if ($roles) {
            foreach ($r in @($roles)) {
                if ($r.id) { $roleMap[$r.id] = $r.name }
            }
        }

        # SID -> NTAccount resolver
        $resolveSid = {
            param([string]$sid)
            if ([string]::IsNullOrEmpty($sid)) { return $null }
            try {
                $sidObj = New-Object System.Security.Principal.SecurityIdentifier($sid)
                return $sidObj.Translate([System.Security.Principal.NTAccount]).Value
            } catch { return $sid }
        }

        # Recursively collect direct member sAMAccountNames from a group DN
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
                        } elseif ($objClass -contains 'group') {
                            # Nested group — add display name as a sub-group indicator
                            $subSam = "$($mEntry.sAMAccountName)"
                            if ($subSam) { $memberNames.Add("[Group] $subSam") }
                        }
                    } catch {}
                }
            } catch {}
            return $memberNames
        }

        # Deduplicate: same principal + same role + same access group = duplicate
        # The API may return one entry per Connection Server in a cluster — all with different IDs
        # but identical display_name + role_id + local_access_group_id
        $seen = @{}
        $uniquePerms = foreach ($p in @($perms)) {
            $key = "$($p.display_name)|$($p.role_id)|$($p.local_access_group_id)"
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $p
            }
        }

        return @($uniquePerms) | ForEach-Object {
            $p = $_
            $roleName = if ($p.role_id -and $roleMap[$p.role_id]) { $roleMap[$p.role_id] } else { $p.role_id }

            # Resolve display name from SID if display_name is missing
            $displayName = $p.display_name
            if ([string]::IsNullOrEmpty($displayName) -and $p.sid) {
                $displayName = & $resolveSid $p.sid
            }
            if ([string]::IsNullOrEmpty($displayName)) { $displayName = "(unknown)" }

            # AD member resolution for groups
            $isGroup     = [bool]$p.group
            $memberCount = 0
            $memberNames = @()

            if ($isGroup) {
                try {
                    # Extract sAMAccountName from display_name (format: DOMAIN\GroupName or just GroupName)
                    $parts = $displayName -split '\\'
                    $samName = if ($parts.Count -ge 2) { $parts[-1] } else { $displayName }

                    $searcher = [adsisearcher]"(&(objectCategory=group)(sAMAccountName=$samName))"
                    $found = $searcher.FindOne()
                    if ($found) {
                        $groupDN = "$($found.Properties['distinguishedname'][0])"
                        $memberNames = @(& $getGroupMembers $groupDN)
                        $memberCount = $memberNames.Count
                    }
                } catch {
                    Write-RunspaceLog "WARNING: Could not resolve group members for '$displayName': $($_.Exception.Message)" "WARN"
                }
            } else {
                # Single user counts as 1
                $memberCount = 1
                $parts = $displayName -split '\\'
                $memberNames = @(if ($parts.Count -ge 2) { $parts[-1] } else { $displayName })
            }

            [PSCustomObject]@{
                DisplayName        = $displayName
                IsGroup            = $isGroup
                RoleName           = $roleName
                LocalAccessGroupId = $p.local_access_group_id
                MemberCount        = $memberCount
                MemberNames        = $memberNames
            }
        }
    } catch {
        Write-RunspaceLog "WARNING: Permissions collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}
