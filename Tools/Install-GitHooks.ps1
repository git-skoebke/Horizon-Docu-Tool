# =============================================================================
# Install-GitHooks.ps1
# Copies Git hooks from Tools/hooks/ into .git/hooks/ and makes them executable.
# Run once after cloning the repository.
# =============================================================================

$repoRoot  = Split-Path $PSScriptRoot -Parent
$hooksDir  = Join-Path $repoRoot ".git\hooks"
$sourceDir = Join-Path $PSScriptRoot "hooks"

if (-not (Test-Path $hooksDir)) {
    Write-Error "Not a git repository (no .git/hooks found)."
    exit 1
}

$hooks = Get-ChildItem -Path $sourceDir -File
foreach ($hook in $hooks) {
    $dest = Join-Path $hooksDir $hook.Name
    Copy-Item -Path $hook.FullName -Destination $dest -Force

    # Make executable on Unix/WSL (no-op on plain Windows, but harmless)
    if ($IsLinux -or $IsMacOS) {
        chmod +x $dest
    } elseif (Get-Command "git" -ErrorAction SilentlyContinue) {
        & git update-index --chmod=+x $hook.FullName 2>$null
    }

    Write-Host "Installed: $($hook.Name) → .git/hooks/$($hook.Name)"
}

Write-Host "`nGit hooks installed. CHANGELOG.md will be updated automatically on each commit."
