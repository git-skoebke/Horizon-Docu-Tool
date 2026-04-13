# =============================================================================
# Render-Syslog — New-HtmlSyslogSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlSyslogSection {
    param($Syslog)
    if ($null -eq $Syslog) {
        return ""
    }
    $servers = if ($Syslog.SyslogServerAddresses -and $Syslog.SyslogServerAddresses.Count -gt 0) {
        ($Syslog.SyslogServerAddresses | ForEach-Object { Invoke-HtmlEncode $_ }) -join "<br>"
    } else { "None configured" }
    $fileInfo = if ($Syslog.FileData) { Invoke-HtmlEncode "$($Syslog.FileData)" } else { "N/A" }
    $rows = @(
        (New-HtmlTableRow -Cells @("Syslog Servers", $servers)),
        (New-HtmlTableRow -Cells @("File Logging",   $fileInfo))
    )
    $table = New-HtmlTable -Headers @("Property","Value") -Rows $rows
    return New-HtmlSection -Id "syslog" -Title "Syslog" -Content $table
}

