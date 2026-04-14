# =============================================================================
# Update-Changelog.ps1
# Called automatically by the Git prepare-commit-msg hook.
# Adds a new entry to CHANGELOG.md for the current commit message.
# =============================================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$CommitMessage
)

# Skip empty, merge, or fixup messages
if ([string]::IsNullOrWhiteSpace($CommitMessage)) { exit 0 }
if ($CommitMessage -match '^(Merge |fixup! |squash! )') { exit 0 }

$repoRoot      = Split-Path $PSScriptRoot -Parent
$changelogPath = Join-Path $repoRoot "CHANGELOG.md"

if (-not (Test-Path $changelogPath)) {
    Write-Warning "CHANGELOG.md not found at $changelogPath"
    exit 1
}

# ── Determine category from commit message prefix ─────────────────────────────
$category = switch -Regex ($CommitMessage) {
    '^Fix'      { 'Fixed'   }
    '^Add'      { 'Added'   }
    '^Remove'   { 'Removed' }
    '^Revert'   { 'Removed' }
    '^Refactor' { 'Changed' }
    '^Improve'  { 'Changed' }
    '^Update'   { 'Changed' }
    '^Bump'     { 'Changed' }
    default     { 'Changed' }
}

# Strip trailing period, normalise whitespace
$entry = ($CommitMessage.Trim()).TrimEnd('.')

# ── Read existing changelog as lines ─────────────────────────────────────────
$lines   = [System.IO.File]::ReadAllLines($changelogPath, [System.Text.UTF8Encoding]::new($false))
$today   = Get-Date -Format "yyyy-MM-dd"
$todayH  = "## [$today]"
$catH    = "### $category"

# Find today's section start index (-1 = not found)
$todayIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Trim() -eq $todayH) { $todayIdx = $i; break }
}

# Find next section start (any "## [" line after today, or EOF)
$nextSectionIdx = $lines.Count
if ($todayIdx -ge 0) {
    for ($i = $todayIdx + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^## \[') { $nextSectionIdx = $i; break }
    }
}

$result = [System.Collections.Generic.List[string]]::new()

if ($todayIdx -lt 0) {
    # ── No section for today yet — insert after [Unreleased] line ────────────
    $unrelIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '## [Unreleased]') { $unrelIdx = $i; break }
    }

    foreach ($line in $lines) { $result.Add($line) }

    if ($unrelIdx -ge 0) {
        # Insert new section after [Unreleased] block (skip until next --- or ##)
        $insertAfter = $unrelIdx
        for ($i = $unrelIdx + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^---' -or $lines[$i] -match '^## \[') {
                $insertAfter = $i
                break
            }
        }
        $newSection = @('', '---', '', $todayH, '', $catH, "- $entry", '', '---')
        $result.InsertRange($insertAfter, [string[]]$newSection)
    } else {
        # No [Unreleased] found — prepend at top after title
        $result.InsertRange(2, [string[]]@('', $todayH, '', $catH, "- $entry", '', '---'))
    }
} else {
    # ── Today's section exists — search for category WITHIN it only ──────────
    $catIdx = -1
    for ($i = $todayIdx + 1; $i -lt $nextSectionIdx; $i++) {
        if ($lines[$i].Trim() -eq $catH) { $catIdx = $i; break }
    }

    if ($catIdx -ge 0) {
        # Category found — insert entry directly after category header
        foreach ($line in $lines) { $result.Add($line) }
        $result.Insert($catIdx + 1, "- $entry")
    } else {
        # Category not found in today's section — insert before first existing ### or end of section
        $insertAt = $nextSectionIdx
        for ($i = $todayIdx + 1; $i -lt $nextSectionIdx; $i++) {
            if ($lines[$i] -match '^### ') { $insertAt = $i; break }
        }
        foreach ($line in $lines) { $result.Add($line) }
        $result.InsertRange($insertAt, [string[]]@($catH, "- $entry", ''))
    }
}

[System.IO.File]::WriteAllLines($changelogPath, $result, [System.Text.UTF8Encoding]::new($false))

Write-Host "CHANGELOG.md updated ($category): $entry"
