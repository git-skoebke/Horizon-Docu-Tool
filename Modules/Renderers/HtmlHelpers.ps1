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
    # Returns a <colgroup> string for table-layout:fixed.
    # Strategy:
    #   - Known short/badge columns get fixed pixel widths (narrow).
    #   - Known timestamp/date columns get fixed pixel widths (medium).
    #   - Special 2-column combinations (Property+Value, Setting+Value) get percent splits.
    #   - All remaining columns share the leftover space equally as percentages.
    param([string[]]$Headers)

    $n = $Headers.Count
    if ($n -eq 0) { return "" }

    # ── Special-case: pure 2-column key/value tables ──────────────────────
    # These are so common and benefit from a fixed label/value split.
    if ($n -eq 2) {
        $known2 = @{
            'Property|Value'          = @('35%','65%')
            'Setting|Value'           = @('35%','65%')
            'Policy|Value'            = @('40%','60%')
            'Feature|Enabled'         = @('60%','40%')
            'Policy|Enforcement State'= @('55%','45%')
            'Privilege|'              = @('100%')
            'Name|Description'        = @('35%','65%')
            'Name|Address'            = @('45%','55%')
            'Username|Role'           = @('55%','45%')
            'Auth Method|Status'      = @('65%','35%')
            'Role|VM Name'            = @('35%','65%')
            'Member'                  = @('100%')
        }
        $key = $Headers -join '|'
        if ($known2.ContainsKey($key)) {
            $ws = $known2[$key]
            return "<colgroup>" + (($ws | ForEach-Object { "<col style='width:$_'>" }) -join "") + "</colgroup>"
        }
    }

    # ── Pixel-width catalogue for known short/fixed columns ───────────────
    # Only px widths here — no percentages — so they don't interact badly with
    # the remaining-space calculation for flexible columns.
    $fixedPx = [ordered]@{
        'Status'          = 90
        'Type'            = 90
        'Enabled'         = 70
        'Port'            = 60
        'Size'            = 80
        'In Use'          = 70
        'Cap'             = 70
        'Used'            = 70
        'Free'            = 70
        'Usage %'         = 75
        'Accessible'      = 82
        'Attachable'      = 82
        'Secure'          = 70
        'SSL Verify'      = 82
        'Security'        = 80
        'Predefined'      = 90
        'Contactable'     = 90
        'CBRC'            = 65
        'Members'         = 120
        'Member Count'    = 130
        'NetBIOS'         = 80
        'Version'         = 75
        'Build'           = 90
        'Agent'           = 100
        'Log Level'       = 80
        'Pending %'       = 80
        'Message'         = 120
        'Spare'           = 60
        'Min'             = 55
        'Max'             = 55
        'Current'         = 70
        'CPUs (physical)' = 100
        'RAM GB'          = 70
        'Powered-On VMs'  = 100
        'vCPU:pCPU'       = 75
        'vGPU Types'      = 90
        'vGPU Driver'     = 90
        'Delivery'        = 100
        'Packages'        = 80
        'AppStacks'       = 82
        'Writables'       = 80
        'Override'        = 80
        'Site'            = 130
        'Home Site'       = 130
        'User / Group'    = 200
        'Connection Server' = 200
        # Timestamps — always the same width
        'Last Changed'    = 155
        'Assigned At'     = 155
        'Added'           = 145
        'Created'         = 145
        'Updated'         = 145
        'Cert From'       = 100
        'Cert To'         = 100
        'Cert Valid'      = 80
        'First Seen'      = 145
        'Last Seen'       = 145
        'Last Updated'    = 145
    }

    # Assign fixed px to known columns; mark others as flexible.
    $colPx   = @($null) * $n
    $totalPx = 0
    $flexIdx = [System.Collections.Generic.List[int]]::new()

    for ($i = 0; $i -lt $n; $i++) {
        $h  = $Headers[$i]
        $px = $fixedPx[$h]
        if ($px) {
            $colPx[$i] = $px
            $totalPx  += $px
        } else {
            $flexIdx.Add($i)
        }
    }

    # Distribute remaining width equally among flexible columns.
    # Assume the table container is ~1100px (report content area is flex:1
    # with 32px side padding — on a typical 1400-1600px viewport this gives
    # ~1100-1300px usable width after the 220px TOC sidebar).
    $nominalPx  = 1100
    $remainPx   = [math]::Max(0, $nominalPx - $totalPx)
    $flexPx     = if ($flexIdx.Count -gt 0) { [math]::Round($remainPx / $flexIdx.Count) } else { 0 }

    # Build <colgroup>
    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.Append("<colgroup>")
    for ($i = 0; $i -lt $n; $i++) {
        if ($colPx[$i]) {
            $null = $sb.Append("<col style='width:$($colPx[$i])px'>")
        } else {
            $null = $sb.Append("<col style='width:$($flexPx)px'>")
        }
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
