# =============================================================================
# Get-HznEventDatabase — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznEventDatabase {
    if (-not $restToken) { return [PSCustomObject]@{ Configured = $false } }
    try {
        $edb = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v1/event-database")
        if (-not $edb -or $edb.event_database_configured -eq $false) {
            return [PSCustomObject]@{ Configured = $false }
        }
        return [PSCustomObject]@{
            Configured    = $true
            Server        = $edb.server_name
            UserName      = $edb.username
            DatabaseName  = $edb.database_name
            Port          = $edb.port
            Type          = $edb.type
            TablePrefix   = $edb.table_prefix
            ShowEventsFor = $edb.show_events_for_time
            NewEventsDays = $edb.classify_events_as_new_for_days
        }
    } catch {
        Write-RunspaceLog "WARNING: Event Database collection failed: $($_.Exception.Message)" "WARN"
        return [PSCustomObject]@{ Configured = $false }
    }
}

# =============================================================================
# NEW REST COLLECTOR FUNCTIONS
# =============================================================================

