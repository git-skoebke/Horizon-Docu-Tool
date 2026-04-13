# =============================================================================
# Render-Gateways — New-HtmlGatewaysSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlGatewaysSection {
    param($Gateways)
    if (-not $Gateways -or $Gateways.Count -eq 0) {
        return ""
    }
    $rows = foreach ($g in $Gateways) {
        $zoneBadge = if ($g.Internal) { New-HtmlBadge -Text "Internal" -Color "neutral" } else { New-HtmlBadge -Text "External" -Color "ok" }
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $g.Name),
            (Invoke-HtmlEncode $g.Address),
            (Invoke-HtmlEncode $g.Version),
            $zoneBadge
        )
    }
    $table = New-HtmlTable -Headers @("Name","Address","Version","Zone") -Rows $rows
    return New-HtmlSection -Id "gateways" -Title "Gateways / UAG" -Content $table
}

