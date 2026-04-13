# =============================================================================
# Get-HznSyslog — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznSyslog {
    if (-not $restToken) { return $null }
    try {
        $s = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v1/syslog")
        if (-not $s) { return $null }
        return [PSCustomObject]@{
            SyslogServerAddresses = if ($s.syslog_server_addresses) { @($s.syslog_server_addresses) } else { @() }
            FileData              = $s.file_data
        }
    } catch {
        Write-RunspaceLog "WARNING: Syslog collection failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}

