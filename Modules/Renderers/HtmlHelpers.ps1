# =============================================================================
# HtmlHelpers — Invoke-HtmlEncode, New-HtmlBadge, New-HtmlTableRow, New-HtmlTable, New-HtmlSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function Invoke-HtmlEncode {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return "" }
    return [System.Net.WebUtility]::HtmlEncode($Value)
}

function New-HtmlBadge {
    param([string]$Text, [string]$Color = "neutral")
    return "<span class=""badge badge-$Color"">$(Invoke-HtmlEncode $Text)</span>"
}

function New-HtmlTableRow {
    param([string[]]$Cells)
    $tdList = ($Cells | ForEach-Object { "<td>$_</td>" }) -join ""
    return "<tr>$tdList</tr>"
}

function Get-HtmlColWidths {
    # Returns a <colgroup> with equal-percent widths (100/n%).
    # 2 cols → 50/50, 3 cols → 33.33 each, 4 cols → 25/25/25/25, etc.
    param([string[]]$Headers)

    $n = $Headers.Count
    if ($n -eq 0) { return "" }

    $pct = [math]::Round(100 / $n, 2)
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.Append("<colgroup>")
    for ($i = 0; $i -lt $n; $i++) {
        $null = $sb.Append("<col style='width:$pct%'>")
    }
    $null = $sb.Append("</colgroup>")
    return $sb.ToString()
}

function New-HtmlTable {
    param(
        [string[]]$Headers,
        [string[]]$Rows,
        # Optional explicit column widths (CSS values, e.g. '30%','70%').
        # When provided, overrides the automatic width catalogue.
        [string[]]$Cols = @()
    )
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.Append('<table style="table-layout:fixed;width:100%;">')

    if ($Cols.Count -gt 0) {
        # Explicit widths provided by caller.
        $null = $sb.Append("<colgroup>")
        foreach ($c in $Cols) { $null = $sb.Append("<col style='width:$c'>") }
        $null = $sb.Append("</colgroup>")
    } else {
        $null = $sb.Append((Get-HtmlColWidths -Headers $Headers))
    }

    $null = $sb.Append("<thead><tr>")
    foreach ($h in $Headers) { $null = $sb.Append("<th>$(Invoke-HtmlEncode $h)</th>") }
    $null = $sb.Append("</tr></thead>")
    $null = $sb.Append("<tbody>")
    foreach ($row in $Rows) { $null = $sb.Append($row + "`n") }
    $null = $sb.Append("</tbody></table>")
    return $sb.ToString()
}

function New-HtmlSection {
    param([string]$Id, [string]$Title, [string]$Content)
    return @"
    <section id="$Id">
      <h2>$(Invoke-HtmlEncode $Title)</h2>
      $Content
    </section>
"@
}
