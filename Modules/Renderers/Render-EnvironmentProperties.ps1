# =============================================================================
# Render-EnvironmentProperties — New-HtmlEnvironmentPropertiesSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlEnvironmentPropertiesSection {
    param($Env)
    if ($null -eq $Env) {
        return ""
    }
    $rows = @(
        (New-HtmlTableRow -Cells @("Cluster Name",               (Invoke-HtmlEncode $Env.ClusterName))),
        (New-HtmlTableRow -Cells @("Cluster GUID",               (Invoke-HtmlEncode $Env.ClusterGuid))),
        (New-HtmlTableRow -Cells @("Deployment Type",            (Invoke-HtmlEncode $Env.DeploymentType))),
        (New-HtmlTableRow -Cells @("CS Version",                 (Invoke-HtmlEncode $Env.LocalConnectionServerVersion))),
        (New-HtmlTableRow -Cells @("CS Build",                   (Invoke-HtmlEncode $Env.LocalConnectionServerBuild))),
        (New-HtmlTableRow -Cells @("IP Mode",                    (Invoke-HtmlEncode $Env.IpMode))),
        (New-HtmlTableRow -Cells @("Timezone Offset",            (Invoke-HtmlEncode "$($Env.TimezoneOffset)"))),
        (New-HtmlTableRow -Cells @("FIPS Mode",                  (Invoke-HtmlEncode "$($Env.FipsModeEnabled)")))
    )
    $table = New-HtmlTable -Headers @("Property","Value") -Rows $rows
    return New-HtmlSection -Id "environment" -Title "Environment Properties" -Content $table
}

