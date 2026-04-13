#Requires -Version 5.1
<#
.SYNOPSIS
    Horizon Documentation Tool — generates a self-contained HTML report of an Omnissa Horizon environment.

.DESCRIPTION
    Modular WPF PowerShell application. Enter Horizon Connection Server credentials,
    optionally test the connection, choose an output folder, and click Generate Report.
    The tool collects inventory data from the Horizon View API and produces a timestamped
    HTML report with no additional frameworks or dependencies.

    Modules are loaded via dot-sourcing from the Modules/ subdirectory:
      Modules/UI/           — Theme constants and WPF XAML definition
      Modules/Collectors/   — Data collection functions (Get-Hzn*)
      Modules/Renderers/    — HTML rendering functions (New-Html*)
      Modules/              — REST helpers and Runspace logging

.NOTES
    Modular architecture — see Modules/ for all collector and renderer implementations.
#>

# =============================================================================
# SECTION 1 — PS7 portable check + Admin elevation check and auto-relaunch
# =============================================================================

# Resolve the portable pwsh.exe relative to this script's location
$global:scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$portablePwsh      = Join-Path $global:scriptRoot "Tools\PowerShell-7.6.0-win-x64\pwsh.exe"

# If we are NOT running under PowerShell 7+, relaunch with the portable pwsh.exe
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if (Test-Path $portablePwsh) {
        $scriptPath = $MyInvocation.MyCommand.Definition
        $isAdmin    = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                          [Security.Principal.WindowsBuiltInRole]::Administrator)
        $verb       = if ($isAdmin) { "open" } else { "runas" }
        Start-Process -FilePath $portablePwsh `
                      -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
                      -Verb $verb
    } else {
        # Portable PS7 missing — fall back to system PowerShell with elevation
        $scriptPath = $MyInvocation.MyCommand.Definition
        Start-Process powershell.exe `
                      -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
                      -Verb runas
    }
    exit
}

# Running under PS7 — ensure we have admin rights
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $scriptPath = $MyInvocation.MyCommand.Definition
    $pwshExe    = if (Test-Path $portablePwsh) { $portablePwsh } else { 'pwsh.exe' }
    Start-Process -FilePath $pwshExe `
                  -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" `
                  -Verb RunAs
    exit
}

# =============================================================================
# SECTION 2 — Assembly loads
# =============================================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# =============================================================================
# SECTION 3 — Module imports (with error handling)
# =============================================================================

$global:moduleLoadError = $null
# $global:scriptRoot already set in Section 1

try {
    $horizonModulePath = Join-Path $global:scriptRoot "Omnissa Horizon Modules\Omnissa.VimAutomation.HorizonView\Omnissa.VimAutomation.HorizonView.psd1"
    $helperModulePath  = Join-Path $global:scriptRoot "Omnissa Horizon Modules\Omnissa.Horizon.Helper\Omnissa.Horizon.Helper.psd1"

    if (Test-Path $horizonModulePath) {
        Import-Module $horizonModulePath -Force -ErrorAction Stop
    } elseif (Get-Module -ListAvailable -Name Omnissa.VimAutomation.HorizonView -ErrorAction SilentlyContinue) {
        Import-Module Omnissa.VimAutomation.HorizonView -Force -ErrorAction Stop
    } else {
        throw "Module not found: $horizonModulePath"
    }

    if (Test-Path $helperModulePath) {
        Import-Module $helperModulePath -Force -ErrorAction SilentlyContinue
    } elseif (Get-Module -ListAvailable -Name Omnissa.Horizon.Helper -ErrorAction SilentlyContinue) {
        Import-Module Omnissa.Horizon.Helper -Force -ErrorAction SilentlyContinue
    }
} catch {
    $global:moduleLoadError = $_.Exception.Message
}

# =============================================================================
# SECTION 4 — Config load/save functions (JSON in AppData)
# =============================================================================

$global:settingsPath = Join-Path $env:APPDATA "HorizonDocTool\settings.json"

# DPAPI helpers — encrypt/decrypt using the current Windows user account.
# Ciphertext is a hex-encoded ConvertFrom-SecureString blob; only the same
# user on the same machine can decrypt it.
function Protect-SettingsPassword {
    param([string]$PlainText)
    if ([string]::IsNullOrEmpty($PlainText)) { return "" }
    try {
        $ss  = ConvertTo-SecureString $PlainText -AsPlainText -Force
        return ConvertFrom-SecureString $ss   # DPAPI-encrypted, hex string
    } catch { return "" }
}

function Unprotect-SettingsPassword {
    param([string]$Encrypted)
    if ([string]::IsNullOrEmpty($Encrypted)) { return "" }
    try {
        $ss   = ConvertTo-SecureString $Encrypted   # re-hydrate DPAPI blob
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
        return [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } catch { return "" }
}

function Load-Settings {
    $defaults = @{
        LastServer        = ""; LastUsername  = ""; LastDomain      = ""
        LastVcUser        = ""; LastGuestUser = ""; LastUagUser = ""; LastAvUser = ""
        LastAvFqdn        = ""
        LastIgnoreSsl     = $false
        LastOutputFolder  = ""; LastExportPdf = $false; LastOpenHtml = $true
        SaveCredentials   = $false
        LastPassword_Enc      = ""; LastVcPassword_Enc = ""; LastGuestPassword_Enc = ""
        LastUagPassword_Enc   = ""; LastAvPassword_Enc = ""
        CompanyInfo       = @{}
    }
    if (Test-Path $global:settingsPath) {
        try {
            $saved = Get-Content $global:settingsPath -Raw | ConvertFrom-Json
            if ($saved.LastServer)       { $defaults.LastServer       = $saved.LastServer }
            if ($saved.LastUsername)      { $defaults.LastUsername     = $saved.LastUsername }
            if ($saved.LastDomain)        { $defaults.LastDomain       = $saved.LastDomain }
            if ($saved.LastVcUser)        { $defaults.LastVcUser       = $saved.LastVcUser }
            if ($saved.LastGuestUser)     { $defaults.LastGuestUser    = $saved.LastGuestUser }
            if ($saved.LastUagUser)       { $defaults.LastUagUser      = $saved.LastUagUser }
            if ($saved.LastAvUser)        { $defaults.LastAvUser       = $saved.LastAvUser }
            if ($saved.LastAvFqdn)        { $defaults.LastAvFqdn       = $saved.LastAvFqdn }
            if ($saved.LastOutputFolder)  { $defaults.LastOutputFolder = $saved.LastOutputFolder }
            if ($null -ne $saved.LastIgnoreSsl)      { $defaults.LastIgnoreSsl      = [bool]$saved.LastIgnoreSsl }
            if ($null -ne $saved.LastExportPdf)      { $defaults.LastExportPdf      = [bool]$saved.LastExportPdf }
            if ($null -ne $saved.LastOpenHtml)       { $defaults.LastOpenHtml       = [bool]$saved.LastOpenHtml }
            if ($null -ne $saved.SaveCredentials)    { $defaults.SaveCredentials    = [bool]$saved.SaveCredentials }
            if ($saved.LastPassword_Enc)             { $defaults.LastPassword_Enc      = $saved.LastPassword_Enc }
            if ($saved.LastVcPassword_Enc)           { $defaults.LastVcPassword_Enc    = $saved.LastVcPassword_Enc }
            if ($saved.LastGuestPassword_Enc)        { $defaults.LastGuestPassword_Enc = $saved.LastGuestPassword_Enc }
            if ($saved.LastUagPassword_Enc)          { $defaults.LastUagPassword_Enc   = $saved.LastUagPassword_Enc }
            if ($saved.LastAvPassword_Enc)           { $defaults.LastAvPassword_Enc    = $saved.LastAvPassword_Enc }
            if ($saved.CompanyInfo) {
                $ci = $saved.CompanyInfo
                $defaults.CompanyInfo = @{
                    CompanyName   = if ($ci.CompanyName)   { $ci.CompanyName }   else { "" }
                    ContactPerson = if ($ci.ContactPerson) { $ci.ContactPerson } else { "" }
                    ContactRole   = if ($ci.ContactRole)   { $ci.ContactRole }   else { "" }
                    Street        = if ($ci.Street)        { $ci.Street }        else { "" }
                    ZipCity       = if ($ci.ZipCity)       { $ci.ZipCity }       else { "" }
                    Country       = if ($ci.Country)       { $ci.Country }       else { "" }
                    Phone         = if ($ci.Phone)         { $ci.Phone }         else { "" }
                    Email         = if ($ci.Email)         { $ci.Email }         else { "" }
                }
            }
        } catch {
            # Silently ignore parse errors - return defaults
        }
    }
    return $defaults
}

function Save-Settings {
    param([hashtable]$Settings)
    $dir = Split-Path $global:settingsPath
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    $Settings | ConvertTo-Json | Set-Content -Path $global:settingsPath -Encoding UTF8
}

# =============================================================================
# SECTION 5 — Theme constants (loaded from Modules/UI/Theme.ps1)
# =============================================================================

. (Join-Path $global:scriptRoot "Modules\UI\Theme.ps1")

# =============================================================================
# SECTION 6 — XAML definition (loaded from Modules/UI/WindowXaml.ps1)
# =============================================================================

. (Join-Path $global:scriptRoot "Modules\UI\WindowXaml.ps1")

# Load Company Info dialog
. (Join-Path $global:scriptRoot "Modules\UI\CompanyInfoDialog.ps1")

# Load Requirements dialog
. (Join-Path $global:scriptRoot "Modules\UI\RequirementsDialog.ps1")

# Load VM Start Confirm dialog
. (Join-Path $global:scriptRoot "Modules\UI\VmStartConfirmDialog.ps1")

# =============================================================================
# SECTION 7 — Window load and controls dictionary
# =============================================================================

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$controlNames = @(
    "TxtServer", "TxtUsername", "PwdPassword", "TxtDomain",
    "ChkIgnoreSsl", "ChkSaveCredentials", "TxtVcUser", "PwdVcPassword",
    "TxtGuestUser", "PwdGuestPassword", "TxtUagUser", "PwdUagPassword",
    "TxtAvUser", "PwdAvPassword", "TxtAvFqdn",
    "BtnTestConnection", "BtnCancel",
    "TxtConnectionInfo", "TxtErrorLabel",
    "TxtFolderPath", "BtnBrowseFolder", "BtnCompanyInfo", "BtnRequirements", "ChkExportPdf", "ChkOpenHtml", "BtnGenerateReport",
    "ProgressBar", "TxtProgressLabel", "LogBox"
)
$controls = @{}
foreach ($name in $controlNames) {
    $ctrl = $window.FindName($name)
    if ($ctrl) { $controls[$name] = $ctrl }
    else { Write-Warning "Control not found: $name" }
}

# =============================================================================
# SECTION 8 — Helper functions
# =============================================================================

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    $window.Dispatcher.Invoke([Action]{
        $controls["LogBox"].AppendText("$line`r`n")
        $controls["LogBox"].ScrollToEnd()
    })
}

