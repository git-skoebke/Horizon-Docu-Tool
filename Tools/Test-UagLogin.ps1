#Requires -Version 7.0
<#
.SYNOPSIS
    UAG REST API Login Tester — diagnoses JWT authentication against a Unified Access Gateway.
#>

param(
    [string]$IpAddress,
    [string]$Username,
    [string]$Password
)

# --- Prompt for missing params ---
if (-not $IpAddress) { $IpAddress = Read-Host "UAG IP Address" }
if (-not $Username)  { $Username  = Read-Host "UAG Admin Username" }
if (-not $Password)  { $Password  = Read-Host -AsSecureString "UAG Admin Password" | ForEach-Object {
    [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($_)) } }

$baseUrl = "https://${IpAddress}:9443"
$uri     = "$baseUrl/rest/v1/jwt/login"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  UAG Login Test — $IpAddress" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Endpoint : $uri"
Write-Host "  Username : $Username"
Write-Host ""

$body = [ordered]@{
    username                  = $Username
    password                  = $Password
    refreshTokenExpiryInHours = 3
} | ConvertTo-Json -Compress

Write-Host "--- Request Body ---" -ForegroundColor Yellow
Write-Host $body
Write-Host ""

# --- Attempt 1: Invoke-WebRequest (gives full response even on error) ---
Write-Host "--- Attempt 1: POST $uri ---" -ForegroundColor Yellow
try {
    $resp = Invoke-WebRequest -Uri $uri -Method POST `
                -Body $body `
                -ContentType "application/json" `
                -Headers @{ Accept = "application/json" } `
                -SkipCertificateCheck `
                -ErrorAction Stop

    Write-Host "  Status  : $($resp.StatusCode) $($resp.StatusDescription)" -ForegroundColor Green
    Write-Host "  Headers :" -ForegroundColor Gray
    $resp.Headers.GetEnumerator() | ForEach-Object { Write-Host "    $($_.Key): $($_.Value)" -ForegroundColor Gray }
    Write-Host "  Body    :" -ForegroundColor Gray
    Write-Host $resp.Content

    $parsed = $resp.Content | ConvertFrom-Json -ErrorAction SilentlyContinue
    # Show all fields returned by login response
    Write-Host ""
    Write-Host "--- Parsed response fields ---" -ForegroundColor Yellow
    if ($parsed) {
        $parsed.PSObject.Properties | ForEach-Object {
            $val = if ($_.Value -and $_.Value.ToString().Length -gt 80) { $_.Value.ToString().Substring(0,80) + "..." } else { $_.Value }
            Write-Host "  $($_.Name) = $val"
        }
    } else {
        Write-Host "  (could not parse JSON)" -ForegroundColor Red
    }

    # Detect token field — some UAG versions use 'token' instead of 'access_token'
    $tokenValue = $parsed.access_token
    if (-not $tokenValue) { $tokenValue = $parsed.token }
    if (-not $tokenValue) { $tokenValue = $parsed.accessToken }

    if ($tokenValue) {
        Write-Host ""
        Write-Host "  LOGIN OK — token received." -ForegroundColor Green
        Write-Host "  Token (first 80 chars): $($tokenValue.Substring(0, [Math]::Min(80,$tokenValue.Length)))..." -ForegroundColor Green

        # --- Quick test: GET /v1/config/general with the token ---
        Write-Host ""
        Write-Host "--- Attempt 2: GET $baseUrl/rest/v1/config/general ---" -ForegroundColor Yellow
        Write-Host "  Authorization header: Bearer $($tokenValue.Substring(0,[Math]::Min(40,$tokenValue.Length)))..."
        try {
            $general = Invoke-WebRequest -Uri "$baseUrl/rest/v1/config/general" -Method GET `
                           -Headers @{ Authorization = "Bearer $tokenValue"; Accept = "application/json" } `
                           -SkipCertificateCheck -ErrorAction Stop
            Write-Host "  Status : $($general.StatusCode)" -ForegroundColor Green
            Write-Host "  Body   :" -ForegroundColor Gray
            Write-Host $general.Content
        } catch {
            $errStatus = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "N/A" }
            Write-Host "  GET /v1/config/general failed: $errStatus — $($_.Exception.Message)" -ForegroundColor Red
            $errBody = $_.ErrorDetails.Message
            if ($errBody) { Write-Host "  Response body: $errBody" -ForegroundColor Red }
        }

        # --- Logout ---
        Write-Host ""
        Write-Host "--- Logout: DELETE $baseUrl/rest/v1/jwt/invalidate ---" -ForegroundColor Yellow
        try {
            $logout = Invoke-WebRequest -Uri "$baseUrl/rest/v1/jwt/invalidate" -Method DELETE `
                          -Headers @{ Authorization = "Bearer $tokenValue"; Accept = "*/*" } `
                          -SkipCertificateCheck -ErrorAction Stop
            Write-Host "  Status : $($logout.StatusCode) — logged out." -ForegroundColor Green
        } catch {
            Write-Host "  Logout failed (non-fatal): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    } else {
        Write-Host ""
        Write-Host "  No token field found in response — cannot proceed with GET tests." -ForegroundColor Red
    }

} catch {
    $status  = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "N/A" }
    $errBody = $_.ErrorDetails.Message   # PS7 populates this from response body on 4xx/5xx

    Write-Host "  Status  : $status" -ForegroundColor Red
    Write-Host "  Error   : $($_.Exception.Message)" -ForegroundColor Red
    if ($errBody) {
        Write-Host "  Response body: $errBody" -ForegroundColor Red
    }

    # --- Connectivity check ---
    Write-Host ""
    Write-Host "--- Connectivity check: can we reach port 9443? ---" -ForegroundColor Yellow
    $tcpOk = $false
    try {
        $tcp = [System.Net.Sockets.TcpClient]::new()
        $tcp.Connect($IpAddress, 9443)
        $tcpOk = $tcp.Connected
        $tcp.Dispose()
    } catch { }
    if ($tcpOk) {
        Write-Host "  TCP 9443  : REACHABLE" -ForegroundColor Green
    } else {
        Write-Host "  TCP 9443  : NOT REACHABLE — firewall or wrong IP?" -ForegroundColor Red
    }

    # --- Try alternate endpoint paths ---
    Write-Host ""
    Write-Host "--- Trying alternate login endpoints ---" -ForegroundColor Yellow
    $altPaths = @(
        "/rest/v1/login",
        "/rest/v2/jwt/login",
        "/api/v1/jwt/login"
    )
    foreach ($altPath in $altPaths) {
        $altUri = "$baseUrl$altPath"
        Write-Host "  Trying $altUri ..." -NoNewline
        try {
            $altResp = Invoke-WebRequest -Uri $altUri -Method POST `
                           -Body $body `
                           -ContentType "application/json" `
                           -Headers @{ Accept = "application/json" } `
                           -SkipCertificateCheck -ErrorAction Stop
            Write-Host " $($altResp.StatusCode)" -ForegroundColor Green
            Write-Host "  Body: $($altResp.Content)"
        } catch {
            $altStatus = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "no response" }
            $altBody   = $_.ErrorDetails.Message
            Write-Host " $altStatus" -ForegroundColor $(if ($altStatus -eq "no response") { "Red" } else { "Yellow" })
            if ($altBody) { Write-Host "    Body: $altBody" -ForegroundColor Gray }
        }
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Test complete." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
