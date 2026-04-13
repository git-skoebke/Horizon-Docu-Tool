# =============================================================================
# Get-HznCpa — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznCpa {
    if (-not $restToken) { return $null }
    try {
        $cpa       = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("federation/v2/cpa")
        $sites     = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("federation/v2/sites")
        $pods      = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("federation/v1/pods")
        $homeSites = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("federation/v2/home-sites")

        # Site lookup map: id → name (from /federation/v2/sites)
        $siteMap = @{}
        if ($sites) { foreach ($s in @($sites)) { $siteMap[$s.id] = $s.name } }

        # CPA.sites is an array of site IDs — resolve each to name
        $cpaSiteNames = if ($cpa -and $cpa.sites) {
            @($cpa.sites) | ForEach-Object { if ($siteMap[$_]) { $siteMap[$_] } else { $_ } }
        } else { @() }

        # Map CPA object to correct fields from actual API response
        $cpaInfo = if ($cpa) {
            [PSCustomObject]@{
                Name                      = $cpa.name
                Guid                      = $cpa.guid
                LocalCsStatus             = $cpa.local_connection_server_status
                SiteNames                 = $cpaSiteNames
                ConnectionServerStatuses  = if ($cpa.connection_server_statuses) { @($cpa.connection_server_statuses) } else { @() }
                SiteRedirectionEnabled    = if ($cpa.site_redirection_settings) { $cpa.site_redirection_settings.site_redirection_enabled } else { $null }
                SiteRedirectionWithoutSso = if ($cpa.site_redirection_settings) { $cpa.site_redirection_settings.site_redirection_enabled_without_sso } else { $null }
            }
        } else { $null }

        $sitesMapped = if ($sites) {
            @($sites) | ForEach-Object { [PSCustomObject]@{ Name = $_.name; Description = $_.description } }
        } else { @() }

        $podsMapped = if ($pods) {
            @($pods) | ForEach-Object {
                [PSCustomObject]@{
                    Name        = $_.name
                    SiteName    = if ($_.site_id -and $siteMap[$_.site_id]) { $siteMap[$_.site_id] } else { $_.site_id }
                    EndpointUrl = $_.endpoint_url
                    Local       = $_.local
                }
            }
        } else { @() }

        $homeSitesMapped = if ($homeSites) {
            @($homeSites) | ForEach-Object {
                [PSCustomObject]@{
                    SiteName      = if ($_.site_id -and $siteMap[$_.site_id]) { $siteMap[$_.site_id] } else { $_.site_id }
                    UserGroupName = if ($_.user_group) { $_.user_group.display_name } else { "" }
                    Override      = $_.override_home_site
                }
            }
        } else { @() }

        return [PSCustomObject]@{
            CpaInfo   = $cpaInfo
            Sites     = $sitesMapped
            Pods      = $podsMapped
            HomeSites = $homeSitesMapped
        }
    } catch {
        Write-RunspaceLog "WARNING: CPA collection failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}

