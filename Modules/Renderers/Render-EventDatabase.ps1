# =============================================================================
# Render-EventDatabase — New-HtmlEventDatabaseSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlEventDatabaseSection {
    param($EventDatabase)
    if ($null -eq $EventDatabase) {
        return ""
    }
    if ($EventDatabase.Configured -eq $false) {
        return ""
    }
    $rows = @(
        (New-HtmlTableRow -Cells @("Server",              (Invoke-HtmlEncode $EventDatabase.Server))),
        (New-HtmlTableRow -Cells @("Username",            (Invoke-HtmlEncode $EventDatabase.UserName))),
        (New-HtmlTableRow -Cells @("Database Name",       (Invoke-HtmlEncode $EventDatabase.DatabaseName))),
        (New-HtmlTableRow -Cells @("Port",                (Invoke-HtmlEncode "$($EventDatabase.Port)"))),
        (New-HtmlTableRow -Cells @("Type",                (Invoke-HtmlEncode $EventDatabase.Type))),
        (New-HtmlTableRow -Cells @("Table Prefix",        (Invoke-HtmlEncode $EventDatabase.TablePrefix))),
        (New-HtmlTableRow -Cells @("Show Events For",     (Invoke-HtmlEncode "$($EventDatabase.ShowEventsFor)"))),
        (New-HtmlTableRow -Cells @("New Events Period",   (Invoke-HtmlEncode "$($EventDatabase.NewEventsDays) days")))
    )
    $table = New-HtmlTable -Headers @("Property","Value") -Rows $rows
    return New-HtmlSection -Id "event-database" -Title "Event Database" -Content $table
}

