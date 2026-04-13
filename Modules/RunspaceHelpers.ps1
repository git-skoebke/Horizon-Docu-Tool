# =============================================================================
# RunspaceHelpers — UI logging from within a background Runspace
# Dot-sourced inside the Runspace scriptblock
# Requires: $window, $controls (passed from UI thread)
# =============================================================================

function Write-RunspaceLog {
    param([string]$Msg, [string]$Level = "INFO")
    $ts = Get-Date -Format "HH:mm:ss"
    $window.Dispatcher.Invoke([Action]{
        $controls["LogBox"].AppendText("[$ts] [$Level] $Msg`r`n")
        $controls["LogBox"].ScrollToEnd()
    })
}
