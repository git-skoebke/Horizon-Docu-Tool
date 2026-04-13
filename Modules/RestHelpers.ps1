# =============================================================================
# REST API Helpers — Authentication and generic GET requests
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function Get-HznRestToken {
    param($Server, $Username, $Password, $Domain)
    $body = [ordered]@{ username = $Username; password = $Password; domain = $Domain } | ConvertTo-Json
    $resp = Invoke-RestMethod -Uri "https://$Server/rest/login" -Method POST `
                -Body $body -ContentType "application/json" -ErrorAction Stop
    return $resp.access_token
}

function Invoke-HznRestGet {
    param([string]$Token, [string]$BaseUrl, [string[]]$Paths)
    foreach ($path in $Paths) {
        try {
            return Invoke-RestMethod -Uri "$BaseUrl/$path" `
                -Headers @{ Authorization = "Bearer $Token" } -ErrorAction Stop
        } catch { }
    }
    return $null
}
