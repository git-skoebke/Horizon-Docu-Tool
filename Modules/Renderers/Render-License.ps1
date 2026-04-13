# =============================================================================
# Render-License — New-HtmlLicenseSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlLicenseSection {
    param($License)
    if ($null -eq $License) {
        return ""
    }

    $healthBadge = switch ($License.LicenseHealth) {
        "OK"      { New-HtmlBadge -Text "OK"      -Color "ok" }
        "GREEN"   { New-HtmlBadge -Text "OK"      -Color "ok" }
        "WARNING" { New-HtmlBadge -Text "WARNING" -Color "warn" }
        "YELLOW"  { New-HtmlBadge -Text "WARNING" -Color "warn" }
        "ERROR"   { New-HtmlBadge -Text "ERROR"   -Color "error" }
        "RED"     { New-HtmlBadge -Text "ERROR"   -Color "error" }
        default   { New-HtmlBadge -Text "$($License.LicenseHealth)" -Color "neutral" }
    }

    $expirationDisplay = if (-not $License.ExpirationTime) {
        New-HtmlBadge -Text "PERPETUAL" -Color "ok"
    } else {
        Invoke-HtmlEncode $License.ExpirationTime
    }

    # Mask license key: show first 5 and last 5 chars
    $keyDisplay = if ($License.LicenseKey) {
        $k = $License.LicenseKey
        if ($k.Length -gt 12) { $k.Substring(0,5) + "***" + $k.Substring($k.Length - 5) }
        else { $k }
    } else { "" }

    $rows = @(
        (New-HtmlTableRow -Cells @("Edition",                   (Invoke-HtmlEncode $License.LicenseEdition))),
        (New-HtmlTableRow -Cells @("Health",                    $healthBadge)),
        (New-HtmlTableRow -Cells @("License Key",               (Invoke-HtmlEncode $keyDisplay))),
        (New-HtmlTableRow -Cells @("License Mode",              (Invoke-HtmlEncode $License.LicenseMode))),
        (New-HtmlTableRow -Cells @("Usage Model",               (Invoke-HtmlEncode $License.UsageModel))),
        (New-HtmlTableRow -Cells @("Expiration",                $expirationDisplay)),
        (New-HtmlTableRow -Cells @("License Sync Time",         (Invoke-HtmlEncode $License.LicenseSyncTime))),
        (New-HtmlTableRow -Cells @("Subscription Slice Expiry", (Invoke-HtmlEncode $License.SubscriptionSliceExpiry)))
    )
    $table = New-HtmlTable -Headers @("Property","Value") -Rows $rows
    return New-HtmlSection -Id "license" -Title "License" -Content $table
}

