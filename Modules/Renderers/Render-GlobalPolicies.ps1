# =============================================================================
# Render-GlobalPolicies — New-HtmlGlobalPoliciesSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlGlobalPoliciesSection {
    param($GlobalPolicies)
    if ($null -eq $GlobalPolicies) {
        return ""
    }
    $rows = @(
        (New-HtmlTableRow -Cells @("Multimedia Redirection",  (Invoke-HtmlEncode "$($GlobalPolicies.AllowMultimediaRedirection)"))),
        (New-HtmlTableRow -Cells @("USB Access",              (Invoke-HtmlEncode "$($GlobalPolicies.AllowUSBAccess)"))),
        (New-HtmlTableRow -Cells @("Remote Mode",             (Invoke-HtmlEncode "$($GlobalPolicies.AllowRemoteMode)"))),
        (New-HtmlTableRow -Cells @("PCoIP Hardware Accel.",   (Invoke-HtmlEncode "$($GlobalPolicies.AllowPCoIPHardwareAcceleration)")))
    )
    $table = New-HtmlTable -Headers @("Policy","Value") -Rows $rows
    return New-HtmlSection -Id "global-policies" -Title "Global Policies" -Content $table
}

