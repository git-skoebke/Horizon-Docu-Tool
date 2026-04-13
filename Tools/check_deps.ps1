$base = 'C:\Claude_Projects\Horizon Docu Tool\VMware PowerCLI Modules'
$mods = @(
    'VMware.VimAutomation.Core',
    'VMware.VimAutomation.Cis.Core',
    'VMware.VimAutomation.Common',
    'VMware.VimAutomation.Sdk',
    'VMware.Vim'
)
foreach ($m in $mods) {
    $psd = Get-ChildItem "$base\$m" -Recurse -Filter "*.psd1" | Select-Object -First 1
    if ($psd) {
        Write-Host "=== $m ==="
        $data = Import-PowerShellDataFile $psd.FullName
        $data.RequiredModules | ForEach-Object { Write-Host "  needs: $_" }
    }
}
