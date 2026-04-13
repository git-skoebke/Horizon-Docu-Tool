# =============================================================================
# Render-PdfExport — PDF export via wkhtmltopdf (bundled) or Edge/Chrome fallback
# Dot-sourced inside the Runspace scriptblock
# Requires: Write-RunspaceLog (from RunspaceHelpers.ps1)
# =============================================================================

function Find-PdfEngine {
    <#
    .SYNOPSIS
        Locates the best available PDF engine. Prefers wkhtmltopdf (bundled or installed),
        falls back to Edge/Chrome headless. Returns hashtable with Engine and Path keys.
    #>
    param([string]$ScriptRoot)

    # 1. Bundled wkhtmltopdf (portable — shipped with the tool)
    $bundled = Join-Path $ScriptRoot "Tools\wkhtmltopdf\wkhtmltopdf.exe"
    if (Test-Path $bundled) {
        return @{ Engine = "wkhtmltopdf"; Path = $bundled }
    }

    # 2. Installed wkhtmltopdf
    foreach ($p in @(
        "$env:ProgramFiles\wkhtmltopdf\bin\wkhtmltopdf.exe",
        "${env:ProgramFiles(x86)}\wkhtmltopdf\bin\wkhtmltopdf.exe"
    )) {
        if ($p -and (Test-Path $p)) {
            return @{ Engine = "wkhtmltopdf"; Path = $p }
        }
    }

    # 3. Edge / Chrome fallback
    foreach ($p in @(
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )) {
        if ($p -and (Test-Path $p)) {
            return @{ Engine = "edge"; Path = $p }
        }
    }

    return $null
}

function Export-HorizonPdf {
    <#
    .SYNOPSIS
        Converts an HTML file to PDF. Uses wkhtmltopdf (preferred) or Edge headless (fallback).
    .PARAMETER HtmlPath
        Full path to the source HTML file.
    .PARAMETER PdfPath
        Full path for the output PDF file.
    .PARAMETER ScriptRoot
        Script root directory (for finding bundled tools).
    .OUTPUTS
        [bool] $true if PDF was created successfully, $false otherwise.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$HtmlPath,

        [Parameter(Mandatory)]
        [string]$PdfPath,

        [string]$ScriptRoot
    )

    # Find PDF engine
    $engine = Find-PdfEngine -ScriptRoot $ScriptRoot
    if (-not $engine) {
        Write-RunspaceLog "PDF export skipped: No wkhtmltopdf or Edge/Chrome found." "WARN"
        return $false
    }

    # Validate input file
    if (-not (Test-Path $HtmlPath)) {
        Write-RunspaceLog "PDF export failed: HTML file not found: $HtmlPath" "ERROR"
        return $false
    }

    $engineName = $engine.Engine
    $enginePath = $engine.Path
    $exeName    = Split-Path $enginePath -Leaf
    Write-RunspaceLog "PDF export: using $exeName ($engineName engine)" "INFO"

    try {
        if ($engineName -eq "wkhtmltopdf") {
            # wkhtmltopdf: ArgumentList as array to avoid quoting/spacing issues.
            # --enable-local-file-access is required by wkhtmltopdf 0.12.6+ for
            # loading local HTML files (without it, "C:" is parsed as a URL protocol
            # causing ProtocolUnknownError).
            $argList = @(
                "--page-size",  "A4",
                "--orientation","Landscape",
                "--margin-top", "8mm",
                "--margin-bottom","8mm",
                "--margin-left","8mm",
                "--margin-right","8mm",
                "--enable-smart-shrinking",
                "--print-media-type",
                "--no-outline",
                "--enable-local-file-access",
                "--quiet",
                $HtmlPath,
                $PdfPath
            )
        } else {
            # Edge/Chrome headless fallback
            $htmlUri  = "file:///" + $HtmlPath.Replace('\', '/')
            $argList = @(
                "--headless=new",
                "--disable-gpu",
                "--no-pdf-header-footer",
                "--print-to-pdf=$PdfPath",
                $htmlUri
            )
        }

        $process = Start-Process -FilePath $enginePath `
            -ArgumentList $argList `
            -NoNewWindow -Wait -PassThru

        Start-Sleep -Milliseconds 500

        if (Test-Path $PdfPath) {
            $pdfSize = (Get-Item $PdfPath).Length
            if ($pdfSize -gt 0) {
                $pdfSizeKB = [math]::Round($pdfSize / 1KB, 1)
                Write-RunspaceLog "PDF exported: $PdfPath ($pdfSizeKB KB)" "OK"
                return $true
            } else {
                Write-RunspaceLog "PDF export produced empty file" "ERROR"
                Remove-Item $PdfPath -Force -ErrorAction SilentlyContinue
                return $false
            }
        } else {
            Write-RunspaceLog "PDF export failed: no output file created (exit code: $($process.ExitCode))" "ERROR"
            return $false
        }
    } catch {
        Write-RunspaceLog "PDF export error: $($_.Exception.Message)" "ERROR"
        return $false
    }
}