function Set-Status {
    param(
        [string]$Message,
        [string]$Color = $global:Theme.FgSecondary
    )
    $window.Dispatcher.Invoke([Action]{
        $controls["TxtProgressLabel"].Text = $Message
    })
}

function Clear-ErrorLabel {
    $controls["TxtErrorLabel"].Visibility    = [System.Windows.Visibility]::Collapsed
    $controls["TxtConnectionInfo"].Visibility = [System.Windows.Visibility]::Collapsed
}

function Show-ErrorLabel {
    param([string]$Message)
    $controls["TxtErrorLabel"].Text       = $Message
    $controls["TxtErrorLabel"].Visibility = [System.Windows.Visibility]::Visible
}

# =============================================================================
# SECTION 9 — Credential parsing function
# =============================================================================

function Get-ParsedCredentials {
    param(
        [string]$Username,
        [string]$DomainOverride
    )
    if ($Username -match '^(.+)\\(.+)$') {
        $domain = if ($DomainOverride -and $DomainOverride.Trim()) { $DomainOverride.Trim() } else { $Matches[1] }
        $user   = $Matches[2]
    } else {
        $domain = if ($DomainOverride) { $DomainOverride.Trim() } else { "" }
        $user   = $Username
    }
    return @{ Username = $user; Domain = $domain }
}

# =============================================================================
# SECTION 10 — Event handler stubs (wired up, functional placeholders)
# =============================================================================

# Browse button — opens FolderBrowserDialog and populates TxtFolderPath
$controls["BtnBrowseFolder"].Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description      = "Select output folder for the Horizon Documentation Report"
    $dialog.ShowNewFolderButton = $true
    if ($controls["TxtFolderPath"].Text -and (Test-Path $controls["TxtFolderPath"].Text)) {
        $dialog.SelectedPath = $controls["TxtFolderPath"].Text
    }
    $result = $dialog.ShowDialog()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $controls["TxtFolderPath"].Text = $dialog.SelectedPath
    }
})

# Company Info — opens modal dialog for optional company/contact data
$global:companyInfo = @{}

$controls["BtnCompanyInfo"].Add_Click({
    $result = Show-CompanyInfoDialog -CurrentData $global:companyInfo -Owner $window
    if ($null -ne $result) {
        $global:companyInfo = $result
        # Persist immediately
        $currentSettings = Load-Settings
        $currentSettings.CompanyInfo = $global:companyInfo
        Save-Settings $currentSettings
        Write-Log "Company info updated." "INFO"
    }
})

# Requirements — opens modal dialog with requirements and feature overview
$controls["BtnRequirements"].Add_Click({
    Show-RequirementsDialog -Owner $window
})

