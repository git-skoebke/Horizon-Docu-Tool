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

# ── Read existing changelog ───────────────────────────────────────────────────
$content = Get-Content $changelogPath -Raw -Encoding UTF8

$today       = Get-Date -Format "yyyy-MM-dd"
$todayHeader = "## [$today]"

if ($content -match [regex]::Escape($todayHeader)) {
    # ── Today's section already exists ─────────────────────────────────────
    $categoryHeader = "### $category"

    if ($content -match "(?ms)$([regex]::Escape($todayHeader)).*?$([regex]::Escape($categoryHeader))") {
        # Category block found — prepend entry after the category header
        $content = $content -replace `
            "($([regex]::Escape($categoryHeader)))", `
            "`$1`n- $entry"
    } else {
        # Category missing inside today's section — insert before next ## block or EOF
        $content = $content -replace `
            "($([regex]::Escape($todayHeader))[^\n]*\n)", `
            "`$1`n$categoryHeader`n- $entry`n"
    }
} else {
    # ── No section for today yet — insert after [Unreleased] ───────────────
    $newSection = @"

---

$todayHeader

### $category
- $entry

---

"@
    $content = $content -replace `
        '(## \[Unreleased\][^\n]*\n)', `
        "`$1$newSection"
}

# Write back (UTF-8 without BOM)
[System.IO.File]::WriteAllText($changelogPath, $content, [System.Text.UTF8Encoding]::new($false))

Write-Host "CHANGELOG.md updated ($category): $entry"
