# =============================================================================
# Get-HznGlobalEntitlements — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznGlobalEntitlements {
    if (-not $restToken) { return $null }
    try {
        $desktops    = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("inventory/v7/global-desktop-entitlements","inventory/v6/global-desktop-entitlements")
        $apps        = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("inventory/v7/global-application-entitlements","inventory/v6/global-application-entitlements")
        $desktopEnts = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("entitlements/v1/global-desktop-entitlements")
        $appEnts     = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("entitlements/v1/global-application-entitlements")

        # SID → display name (AD lookup; falls back to raw SID on failure)
        $resolveSid = {
            param([string]$sid)
            if ([string]::IsNullOrEmpty($sid)) { return $null }
            try {
                $sidObj = New-Object System.Security.Principal.SecurityIdentifier($sid)
                return $sidObj.Translate([System.Security.Principal.NTAccount]).Value
            } catch { return $sid }
        }

        # Collect direct member sAMAccountNames from an AD group DN (users + nested group names)
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

        # Resolve a single SID to a rich entitlement object with IsGroup / MemberCount / MemberNames
        $resolveEntitlement = {
            param([string]$sid)
            $resolvedName = & $resolveSid $sid
            if (-not $resolvedName) { return $null }

            $isGroup     = $false
            $memberCount = 0
            $memberNames = @()

            try {
                $parts   = $resolvedName -split '\\'
                $samName = if ($parts.Count -ge 2) { $parts[-1] } else { $resolvedName }

                $searcher = [adsisearcher]"(&(objectCategory=group)(sAMAccountName=$samName))"
                $found    = $searcher.FindOne()
                if ($found) {
                    $isGroup     = $true
                    $groupDN     = "$($found.Properties['distinguishedname'][0])"
                    $memberNames = @(& $getGroupMembers $groupDN)
                    $memberCount = $memberNames.Count
                } else {
                    # Direct user
                    $memberCount = 1
                    $memberNames = @($samName)
                }
            } catch {
                $memberCount = 0
            }

            return [PSCustomObject]@{
                Name        = $resolvedName
                IsGroup     = $isGroup
                MemberCount = $memberCount
                MemberNames = $memberNames
            }
        }

        # Build lookup: entitlement id -> list of resolved entitlement objects
        $dMap = @{}
        foreach ($e in @($desktopEnts)) {
            $id = $e.id
            if (-not $id) { continue }
            if (-not $dMap[$id]) { $dMap[$id] = [System.Collections.Generic.List[object]]::new() }
            foreach ($sid in @($e.ad_user_or_group_ids)) {
                $obj = & $resolveEntitlement $sid
                if ($obj) { $dMap[$id].Add($obj) }
            }
        }

        $aMap = @{}
        foreach ($e in @($appEnts)) {
            $id = $e.id
            if (-not $id) { continue }
            if (-not $aMap[$id]) { $aMap[$id] = [System.Collections.Generic.List[object]]::new() }
            foreach ($sid in @($e.ad_user_or_group_ids)) {
                $obj = & $resolveEntitlement $sid
                if ($obj) { $aMap[$id].Add($obj) }
            }
        }

        # Attach resolved entitlement objects to each inventory item
        $desktopList = @($desktops) | ForEach-Object {
            $members = if ($dMap[$_.id]) { @($dMap[$_.id]) } else { @() }
            $_ | Add-Member -NotePropertyName "AD_Members" -NotePropertyValue $members -Force -PassThru
        }
        $appList = @($apps) | ForEach-Object {
            $members = if ($aMap[$_.id]) { @($aMap[$_.id]) } else { @() }
            $_ | Add-Member -NotePropertyName "AD_Members" -NotePropertyValue $members -Force -PassThru
        }

        return [PSCustomObject]@{
            DesktopEntitlements = if ($desktopList) { @($desktopList) } else { @() }
            AppEntitlements     = if ($appList)     { @($appList)     } else { @() }
        }
    } catch {
        Write-RunspaceLog "WARNING: Global Entitlements collection failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}