# Test Connection — Runspace + Dispatcher.Invoke pattern (Plan 02)
$controls["BtnTestConnection"].Add_Click({
    # --- Read all UI values on the UI thread ---
    $serverInput   = $controls["TxtServer"].Text.Trim()
    $usernameInput = $controls["TxtUsername"].Text.Trim()
    $passwordText  = $controls["PwdPassword"].Password      # Must be read here — thread-affine
    $domainInput   = $controls["TxtDomain"].Text.Trim()
    $ignoreSsl     = $controls["ChkIgnoreSsl"].IsChecked -eq $true

    # --- Validate inputs ---
    Clear-ErrorLabel
    if (-not $serverInput) {
        Show-ErrorLabel "Please enter a Connection Server address."
        return
    }
    if (-not $usernameInput) {
        Show-ErrorLabel "Please enter a username."
        return
    }
    if (-not $passwordText) {
        Show-ErrorLabel "Please enter a password."
        return
    }

    # --- Parse credentials (domain extraction from DOMAIN\user) ---
    $parsed = Get-ParsedCredentials -Username $usernameInput -DomainOverride $domainInput
    $finalUser   = $parsed.Username
    $finalDomain = $parsed.Domain

    # --- Disable button while running ---
    $controls["BtnTestConnection"].IsEnabled = $false
    $controls["TxtConnectionInfo"].Visibility = [System.Windows.Visibility]::Collapsed
    $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [INFO] Testing connection to $serverInput...`r`n")
    $controls["LogBox"].ScrollToEnd()
    if ($ignoreSsl) {
        $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [WARN] SSL certificate validation is disabled.`r`n")
        $controls["LogBox"].ScrollToEnd()
    }

    # --- Save credentials (persist last-used, passwords encrypted if checkbox active) ---
    $currentSettings = Load-Settings
    $saveCredentials  = $controls["ChkSaveCredentials"].IsChecked -eq $true
    $currentSettings.LastServer       = $serverInput
    $currentSettings.LastUsername      = $usernameInput
    $currentSettings.LastDomain       = $domainInput
    $currentSettings.LastIgnoreSsl    = $ignoreSsl
    $currentSettings.LastVcUser       = $controls["TxtVcUser"].Text.Trim()
    $currentSettings.LastGuestUser    = $guestUser
    $currentSettings.LastOutputFolder = $controls["TxtFolderPath"].Text.Trim()
    $currentSettings.LastExportPdf    = $controls["ChkExportPdf"].IsChecked -eq $true
    $currentSettings.LastOpenHtml     = $controls["ChkOpenHtml"].IsChecked -eq $true
    $currentSettings.SaveCredentials  = $saveCredentials
    if ($saveCredentials) {
        $currentSettings.LastPassword_Enc      = Protect-SettingsPassword $passwordText
        $currentSettings.LastVcPassword_Enc    = Protect-SettingsPassword $vcPassword
        $currentSettings.LastGuestPassword_Enc = Protect-SettingsPassword $guestPassword
    } else {
        $currentSettings.LastPassword_Enc      = ""
        $currentSettings.LastVcPassword_Enc    = ""
        $currentSettings.LastGuestPassword_Enc = ""
    }
    Save-Settings $currentSettings

    # --- Capture values needed inside Runspace ---
    $scriptRoot = $global:scriptRoot

    # --- Launch Runspace ---
    $global:testConnRunspace = [runspacefactory]::CreateRunspace()
    $global:testConnRunspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $global:testConnRunspace

    $ps.AddScript({
        param($server, $username, $password, $domain, $ignoreSsl, $moduleBasePath, $window, $controls)

        # TLS 1.2 (PS5 defaults to older TLS which modern servers reject)
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        # SSL bypass FIRST, before any network call
        if ($ignoreSsl) {
            [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        }

        # Import module inside Runspace (not inherited from outer scope)
        try {
            $modPath = Join-Path $moduleBasePath "Omnissa Horizon Modules\Omnissa.VimAutomation.HorizonView\Omnissa.VimAutomation.HorizonView.psd1"
            if (Test-Path $modPath) {
                Import-Module $modPath -Force -ErrorAction Stop
            } elseif (Get-Module -ListAvailable -Name Omnissa.VimAutomation.HorizonView -ErrorAction SilentlyContinue) {
                Import-Module Omnissa.VimAutomation.HorizonView -Force -ErrorAction Stop
            } else {
                throw "Module not found at $modPath and not installed in PSModulePath"
            }
        } catch {
            $importErr = $_.Exception.Message
            $window.Dispatcher.Invoke([Action]{
                $controls["TxtErrorLabel"].Text = "Module load failed - cannot connect."
                $controls["TxtErrorLabel"].Visibility = [System.Windows.Visibility]::Visible
                $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [ERROR] Module import failed: $importErr`r`n")
                $controls["LogBox"].ScrollToEnd()
                $controls["BtnTestConnection"].IsEnabled = $true
            })
            return
        }

        # Attempt connection
        try {
            $secPwd = ConvertTo-SecureString $password -AsPlainText -Force
            $cred   = New-Object System.Management.Automation.PSCredential($username, $secPwd)

            $connectParams = @{
                Server      = $server
                Credential  = $cred
                Domain      = $domain
                Force       = $true
                ErrorAction = "Stop"
            }

            $hvServer = Connect-HVServer @connectParams
            $hzServices = $hvServer.ExtensionData

            # List all CS nodes for GUI-03
            $csNodes = $hzServices.ConnectionServer.ConnectionServer_List()
            $csInfoParts = $csNodes | ForEach-Object {
                "$($_.General.Name) [$($_.General.Version)]"
            }
            $csInfoText = $csInfoParts -join "  |  "
            if (-not $csInfoText) { $csInfoText = "$server [version unknown]" }

            # Disconnect — Test Connection does not hold a persistent session
            Disconnect-HVServer -Server $hvServer -Confirm:$false -ErrorAction SilentlyContinue

            # Check PSRemoting on the target Connection Server
            $psRemotingOk = $false
            try {
                $testResult = Invoke-Command -ComputerName $server -Credential $cred -ErrorAction Stop -ScriptBlock { $true }
                if ($testResult -eq $true) { $psRemotingOk = $true }
            } catch {}

            $psRemoteWarn = ""
            if (-not $psRemotingOk) {
                $psRemoteWarn = "PSRemoting is not available on $server. " +
                    "Some report data (locked.properties, Local Admins, Disk Space, Last Patch) will be skipped. " +
                    "To enable, run on each Connection Server: Enable-PSRemoting -Force"
            }

            # Update UI on success
            $window.Dispatcher.Invoke([Action]{
                $controls["TxtConnectionInfo"].Text = "Connected: $csInfoText"
                $controls["TxtConnectionInfo"].Visibility = [System.Windows.Visibility]::Visible
                $controls["TxtErrorLabel"].Visibility = [System.Windows.Visibility]::Collapsed
                $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [OK] Connection successful: $csInfoText`r`n")
                if ($psRemoteWarn) {
                    $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [WARN] $psRemoteWarn`r`n")
                }
                $controls["LogBox"].ScrollToEnd()
                $controls["BtnTestConnection"].IsEnabled = $true
            })

        } catch {
            $ex = $_
            # Map exception to user-friendly message
            $friendlyMsg = switch -Wildcard ($ex.Exception.Message) {
                "*authentication*"              { "Authentication failed - check username and password." }
                "*not authorized*"              { "Access denied - account may lack Horizon admin rights." }
                "*certificate*"                 { "SSL certificate error - enable 'Ignore SSL Certificate Errors' and retry." }
                "*name or service not known*"   { "Server not found - check the FQDN or IP address." }
                "*connection refused*"          { "Connection refused - check that the Connection Server is running." }
                "*timed out*"                   { "Connection timed out - server may be unreachable." }
                "*No connection could be made*" { "Connection failed - server not reachable on this network." }
                default                         { "Connection failed - see Log for details." }
            }
            $technicalMsg = $ex.Exception.Message

            $window.Dispatcher.Invoke([Action]{
                $controls["TxtErrorLabel"].Text = $friendlyMsg
                $controls["TxtErrorLabel"].Visibility = [System.Windows.Visibility]::Visible
                $controls["TxtConnectionInfo"].Visibility = [System.Windows.Visibility]::Collapsed
                $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [ERROR] $technicalMsg`r`n")
                $controls["LogBox"].ScrollToEnd()
                $controls["BtnTestConnection"].IsEnabled = $true
            })
        } finally {
            # Cleanup: reset SSL callback if it was set
            if ($ignoreSsl) {
                [Net.ServicePointManager]::ServerCertificateValidationCallback = $null
            }
        }

    }).AddArgument($serverInput).AddArgument($finalUser).AddArgument($passwordText).AddArgument($finalDomain).AddArgument($ignoreSsl).AddArgument($scriptRoot).AddArgument($window).AddArgument($controls)

    $global:testConnJob = $ps.BeginInvoke()
})

# Global cancellation token and Runspace handles for Generate Report (Plan 03)
$global:cancelToken      = [hashtable]::Synchronized(@{ Requested = $false })
$global:generateRunspace = $null
$global:generateJob      = $null

# Global VM-start handshake state (DispatcherTimer + ManualResetEventSlim pattern)
# Runspace writes PendingVMs + sets NeedDecision; UI-Thread reads, shows dialogs,
# writes Decisions, sets GotDecision; Runspace unblocks and proceeds with scans.
$global:vmStartState = [hashtable]::Synchronized(@{
    PendingVMs    = [System.Collections.Generic.List[string]]::new()
    Decisions     = @{}
    NeedDecision  = [System.Threading.ManualResetEventSlim]::new($false)
    GotDecision   = [System.Threading.ManualResetEventSlim]::new($false)
})

# DispatcherTimer — polls vmStartState.NeedDecision on the UI thread (200 ms).
# When Runspace signals pending VMs, timer stops, shows dialog(s) on UI thread
# (ShowDialog safe here — native UI thread), writes decisions, signals GotDecision.
$global:vmStartTimer = New-Object System.Windows.Threading.DispatcherTimer
$global:vmStartTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$global:vmStartTimer.Add_Tick({
    if (-not $global:vmStartState.NeedDecision.IsSet) { return }

    # Stop immediately — handle exactly one batch per report run
    $global:vmStartTimer.Stop()

    $pendingVMs = @($global:vmStartState.PendingVMs)
    $applyToAll = $null   # $null=ask each, $true=always start, $false=always skip

    foreach ($vmName in $pendingVMs) {
        if ($null -ne $applyToAll) {
            $global:vmStartState.Decisions[$vmName] = $applyToAll
        } else {
            $ans = Show-VmStartConfirmDialog -VmName $vmName -Owner $window
            $global:vmStartState.Decisions[$vmName] = $ans.Start
            if ($ans.ApplyToAll) { $applyToAll = $ans.Start }
        }
    }

    # Unblock the Runspace thread
    $global:vmStartState.GotDecision.Set()
})

# Generate Report — Runspace + determinate progress + graceful cancel (Plan 03)
$controls["BtnGenerateReport"].Add_Click({
    # --- Read UI values on UI thread ---
    $outputFolder = $controls["TxtFolderPath"].Text.Trim()

    # --- Validate ---
    Clear-ErrorLabel
    if (-not $outputFolder) {
        Show-ErrorLabel "Please select an output folder first."
        return
    }
    if (-not (Test-Path $outputFolder)) {
        Show-ErrorLabel "Output folder does not exist. Please select a valid folder."
        return
    }

    # --- Read connection credentials (needed for API collection) ---
    $serverInput   = $controls["TxtServer"].Text.Trim()
    $usernameInput = $controls["TxtUsername"].Text.Trim()
    $passwordText  = $controls["PwdPassword"].Password
    $domainInput   = $controls["TxtDomain"].Text.Trim()
    $ignoreSsl     = $controls["ChkIgnoreSsl"].IsChecked -eq $true
    $vcUser        = $controls["TxtVcUser"].Text.Trim()
    $vcPassword    = $controls["PwdVcPassword"].Password
    $guestUser     = $controls["TxtGuestUser"].Text.Trim()
    $guestPassword = $controls["PwdGuestPassword"].Password
    $uagUser       = $controls["TxtUagUser"].Text.Trim()
    $uagPassword   = $controls["PwdUagPassword"].Password
    $avUser        = $controls["TxtAvUser"].Text.Trim()
    $avPassword    = $controls["PwdAvPassword"].Password
    $avFqdn        = $controls["TxtAvFqdn"].Text.Trim()
    $exportPdf     = $controls["ChkExportPdf"].IsChecked -eq $true
    $openHtml      = $controls["ChkOpenHtml"].IsChecked -eq $true
    $companyInfo   = $global:companyInfo

    # --- Determine run mode ---
    # When an App Volumes FQDN is provided together with AV credentials, the tool
    # can run in AV-only mode (no Horizon Connection Server required). Horizon
    # fields stay optional and take precedence if they are also filled in.
    $avStandalone = ($avFqdn -and $avUser -and $avPassword -and -not $serverInput)

    if ($avStandalone) {
        # AV-only mode: skip all Horizon validation
        if (-not $avUser -or -not $avPassword) {
            Show-ErrorLabel "App Volumes username and password are required when documenting an App Volumes Manager directly."
            return
        }
    } else {
        # Standard mode: Horizon Connection Server is required
        if (-not $serverInput) {
            Show-ErrorLabel "Please enter a Connection Server address before generating a report — or fill in an App Volumes Manager FQDN on the App Volumes tab for AV-only documentation."
            return
        }
        if (-not $usernameInput) {
            Show-ErrorLabel "Please enter a username before generating a report."
            return
        }
        if (-not $passwordText) {
            Show-ErrorLabel "Please enter a password before generating a report."
            return
        }
    }

    # Parse DOMAIN\user format (only if a Horizon username was provided — AV-only mode skips this)
    $finalUser   = ""
    $finalDomain = ""
    if ($usernameInput) {
        $parsed      = Get-ParsedCredentials -Username $usernameInput -DomainOverride $domainInput
        $finalUser   = $parsed.Username
        $finalDomain = $parsed.Domain
    }

    # --- Save credentials (persist last-used, passwords encrypted if checkbox active) ---
    $currentSettings  = Load-Settings
    $saveCredentials  = $controls["ChkSaveCredentials"].IsChecked -eq $true
    $currentSettings.LastServer       = $serverInput
    $currentSettings.LastUsername      = $usernameInput
    $currentSettings.LastDomain       = $domainInput
    $currentSettings.LastIgnoreSsl    = $ignoreSsl
    $currentSettings.LastVcUser       = $vcUser
    $currentSettings.LastGuestUser    = $guestUser
    $currentSettings.LastUagUser      = $uagUser
    $currentSettings.LastAvUser       = $avUser
    $currentSettings.LastAvFqdn       = $avFqdn
    $currentSettings.LastOutputFolder = $controls["TxtFolderPath"].Text.Trim()
    $currentSettings.LastExportPdf    = $exportPdf
    $currentSettings.LastOpenHtml     = $openHtml
    $currentSettings.SaveCredentials  = $saveCredentials
    if ($saveCredentials) {
        $currentSettings.LastPassword_Enc      = Protect-SettingsPassword $passwordText
        $currentSettings.LastVcPassword_Enc    = Protect-SettingsPassword $vcPassword
        $currentSettings.LastGuestPassword_Enc = Protect-SettingsPassword $guestPassword
        $currentSettings.LastUagPassword_Enc   = Protect-SettingsPassword $uagPassword
        $currentSettings.LastAvPassword_Enc    = Protect-SettingsPassword $avPassword
    } else {
        $currentSettings.LastPassword_Enc      = ""
        $currentSettings.LastVcPassword_Enc    = ""
        $currentSettings.LastGuestPassword_Enc = ""
        $currentSettings.LastUagPassword_Enc   = ""
        $currentSettings.LastAvPassword_Enc    = ""
    }
    Save-Settings $currentSettings

    # --- Capture Runspace args ---
    $scriptRoot = $global:scriptRoot

    # --- Reset cancellation token ---
    $global:cancelToken.Requested = $false

    # --- Reset VM-start handshake state for this run ---
    $global:vmStartState.PendingVMs.Clear()
    $global:vmStartState.Decisions.Clear()
    $global:vmStartState.NeedDecision.Reset()
    $global:vmStartState.GotDecision.Reset()
    $global:vmStartTimer.Start()

    # --- Update UI state ---
    $controls["BtnGenerateReport"].IsEnabled = $false
    $controls["BtnTestConnection"].IsEnabled = $false
    $controls["BtnCancel"].IsEnabled         = $true
    $controls["ProgressBar"].Value            = 0
    $controls["TxtProgressLabel"].Text        = "Starting..."
    $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [INFO] Starting report generation. Output: $outputFolder`r`n")
    $controls["LogBox"].ScrollToEnd()

    # --- Capture the synchronized token for passing to Runspace ---
    $cancelToken = $global:cancelToken

    # --- Launch Runspace ---
    $global:generateRunspace = [runspacefactory]::CreateRunspace()
    $global:generateRunspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $global:generateRunspace

    $ps.AddScript({
        param($outputFolder, $moduleBasePath, $window, $controls, $cancelToken,
              $server, $username, $password, $domain, $ignoreSsl,
              $vcUsername, $vcPassword, $guestUsername, $guestPassword,
              $uagUsername, $uagPassword,
              $avUsername, $avPassword, $avFqdn,
              $exportPdf, $openHtml, $companyInfo, $vmStartState)

        # Run mode: AV-standalone when a Manager FQDN is provided without a Horizon Server.
        # In that case the Horizon login, REST token, vCenter and all Horizon collectors are
        # skipped — only the App Volumes pipeline runs.
        $avStandalone = ([string]::IsNullOrWhiteSpace($server)) -and -not [string]::IsNullOrWhiteSpace($avFqdn)
        # TLS 1.2 (PS5 defaults to older TLS which modern servers reject)
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

        # SSL bypass FIRST, before any network call
        if ($ignoreSsl) {
            [Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        }

        # Horizon module import + Connect-HVServer — only when a Connection Server was provided.
        # In AV-standalone mode both are skipped.
        $hvServer   = $null
        $hzServices = $null
        if (-not $avStandalone) {
            # Import module inside Runspace (not inherited from outer scope)
            try {
                $modPath = Join-Path $moduleBasePath "Omnissa Horizon Modules\Omnissa.VimAutomation.HorizonView\Omnissa.VimAutomation.HorizonView.psd1"
                if (Test-Path $modPath) {
                    Import-Module $modPath -Force -ErrorAction Stop
                } elseif (Get-Module -ListAvailable -Name Omnissa.VimAutomation.HorizonView -ErrorAction SilentlyContinue) {
                    Import-Module Omnissa.VimAutomation.HorizonView -Force -ErrorAction Stop
                } else {
                    throw "Module not found at $modPath and not installed in PSModulePath"
                }
            } catch {
                $importErr = $_.Exception.Message
                $window.Dispatcher.Invoke([Action]{
                    $controls["TxtErrorLabel"].Text = "Module load failed - cannot generate report."
                    $controls["TxtErrorLabel"].Visibility = [System.Windows.Visibility]::Visible
                    $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [ERROR] Module import failed: $importErr`r`n")
                    $controls["LogBox"].ScrollToEnd()
                    $controls["BtnGenerateReport"].IsEnabled = $true
                    $controls["BtnTestConnection"].IsEnabled = $true
                    $controls["BtnCancel"].IsEnabled         = $false
                })
                # Unblock timer in case it's waiting (early exit — no VMs will be processed)
                $vmStartState.GotDecision.Set()
                return
            }

            # Connect to Horizon (fresh connection — Test Connection disconnects immediately)
            try {
                $secPwd = ConvertTo-SecureString $password -AsPlainText -Force
                $cred   = New-Object System.Management.Automation.PSCredential($username, $secPwd)
                $connectParams = @{
                    Server      = $server
                    Credential  = $cred
                    Force       = $true
                    ErrorAction = "Stop"
                }
                if ($domain) { $connectParams.Domain = $domain }
                $hvServer   = Connect-HVServer @connectParams
                $hzServices = $hvServer.ExtensionData
                $window.Dispatcher.Invoke([Action]{
                    $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [OK] Connected to Horizon: $server`r`n")
                    $controls["LogBox"].ScrollToEnd()
                })
            } catch {
                $connErr = $_.Exception.Message
                $window.Dispatcher.Invoke([Action]{
                    $controls["TxtErrorLabel"].Text = "Connection failed - cannot generate report. Check credentials."
                    $controls["TxtErrorLabel"].Visibility = [System.Windows.Visibility]::Visible
                    $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [ERROR] Connection failed: $connErr`r`n")
                    $controls["LogBox"].ScrollToEnd()
                    $controls["ProgressBar"].Value     = 0
                    $controls["TxtProgressLabel"].Text = ""
                    $controls["BtnGenerateReport"].IsEnabled = $true
                    $controls["BtnTestConnection"].IsEnabled = $true
                    $controls["BtnCancel"].IsEnabled         = $false
                })
                if ($ignoreSsl) { [Net.ServicePointManager]::ServerCertificateValidationCallback = $null }
                $vmStartState.GotDecision.Set()
                return
            }
        } else {
            $window.Dispatcher.Invoke([Action]{
                $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [INFO] AV-standalone mode: skipping Horizon connection, documenting App Volumes Manager $avFqdn`r`n")
                $controls["LogBox"].ScrollToEnd()
            })
        }

        # Initialize synchronized data store for all collectors
        $collectedData = [hashtable]::Synchronized(@{
            ConnectionServers       = @()
            ConnectionServersHealth = @()
            VCenterServers          = @()
            VCenterHealth           = @()
            VCenterHealth_Internal  = @()
            Datastores              = @()
            ESXiHosts               = @()
            ADDomains               = @()
            Gateways                = @()
            GatewayCertificates     = @()
            UagData                 = @()
            AppVolumesData          = @()
            License                 = $null
            GeneralSettings         = $null
            GlobalPolicies          = $null
            EventDatabase           = $null

            SamlAuthenticators      = @()
            TrueSSO                 = $null
            Permissions             = @()
            IcDomainAccounts        = @()
            EnvironmentProperties   = $null
            AppVolumesManager       = @()
            Syslog                  = $null
            Cpa                     = $null
            GlobalEntitlements      = $null
            DesktopPools            = @()
            RdsFarms                = @()
            ApplicationPools        = @()
            LocalApplicationEntitlements = @()
            VcVmInventory           = $null
            ReportMeta              = @{
                GeneratedAt    = (Get-Date)
                ServerName     = if ($avStandalone) { $avFqdn } else { $server }
                HorizonVersion = ""
                AvStandalone   = $avStandalone
            }
        })

        # Dot-source helper modules into Runspace scope
        . (Join-Path $moduleBasePath "Modules\RunspaceHelpers.ps1")
        . (Join-Path $moduleBasePath "Modules\RestHelpers.ps1")
        # VmStartConfirmDialog is shown on the UI thread via DispatcherTimer — not needed here

        # Dot-source all Collector modules
        Get-ChildItem (Join-Path $moduleBasePath "Modules\Collectors\*.ps1") -ErrorAction SilentlyContinue |
            ForEach-Object { . $_.FullName }

        # Dot-source all Renderer modules (HtmlHelpers first for dependency order)
        $renderersPath = Join-Path $moduleBasePath "Modules\Renderers"
        $htmlHelpers = Join-Path $renderersPath "HtmlHelpers.ps1"
        if (Test-Path $htmlHelpers) { . $htmlHelpers }
        Get-ChildItem (Join-Path $renderersPath "*.ps1") -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "HtmlHelpers.ps1" } |
            ForEach-Object { . $_.FullName }

        # Authenticate REST API (non-fatal — collectors guard with if (-not $restToken))
        $restBase  = $null
        $restToken = $null
        if (-not $avStandalone) {
            $restBase = "https://$server/rest"
            try {
                $restToken = Get-HznRestToken -Server $server -Username $username -Password $password -Domain $domain
                Write-RunspaceLog "REST API authenticated" "INFO"
            } catch {
                Write-RunspaceLog "REST API auth failed: $($_.Exception.Message)" "WARN"
            }
        }

        # Connect to vCenter via PowerCLI (optional — enables IC chain lookup + VM counts)
        $viConnected = $false; $vcServer = $null
        if (-not $avStandalone -and $vcUsername -and $vcPassword) {
            try {
                $vcList = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v6/virtual-centers","config/v5/virtual-centers","config/v4/virtual-centers")
                if ($vcList -and @($vcList).Count -gt 0) { $vcServer = @($vcList)[0].server_name }
            } catch {}
            if ($vcServer) {
                try {
                    $vcModLoaded = $false
                    # 1st priority: local project copy (portable, no system install required)
                    # RequiredModules in .psd1 are resolved via $PSModulePath — to load locally
                    # we must pre-import the full dependency chain in bottom-up order so that
                    # PowerShell finds them already loaded and skips the PSModulePath lookup.
                    $localPcliBase  = Join-Path $moduleBasePath "VMware PowerCLI Modules"
                    $localVcModPath = Join-Path $localPcliBase "VMware.VimAutomation.Core\13.3.0.24145081\VMware.VimAutomation.Core.psd1"
                    if (Test-Path $localVcModPath) {
                        try {
                            # Load bottom-up: Sdk -> Common -> Vim -> Cis.Core -> Core
                            $depChain = @(
                                (Join-Path $localPcliBase "VMware.VimAutomation.Sdk\13.3.0.24145081\VMware.VimAutomation.Sdk.psd1"),
                                (Join-Path $localPcliBase "VMware.VimAutomation.Common\13.3.0.24145081\VMware.VimAutomation.Common.psd1"),
                                (Join-Path $localPcliBase "VMware.Vim\8.3.0.24145081\VMware.Vim.psd1"),
                                (Join-Path $localPcliBase "VMware.VimAutomation.Cis.Core\13.3.0.24145081\VMware.VimAutomation.Cis.Core.psd1"),
                                $localVcModPath
                            )
                            foreach ($depPath in $depChain) {
                                $depName = [System.IO.Path]::GetFileNameWithoutExtension($depPath)
                                if (-not (Get-Module -Name $depName -ErrorAction SilentlyContinue)) {
                                    Import-Module $depPath -Force -ErrorAction Stop -WarningAction SilentlyContinue
                                    Write-RunspaceLog "  Loaded: $depName" "INFO"
                                }
                            }
                            $vcModLoaded = $true
                            Write-RunspaceLog "PowerCLI loaded from local project copy" "INFO"
                        } catch {
                            Write-RunspaceLog "Local PowerCLI load failed: $($_.Exception.Message)" "WARN"
                        }
                    }
                    if (-not $vcModLoaded) {
                        # 2nd priority: system-wide installation
                        foreach ($vcMod in @("VMware.VimAutomation.Core","VMware.PowerCLI")) {
                            if (Get-Module -ListAvailable -Name $vcMod -ErrorAction SilentlyContinue) {
                                Import-Module $vcMod -ErrorAction Stop -WarningAction SilentlyContinue
                                $vcModLoaded = $true; break
                            }
                        }
                    }
                    if ($vcModLoaded) {
                        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
                        $vcSecPwd = ConvertTo-SecureString $vcPassword -AsPlainText -Force
                        $vcCred   = New-Object System.Management.Automation.PSCredential($vcUsername, $vcSecPwd)
                        Connect-VIServer -Server $vcServer -Credential $vcCred -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null
                        $viConnected = $true
                        Write-RunspaceLog "vCenter connected: $vcServer" "INFO"
                    } else {
                        Write-RunspaceLog "VMware PowerCLI not installed - vCenter features skipped" "WARN"
                    }
                } catch {
                    Write-RunspaceLog "vCenter connection failed: $($_.Exception.Message)" "WARN"
                }
            } else {
                Write-RunspaceLog "Could not resolve vCenter hostname from Horizon REST API" "WARN"
            }
        }

        # ── Build collector step list ──────────────────────────────────
        # In AV-standalone mode only the App Volumes API data collector runs, and the
        # manager list is primed from the manually entered FQDN (skipping the Horizon
        # discovery collector entirely).
        if ($avStandalone) {
            # Build credential for PSRemoting to AV Manager — prefer Guest creds, fall back to AV API creds
            $avmRemoteUser = if ($guestUsername) { $guestUsername } else { $avUsername }
            $avmRemotePwd  = if ($guestPassword) { $guestPassword } else { $avPassword }
            $avmSecPwd     = ConvertTo-SecureString $avmRemotePwd -AsPlainText -Force
            $avmCred       = New-Object System.Management.Automation.PSCredential($avmRemoteUser, $avmSecPwd)

            # Collect AV Manager details via PSRemoting (same logic as Get-HznAppVolumesManager)
            Write-RunspaceLog "Collecting App Volumes Manager details via PSRemoting: $avFqdn" "INFO"
            $avmData = [PSCustomObject]@{
                ServerName        = $avFqdn
                Port              = $null
                UserName          = $null
                CertificateOverride = $null
                AppVolumesVersion = ""
                ServiceStatus     = ""
                OsVersion         = ""
                NginxCertFile     = ""
                NginxKeyFile      = ""
                CertValid         = $null
                CertValidFrom     = "N/A"
                CertValidTo       = "N/A"
                GuestFreeMemMB    = $null
                GuestTotalMemMB   = $null
                LocalAdmins       = @()
                DiskFreeGB        = $null
                DiskTotalGB       = $null
                LastPatchId       = ""
                LastPatchDate     = ""
                OdbcDsnEntries    = @()
                NetIPAddress      = ""
                NetSubnet         = ""
                NetGateway        = ""
                NetDNS1           = ""
                NetDNS2           = ""
            }
            $avmRemoteSkipped = @()

            # PSRemoting block
            try {
                $remoteInfo = Invoke-Command -ComputerName $avFqdn -Credential $avmCred -ErrorAction Stop -ScriptBlock {
                    $result = @{}
                    # App Volumes Version
                    $avReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\CloudVolumes\Manager" -ErrorAction SilentlyContinue
                    if (-not $avReg) { $avReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\CloudVolumes\Manager" -ErrorAction SilentlyContinue }
                    $result.Version = if ($avReg -and $avReg.Version) { $avReg.Version } else {
                        $uninstall = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                                     Where-Object { $_.DisplayName -match 'App Volumes Manager|CloudVolumes Manager' } | Select-Object -First 1
                        if ($uninstall) { $uninstall.DisplayVersion } else { "" }
                    }
                    # Service status
                    $svc = Get-Service -Name "CVManager" -ErrorAction SilentlyContinue
                    if (-not $svc) { $svc = Get-Service -Name "svmanager" -ErrorAction SilentlyContinue }
                    $result.ServiceStatus = if ($svc) { $svc.Status.ToString() } else { "Not Found" }
                    # OS Version
                    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
                    $result.OsVersion = if ($os) { "$($os.Caption) ($($os.Version))" } else { "" }
                    # nginx.conf certificate paths
                    $nginxConf = "C:\Program Files (x86)\CloudVolumes\Manager\nginx\conf\nginx.conf"
                    $result.NginxCertFile = ""; $result.NginxKeyFile = ""
                    if (Test-Path $nginxConf) {
                        $lines = Get-Content $nginxConf -ErrorAction SilentlyContinue
                        foreach ($line in $lines) {
                            if ($line -match '^\s*ssl_certificate\s+([^;]+);')     { $result.NginxCertFile = $Matches[1].Trim() }
                            if ($line -match '^\s*ssl_certificate_key\s+([^;]+);') { $result.NginxKeyFile  = $Matches[1].Trim() }
                        }
                    }
                    # Certificate validity
                    $result.CertValidFrom = $null; $result.CertValidTo = $null; $result.CertValid = $null
                    if ($result.NginxCertFile) {
                        $certPath = $result.NginxCertFile
                        if (-not [System.IO.Path]::IsPathRooted($certPath)) {
                            $certPath = Join-Path "C:\Program Files (x86)\CloudVolumes\Manager\nginx\conf" $certPath
                        }
                        if (Test-Path $certPath) {
                            try {
                                $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certPath)
                                $result.CertValidFrom = $cert.NotBefore.ToString("yyyy-MM-dd")
                                $result.CertValidTo   = $cert.NotAfter.ToString("yyyy-MM-dd")
                                $result.CertValid     = ($cert.NotBefore -le (Get-Date)) -and ($cert.NotAfter -ge (Get-Date))
                                $cert.Dispose()
                            } catch {}
                        }
                    }
                    # Network configuration
                    $adapter = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
                    if ($adapter) {
                        $ifIndex = $adapter.InterfaceIndex
                        $ipAddr  = ($adapter.IPv4Address | Select-Object -First 1).IPAddress
                        $gateway = ($adapter.IPv4DefaultGateway | Select-Object -First 1).NextHop
                        $prefix  = (Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 | Select-Object -First 1).PrefixLength
                        $maskBin = ('1' * $prefix).PadRight(32, '0')
                        $mask    = (0..3 | ForEach-Object { [convert]::ToInt32($maskBin.Substring($_ * 8, 8), 2) }) -join '.'
                        $result.NetIP      = $ipAddr
                        $result.NetSubnet  = $mask
                        $result.NetGateway = $gateway
                        $dns = (Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4).ServerAddresses
                        $result.NetDNS1 = if ($dns.Count -ge 1) { $dns[0] } else { "" }
                        $result.NetDNS2 = if ($dns.Count -ge 2) { $dns[1] } else { "" }
                    }
                    # Local Administrators
                    $result.LocalAdmins = @()
                    try {
                        $members = net localgroup Administrators 2>$null
                        $collecting = $false; $admins = @()
                        foreach ($line in $members) {
                            if ($line -match '^---') { $collecting = $true; continue }
                            if ($collecting -and $line -match '\S' -and $line -notmatch 'Der Befehl|The command') { $admins += $line.Trim() }
                        }
                        $result.LocalAdmins = $admins
                    } catch {}
                    # ODBC System DSN entries
                    $result.OdbcDsn = @()
                    try {
                        $dsnKeys = Get-ItemProperty "HKLM:\SOFTWARE\ODBC\ODBC.INI\ODBC Data Sources" -ErrorAction SilentlyContinue
                        if ($dsnKeys) {
                            $entries = @()
                            foreach ($prop in $dsnKeys.PSObject.Properties) {
                                if ($prop.Name -notmatch '^PS') {
                                    $dsnName   = $prop.Name
                                    $dsnDriver = $prop.Value
                                    $platform  = "64-bit"
                                    $wow = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBC.INI\ODBC Data Sources" -ErrorAction SilentlyContinue
                                    if ($wow -and $wow.$dsnName) { $platform = "32-bit" }
                                    $dsnDetail = Get-ItemProperty "HKLM:\SOFTWARE\ODBC\ODBC.INI\$dsnName" -ErrorAction SilentlyContinue
                                    $dsnServer = if ($dsnDetail -and $dsnDetail.Server) { $dsnDetail.Server } else { "" }
                                    $dsnDB     = if ($dsnDetail -and $dsnDetail.Database) { $dsnDetail.Database } else { "" }
                                    $entries += [PSCustomObject]@{ Name = $dsnName; Platform = $platform; Driver = $dsnDriver; Server = $dsnServer; Database = $dsnDB }
                                }
                            }
                            $result.OdbcDsn = $entries
                        }
                    } catch {}
                    # Guest Memory
                    try {
                        $osMem = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
                        if ($osMem) {
                            $result.GuestFreeMemMB  = [math]::Round($osMem.FreePhysicalMemory / 1KB, 0)
                            $result.GuestTotalMemMB = [math]::Round($osMem.TotalVisibleMemorySize / 1KB, 0)
                        }
                    } catch {}
                    return $result
                }
                if ($remoteInfo) {
                    $avmData.AppVolumesVersion = $remoteInfo.Version
                    $avmData.ServiceStatus     = $remoteInfo.ServiceStatus
                    $avmData.OsVersion         = $remoteInfo.OsVersion
                    $avmData.NginxCertFile     = $remoteInfo.NginxCertFile
                    $avmData.NginxKeyFile      = $remoteInfo.NginxKeyFile
                    $avmData.CertValidFrom     = if ($remoteInfo.CertValidFrom) { $remoteInfo.CertValidFrom } else { "N/A" }
                    $avmData.CertValidTo       = if ($remoteInfo.CertValidTo)   { $remoteInfo.CertValidTo }   else { "N/A" }
                    $avmData.CertValid         = $remoteInfo.CertValid
                    $avmData.NetIPAddress      = $remoteInfo.NetIP
                    $avmData.NetSubnet         = $remoteInfo.NetSubnet
                    $avmData.NetGateway        = $remoteInfo.NetGateway
                    $avmData.NetDNS1           = $remoteInfo.NetDNS1
                    $avmData.NetDNS2           = $remoteInfo.NetDNS2
                    $avmData.LocalAdmins       = @($remoteInfo.LocalAdmins) | Where-Object { $_ }
                    $avmData.OdbcDsnEntries    = @($remoteInfo.OdbcDsn)
                    $avmData.GuestFreeMemMB    = $remoteInfo.GuestFreeMemMB
                    $avmData.GuestTotalMemMB   = $remoteInfo.GuestTotalMemMB
                    Write-RunspaceLog "AVM $avFqdn PSRemoting details collected successfully" "INFO"
                }
            } catch {
                Write-RunspaceLog "AVM $avFqdn remote query failed (PSRemoting): $($_.Exception.Message)" "WARN"
                $avmRemoteSkipped += "PSRemoting"
            }

            # Disk space (C:) via CIM
            $diskCim = $null
            try {
                $cimSessW = New-CimSession -ComputerName $avFqdn -Credential $avmCred -ErrorAction Stop -OperationTimeoutSec 15
                $diskCim  = Get-CimInstance -CimSession $cimSessW -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
                Remove-CimSession $cimSessW -ErrorAction SilentlyContinue
            } catch {
                try {
                    $cimOptD  = New-CimSessionOption -Protocol Dcom
                    $cimSessD = New-CimSession -ComputerName $avFqdn -SessionOption $cimOptD -Credential $avmCred -ErrorAction Stop -OperationTimeoutSec 15
                    $diskCim  = Get-CimInstance -CimSession $cimSessD -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction Stop
                    Remove-CimSession $cimSessD -ErrorAction SilentlyContinue
                } catch { $avmRemoteSkipped += "disk space" }
            }
            if ($diskCim) {
                $avmData.DiskFreeGB  = [math]::Round($diskCim.FreeSpace / 1GB, 1)
                $avmData.DiskTotalGB = [math]::Round($diskCim.Size      / 1GB, 1)
            }

            # Last Windows patch via CIM
            $patchList = $null
            try {
                $cimSessW = New-CimSession -ComputerName $avFqdn -Credential $avmCred -ErrorAction Stop -OperationTimeoutSec 20
                $patchList = Get-CimInstance -CimSession $cimSessW -ClassName Win32_QuickFixEngineering -ErrorAction Stop
                Remove-CimSession $cimSessW -ErrorAction SilentlyContinue
            } catch {
                try {
                    $cimOptD  = New-CimSessionOption -Protocol Dcom
                    $cimSessD = New-CimSession -ComputerName $avFqdn -SessionOption $cimOptD -Credential $avmCred -ErrorAction Stop -OperationTimeoutSec 20
                    $patchList = Get-CimInstance -CimSession $cimSessD -ClassName Win32_QuickFixEngineering -ErrorAction Stop
                    Remove-CimSession $cimSessD -ErrorAction SilentlyContinue
                } catch { $avmRemoteSkipped += "patches" }
            }
            if ($avmRemoteSkipped.Count -gt 0) {
                Write-RunspaceLog "AVM $avFqdn remote query skipped: $($avmRemoteSkipped -join ', ')" "WARN"
            }
            if ($patchList) {
                $topPatch = $patchList | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
                if (-not $topPatch) { $topPatch = $patchList | Sort-Object HotFixID -Descending | Select-Object -First 1 }
                if ($topPatch) {
                    $avmData.LastPatchId   = $topPatch.HotFixID
                    $avmData.LastPatchDate = if ($topPatch.InstalledOn) { $topPatch.InstalledOn.ToString("yyyy-MM-dd") } else { "" }
                }
            }

            $collectedData.AppVolumesManager = @($avmData)
            $steps = @(
                @{ Name = "App Volumes API Data";   Key = "AppVolumesData";
                   Collector = [scriptblock]{ Get-HznAppVolumesData -AvUsername $avUsername -AvPassword $avPassword } }
            )
        } else {
        $steps = @(
            @{ Name = "Connection Servers";         Key = "ConnectionServers";
               Collector = [scriptblock]{ Get-HznConnectionServers } },

            @{ Name = "vCenter Servers";            Key = "VCenterServers";
               Collector = [scriptblock]{ Get-HznVCenters } },

            @{ Name = "vCenter Health (internal)";  Key = "VCenterHealth_Internal";
               Collector = [scriptblock]{
                   try { $hzServices.VirtualCenterHealth.VirtualCenterHealth_List() } catch { @() }
               }},

            @{ Name = "Datastores";                 Key = "Datastores";
               Collector = [scriptblock]{ Get-HznDatastores $collectedData.VCenterHealth_Internal } },

            @{ Name = "ESXi Hosts";                 Key = "ESXiHosts";
               Collector = [scriptblock]{ Get-HznESXiHosts $collectedData.VCenterHealth_Internal } },

            @{ Name = "AD Domains";                 Key = "ADDomains";
               Collector = [scriptblock]{ Get-HznADDomains $hzServices } },

            @{ Name = "Gateways";                   Key = "Gateways";
               Collector = [scriptblock]{ Get-HznGateways } },

            @{ Name = "Gateway Certificates";       Key = "GatewayCertificates";
               Collector = [scriptblock]{ Get-HznGatewayCertificates } },

            @{ Name = "UAG API Data";               Key = "UagData";
               Collector = [scriptblock]{ Get-HznUagData -UagUsername $uagUsername -UagPassword $uagPassword } },

            @{ Name = "License";                    Key = "License";
               Collector = [scriptblock]{ Get-HznLicense } },

            @{ Name = "General Settings";           Key = "GeneralSettings";
               Collector = [scriptblock]{ Get-HznGeneralSettings } },

            @{ Name = "Global Policies";            Key = "GlobalPolicies";
               Collector = [scriptblock]{ Get-HznGlobalPolicies $hzServices } },

            @{ Name = "Event Database";             Key = "EventDatabase";
               Collector = [scriptblock]{ Get-HznEventDatabase } },

            @{ Name = "SAML Authenticators";        Key = "SamlAuthenticators";
               Collector = [scriptblock]{ Get-HznSamlAuthenticators } },

            @{ Name = "TrueSSO";                    Key = "TrueSSO";
               Collector = [scriptblock]{ Get-HznTrueSSO } },

            @{ Name = "Administrators";             Key = "Permissions";
               Collector = [scriptblock]{ Get-HznPermissions } },

            @{ Name = "IC Domain Accounts";         Key = "IcDomainAccounts";
               Collector = [scriptblock]{ Get-HznIcDomainAccounts } },

            @{ Name = "Environment Properties";     Key = "EnvironmentProperties";
               Collector = [scriptblock]{ Get-HznEnvironmentProperties } },

            @{ Name = "App Volumes Manager";        Key = "AppVolumesManager";
               Collector = [scriptblock]{ Get-HznAppVolumesManager } },

            @{ Name = "App Volumes API Data";       Key = "AppVolumesData";
               Collector = [scriptblock]{ Get-HznAppVolumesData -AvUsername $avUsername -AvPassword $avPassword } },

            @{ Name = "Syslog";                     Key = "Syslog";
               Collector = [scriptblock]{ Get-HznSyslog } },

            @{ Name = "Cloud Pod Architecture";     Key = "Cpa";
               Collector = [scriptblock]{ Get-HznCpa } },

            @{ Name = "Global Entitlements";        Key = "GlobalEntitlements";
               Collector = [scriptblock]{ Get-HznGlobalEntitlements } },

            @{ Name = "Local Desktop Entitlements"; Key = "LocalDesktopEntitlements";
               Collector = [scriptblock]{ Get-HznLocalDesktopEntitlements } },

            @{ Name = "Local Application Entitlements"; Key = "LocalApplicationEntitlements";
               Collector = [scriptblock]{ Get-HznLocalApplicationEntitlements } },

            @{ Name = "Desktop Pools";              Key = "DesktopPools";
               Collector = [scriptblock]{ Get-HznDesktopPools } },

            @{ Name = "RDS Farms";                  Key = "RdsFarms";
               Collector = [scriptblock]{ Get-HznRdsFarms } },

            @{ Name = "Application Pools";          Key = "ApplicationPools";
               Collector = [scriptblock]{ Get-HznApplicationPools } },

            @{ Name = "vCenter VM Counts";          Key = "VcVmInventory";
               Collector = [scriptblock]{ Get-HznVcVmInventory } },

            @{ Name = "Golden Images";              Key = "GoldenImages";
               Collector = [scriptblock]{
                   $guestCred = $null
                   if ($guestUsername -and $guestPassword) {
                       $guestSecPwd = ConvertTo-SecureString $guestPassword -AsPlainText -Force
                       $guestCred   = New-Object System.Management.Automation.PSCredential($guestUsername, $guestSecPwd)
                   }
                   # Phase 1 only — hardware/vCenter data, no guest scans yet
                   Get-HznGoldenImages $collectedData.DesktopPools $collectedData.RdsFarms $guestCred
               } },

            @{ Name = "Internal Template VMs";      Key = "InternalTemplateVMs";
               Collector = [scriptblock]{ Get-HznInternalTemplateVMs $collectedData.DesktopPools $collectedData.RdsFarms } }
        )
        }  # end if/else $avStandalone
        $totalSteps  = $steps.Count
        $currentStep = 0

        foreach ($step in $steps) {
            # Check cancellation between each step (same pattern as Phase 1)
            if ($cancelToken.Requested) {
                if ($hvServer) {
                    try { Disconnect-HVServer -Server $hvServer -Confirm:$false -ErrorAction SilentlyContinue } catch { }
                }
                if ($ignoreSsl) { [Net.ServicePointManager]::ServerCertificateValidationCallback = $null }
                $vmStartState.GotDecision.Set()   # unblock timer if waiting
                $window.Dispatcher.Invoke([Action]{
                    $controls["TxtProgressLabel"].Text = "Cancelled."
                    $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [WARN] Report generation cancelled by user.`r`n")
                    $controls["LogBox"].ScrollToEnd()
                    $controls["BtnGenerateReport"].IsEnabled = $true
                    $controls["BtnTestConnection"].IsEnabled = $true
                    $controls["BtnCancel"].IsEnabled         = $false
                })
                break
            }

            $currentStep++
            $pct      = [int](($currentStep / $totalSteps) * 100)
            $stepText = "Collecting $($step.Name)... ($currentStep/$totalSteps)"

            $window.Dispatcher.Invoke([Action]{
                $controls["ProgressBar"].Value     = $pct
                $controls["TxtProgressLabel"].Text = $stepText
                $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [INFO] $stepText`r`n")
                $controls["LogBox"].ScrollToEnd()
            })

            # Invoke collector and store result
            $result = & $step.Collector
            $collectedData[$step.Key] = $result

            # Special: after Connection Servers, capture Horizon version for report metadata
            if ($step.Key -eq "ConnectionServers" -and $result -and $result.Count -gt 0) {
                $collectedData.ReportMeta.HorizonVersion = $result[0].Version
            }

            # Special: if Horizon returned no App Volumes Manager but a manual FQDN was
            # provided, fall back to the manual entry so the AV collector still runs.
            if ($step.Key -eq "AppVolumesManager" -and (-not $result -or @($result).Count -eq 0) -and $avFqdn) {
                Write-RunspaceLog "No App Volumes Manager found via Horizon — using manual FQDN: $avFqdn" "INFO"
                $collectedData.AppVolumesManager = @(
                    [PSCustomObject]@{
                        ServerName          = $avFqdn
                        Port                = $null
                        UserName            = $null
                        CertificateOverride = $null
                    }
                )
            }
        }

        # ── Golden Image Phase 2 — Guest Scans via DispatcherTimer handshake ───
        # For powered-off VMs: Runspace populates PendingVMs, sets NeedDecision,
        # then BLOCKS on GotDecision.Wait(). The UI-thread DispatcherTimer wakes,
        # shows ShowDialog() safely (native UI thread), writes Decisions, sets
        # GotDecision — Runspace unblocks and runs sequential PowerOn/Scan/PowerOff.
        # Skipped entirely in AV-standalone mode (no Horizon → no golden images).
        if (-not $avStandalone -and -not $cancelToken.Requested -and $guestUsername -and $guestPassword) {
            $giEntries = @($collectedData["GoldenImages"])
            $offVMs    = @($giEntries | Where-Object { $_.Found -and $_.PowerState -ne "poweredOn" })

            $guestSecPwd2 = ConvertTo-SecureString $guestPassword -AsPlainText -Force
            $guestCred2   = New-Object System.Management.Automation.PSCredential($guestUsername, $guestSecPwd2)

            if ($offVMs.Count -gt 0) {
                # Fill PendingVMs and signal the UI-thread timer
                foreach ($offEntry in $offVMs) {
                    $vmStartState.PendingVMs.Add($offEntry.VmName)
                }
                Write-RunspaceLog "Golden Images: $($offVMs.Count) VM(s) off — waiting for user decisions" "INFO"
                $vmStartState.NeedDecision.Set()

                # Block Runspace thread — UI thread is free to pump messages and show dialog
                $vmStartState.GotDecision.Wait()

                # Log decisions
                foreach ($offEntry in $offVMs) {
                    $dec = $vmStartState.Decisions[$offEntry.VmName]
                    $verb = if ($dec) { "start" } else { "skip" }
                    Write-RunspaceLog "Golden Images: $($offEntry.VmName) — user chose: $verb" "INFO"
                }

                $collectedData["GoldenImages"] = Invoke-HznGoldenImageGuestScans `
                    -Entries $giEntries `
                    -GuestCredential $guestCred2 `
                    -StartDecisions $vmStartState.Decisions

            } elseif ($giEntries.Count -gt 0) {
                # All VMs already on — skip dialog, scan directly
                Write-RunspaceLog "Golden Images: all VMs powered on, running guest scans" "INFO"
                $collectedData["GoldenImages"] = Invoke-HznGoldenImageGuestScans `
                    -Entries $giEntries `
                    -GuestCredential $guestCred2 `
                    -StartDecisions @{}
            }
        }

        # Completion (only if not cancelled)
        if (-not $cancelToken.Requested) {
            # Ensure timer is never left waiting (e.g. no guest creds → no Phase 2)
            $vmStartState.GotDecision.Set()
            # Disconnect cleanly — only if we actually connected (skipped in AV-standalone mode)
            if ($hvServer) {
                try {
                    Disconnect-HVServer -Server $hvServer -Confirm:$false -ErrorAction SilentlyContinue
                } catch { }
            }

            # Disconnect vCenter if connected
            if ($viConnected) {
                try { Disconnect-VIServer -Server $vcServer -Confirm:$false -ErrorAction SilentlyContinue } catch {}
                Write-RunspaceLog "vCenter disconnected" "INFO"
            }

            # SSL cleanup
            if ($ignoreSsl) {
                [Net.ServicePointManager]::ServerCertificateValidationCallback = $null
            }

            # Step 11 — Rendering HTML report
            $window.Dispatcher.Invoke([Action]{
                $controls["ProgressBar"].Value     = 95
                $controls["TxtProgressLabel"].Text = "Rendering HTML report..."
                $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [INFO] Rendering HTML report...`r`n")
                $controls["LogBox"].ScrollToEnd()
            })

            # Filename construction — strip domain suffix, sanitize, uppercase
            $serverRaw   = $collectedData.ReportMeta.ServerName
            $serverShort = ($serverRaw -replace '\..*$', '') -replace '[^\w]', '_'
            $serverShort = $serverShort.ToUpper()
            $timestamp   = $collectedData.ReportMeta.GeneratedAt.ToString("yyyyMMdd_HHmmss")
            $reportFile  = "HorizonReport_${serverShort}_${timestamp}.html"
            $reportPath  = Join-Path $outputFolder $reportFile

            # Render and write UTF-8 no BOM
            $reportWritten = $false
            try {
                $html = New-HorizonHtmlReport -Data $collectedData -CompanyInfo $companyInfo
                $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllText($reportPath, $html, $utf8NoBom)
                $reportWritten = $true
                Write-RunspaceLog "Report saved: $reportPath" "OK"
            } catch {
                $errMsg   = $_.Exception.Message
                $errStack = $_.ScriptStackTrace
                Write-RunspaceLog "Failed to write report: $errMsg" "ERROR"
                Write-RunspaceLog "Stack: $errStack" "ERROR"
            }

            # PDF export (optional — triggered by checkbox)
            $pdfWritten = $false
            $pdfFile    = ""
            if ($reportWritten -and $exportPdf) {
                $window.Dispatcher.Invoke([Action]{
                    $controls["ProgressBar"].Value     = 97
                    $controls["TxtProgressLabel"].Text = "Exporting PDF..."
                    $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [INFO] Exporting PDF...`r`n")
                    $controls["LogBox"].ScrollToEnd()
                })

                $pdfFile = $reportFile -replace '\.html$', '.pdf'
                $pdfPath = Join-Path $outputFolder $pdfFile
                $pdfWritten = Export-HorizonPdf -HtmlPath $reportPath -PdfPath $pdfPath -ScriptRoot $moduleBasePath
            }

            # Open HTML report in Edge (optional — triggered by checkbox)
            if ($reportWritten -and $openHtml) {
                try {
                    Start-Process "msedge.exe" -ArgumentList "`"$reportPath`""
                    Write-RunspaceLog "Opened HTML report in Edge" "OK"
                } catch {
                    # Fallback: open with default browser
                    try {
                        Start-Process $reportPath
                        Write-RunspaceLog "Opened HTML report in default browser" "OK"
                    } catch {
                        Write-RunspaceLog "Could not open HTML report: $($_.Exception.Message)" "WARN"
                    }
                }
            }

            $window.Dispatcher.Invoke([Action]{
                $controls["ProgressBar"].Value     = 100
                if ($reportWritten) {
                    $statusParts = @("Report saved: $reportFile")
                    if ($pdfWritten)      { $statusParts += "PDF: $pdfFile" }
                    elseif ($exportPdf)   { $statusParts += "PDF export failed" }
                    $progressText = $statusParts -join " | "
                } else {
                    $progressText = "Report generation failed - see log"
                }
                $controls["TxtProgressLabel"].Text = $progressText
                $logLevel = if ($reportWritten) { 'OK' } else { 'ERROR' }
                $logDetail = if ($reportWritten) { "Report: $reportPath" } else { 'HTML rendering failed' }
                $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [$logLevel] $logDetail`r`n")
                $controls["LogBox"].ScrollToEnd()
                $controls["BtnGenerateReport"].IsEnabled = $true
                $controls["BtnTestConnection"].IsEnabled = $true
                $controls["BtnCancel"].IsEnabled         = $false
                $global:vmStartTimer.Stop()
            })
        }

    }).AddArgument($outputFolder).AddArgument($scriptRoot).AddArgument($window).AddArgument($controls).AddArgument($cancelToken).AddArgument($serverInput).AddArgument($finalUser).AddArgument($passwordText).AddArgument($finalDomain).AddArgument($ignoreSsl).AddArgument($vcUser).AddArgument($vcPassword).AddArgument($guestUser).AddArgument($guestPassword).AddArgument($uagUser).AddArgument($uagPassword).AddArgument($avUser).AddArgument($avPassword).AddArgument($avFqdn).AddArgument($exportPdf).AddArgument($openHtml).AddArgument($companyInfo).AddArgument($global:vmStartState)

    $global:generateJob = $ps.BeginInvoke()
})

# Cancel — sets synchronized cancellation token to stop Generate Report loop (Plan 03)
$controls["BtnCancel"].Add_Click({
    if ($global:cancelToken.Requested) { return }   # Already cancelling
    $global:cancelToken.Requested = $true
    $controls["LogBox"].AppendText("[$(Get-Date -Format 'HH:mm:ss')] [INFO] Cancellation requested...`r`n")
    $controls["LogBox"].ScrollToEnd()
    $controls["BtnCancel"].IsEnabled = $false  # Prevent double-cancel
})

# =============================================================================
# SECTION 11 — Window Loaded event
# =============================================================================

$window.Add_Loaded({
    # Load settings and pre-fill fields
    $settings = Load-Settings
    if ($settings.LastServer)       { $controls["TxtServer"].Text     = $settings.LastServer }
    if ($settings.LastUsername)     { $controls["TxtUsername"].Text   = $settings.LastUsername }
    if ($settings.LastDomain)       { $controls["TxtDomain"].Text     = $settings.LastDomain }
    if ($settings.LastVcUser)       { $controls["TxtVcUser"].Text     = $settings.LastVcUser }
    if ($settings.LastGuestUser)    { $controls["TxtGuestUser"].Text  = $settings.LastGuestUser }
    if ($settings.LastUagUser)      { $controls["TxtUagUser"].Text    = $settings.LastUagUser }
    if ($settings.LastAvUser)       { $controls["TxtAvUser"].Text     = $settings.LastAvUser }
    if ($settings.LastAvFqdn)       { $controls["TxtAvFqdn"].Text     = $settings.LastAvFqdn }
    if ($settings.LastOutputFolder) { $controls["TxtFolderPath"].Text = $settings.LastOutputFolder }
    $controls["ChkIgnoreSsl"].IsChecked        = $settings.LastIgnoreSsl
    $controls["ChkExportPdf"].IsChecked        = $settings.LastExportPdf
    $controls["ChkOpenHtml"].IsChecked         = $settings.LastOpenHtml
    $controls["ChkSaveCredentials"].IsChecked  = $settings.SaveCredentials
    # Restore encrypted passwords if Save Credentials was active
    if ($settings.SaveCredentials) {
        $pwd = Unprotect-SettingsPassword $settings.LastPassword_Enc
        if ($pwd) { $controls["PwdPassword"].Password = $pwd }
        $vcPwd = Unprotect-SettingsPassword $settings.LastVcPassword_Enc
        if ($vcPwd) { $controls["PwdVcPassword"].Password = $vcPwd }
        $gPwd = Unprotect-SettingsPassword $settings.LastGuestPassword_Enc
        if ($gPwd) { $controls["PwdGuestPassword"].Password = $gPwd }
        $uagPwd = Unprotect-SettingsPassword $settings.LastUagPassword_Enc
        if ($uagPwd) { $controls["PwdUagPassword"].Password = $uagPwd }
        $avPwd = Unprotect-SettingsPassword $settings.LastAvPassword_Enc
        if ($avPwd) { $controls["PwdAvPassword"].Password = $avPwd }
    }
    if ($settings.CompanyInfo -and $settings.CompanyInfo.Count -gt 0) {
        $global:companyInfo = $settings.CompanyInfo
    }
    # Warn if module load failed
    if ($global:moduleLoadError) {
        Write-Log "WARNING: Omnissa module load failed: $global:moduleLoadError" "WARN"
        Write-Log "Connect-HVServer will not be available. Install the Omnissa Horizon Modules." "WARN"
    }
    Write-Log "Horizon Documentation Tool started." "INFO"
})

# =============================================================================
# SECTION 12 — Show window
# =============================================================================

$window.ShowDialog() | Out-Null
