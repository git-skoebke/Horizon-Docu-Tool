# =============================================================================
# Get-HznUagData — UAG REST API collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $collectedData.Gateways (IP addresses), $uagUsername, $uagPassword
#           $window, $controls (Runspace scope for logging)
#
# UAG REST API runs on port 9443. Auth is separate from Horizon (JWT login).
# Each Gateway IP gets its own login/query/logout cycle.
# =============================================================================

function Invoke-UagRestLogin {
    param(
        [string]$IpAddress,
        [string]$Username,
        [string]$Password
    )
    $uri  = "https://${IpAddress}:9443/rest/v1/jwt/login"
    $body = [ordered]@{
        username                  = $Username
        password                  = $Password
        refreshTokenExpiryInHours = 3
    } | ConvertTo-Json

    try {
        $resp = Invoke-RestMethod -Uri $uri -Method POST -Body $body `
                    -ContentType "application/json" `
                    -Headers @{ Accept = "application/json" } `
                    -SkipCertificateCheck `
                    -ErrorAction Stop
        return $resp.accessToken
    } catch {
        $httpStatus = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { "?" }
        $detail     = $_.ErrorDetails.Message
        if (-not $detail) {
            try {
                $wr     = Invoke-WebRequest -Uri $uri -Method POST -Body $body `
                              -ContentType "application/json" `
                              -Headers @{ Accept = "application/json" } `
                              -SkipCertificateCheck -ErrorAction SilentlyContinue
                $detail = $wr.Content
            } catch {
                $detail = $_.ErrorDetails.Message
            }
        }
        throw "HTTP ${httpStatus}: $detail"
    }
}

function Invoke-UagRestGet {
    param(
        [string]$IpAddress,
        [string]$Token,
        [string]$Path
    )
    $uri = "https://${IpAddress}:9443/rest/$Path"
    return Invoke-RestMethod -Uri $uri -Method GET `
               -Headers @{ Authorization = "Bearer $Token"; Accept = "application/json" } `
               -SkipCertificateCheck `
               -ErrorAction Stop
}

function Invoke-UagRestLogout {
    param(
        [string]$IpAddress,
        [string]$Token
    )
    try {
        Invoke-RestMethod -Uri "https://${IpAddress}:9443/rest/v1/jwt/invalidate" -Method DELETE `
            -Headers @{ Authorization = "Bearer $Token" } `
            -SkipCertificateCheck -ErrorAction SilentlyContinue | Out-Null
    } catch { }
}

function Get-HznUagData {
    param(
        [string]$UagUsername,
        [string]$UagPassword
    )

    if ([string]::IsNullOrEmpty($UagUsername) -or [string]::IsNullOrEmpty($UagPassword)) {
        Write-RunspaceLog "UAG: no credentials provided — skipping UAG API collection" "INFO"
        return @()
    }

    $gateways = @($collectedData["Gateways"])
    if ($gateways.Count -eq 0) {
        Write-RunspaceLog "UAG: no gateways found from Horizon — skipping UAG API collection" "INFO"
        return @()
    }

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($gw in $gateways) {
        $ip = $gw.Address
        if ([string]::IsNullOrEmpty($ip)) {
            Write-RunspaceLog "UAG: gateway '$($gw.Name)' has no IP address — skipping" "WARN"
            continue
        }

        Write-RunspaceLog "UAG: connecting to $ip (gateway: $($gw.Name))" "INFO"
        $token = $null

        try {
            $token = Invoke-UagRestLogin -IpAddress $ip -Username $UagUsername -Password $UagPassword
            Write-RunspaceLog "UAG: authenticated $ip" "INFO"
        } catch {
            Write-RunspaceLog "UAG: login failed for $ip — $($_.Exception.Message)" "WARN"
            $results.Add([PSCustomObject]@{
                GatewayName  = $gw.Name
                GatewayIP    = $ip
                LoginFailed  = $true
                General      = $null
                EdgeServices = @()
                AdminUsers   = @()
                SslCerts     = @()
                AuthMethods  = @()
            })
            continue
        }

        $general     = $null
        $edgeServices = @()
        $adminUsers  = @()
        $sslCerts    = @()
        $authMethods = @()

        # /v1/config/general
        try {
            $general = Invoke-UagRestGet -IpAddress $ip -Token $token -Path "v1/config/general"
        } catch {
            Write-RunspaceLog "UAG [$ip]: /v1/config/general failed — $($_.Exception.Message)" "WARN"
        }

        # /v1/config/edgeservice
        try {
            $edgeRaw = Invoke-UagRestGet -IpAddress $ip -Token $token -Path "v1/config/edgeservice"
            if ($edgeRaw) {
                if ($edgeRaw.edgeServiceSettingsList) {
                    $edgeServices = @($edgeRaw.edgeServiceSettingsList)
                } elseif ($edgeRaw -is [array]) {
                    $edgeServices = @($edgeRaw)
                } else {
                    $edgeServices = @($edgeRaw)
                }
            }
        } catch {
            Write-RunspaceLog "UAG [$ip]: /v1/config/edgeservice failed — $($_.Exception.Message)" "WARN"
        }

        # /v1/config/adminusers
        try {
            $adminRaw = Invoke-UagRestGet -IpAddress $ip -Token $token -Path "v1/config/adminusers"
            if ($adminRaw) {
                if ($adminRaw.AdminUsersList) {
                    $adminUsers = @($adminRaw.AdminUsersList)
                } elseif ($adminRaw -is [array]) {
                    $adminUsers = @($adminRaw)
                } else {
                    $adminUsers = @($adminRaw)
                }
            }
        } catch {
            Write-RunspaceLog "UAG [$ip]: /v1/config/adminusers failed — $($_.Exception.Message)" "WARN"
        }

        # /v1/config/certs/ssl/details/{entity} — query for known entity types
        $sslEntities = @("end_user", "admin")
        foreach ($entity in $sslEntities) {
            try {
                $certRaw = Invoke-UagRestGet -IpAddress $ip -Token $token -Path "v1/config/certs/ssl/details/$entity"
                if ($certRaw) {
                    $sslCerts += [PSCustomObject]@{
                        Entity = $entity
                        Data   = $certRaw
                    }
                }
            } catch {
                # 404 = entity not configured — silent skip; other errors logged
                $status = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
                if ($status -ne 404) {
                    Write-RunspaceLog "UAG [$ip]: /v1/config/certs/ssl/details/$entity failed — $($_.Exception.Message)" "WARN"
                }
            }
        }

        # /v1/config/authmethod
        try {
            $authRaw = Invoke-UagRestGet -IpAddress $ip -Token $token -Path "v1/config/authmethod"
            if ($authRaw) {
                if ($authRaw.authMethodSettingsList) {
                    $authMethods = @($authRaw.authMethodSettingsList)
                } elseif ($authRaw -is [array]) {
                    $authMethods = @($authRaw)
                }
            }
        } catch {
            Write-RunspaceLog "UAG [$ip]: /v1/config/authmethod failed — $($_.Exception.Message)" "WARN"
        }

        Invoke-UagRestLogout -IpAddress $ip -Token $token
        Write-RunspaceLog "UAG: completed $ip" "INFO"

        $results.Add([PSCustomObject]@{
            GatewayName  = $gw.Name
            GatewayIP    = $ip
            LoginFailed  = $false
            General      = $general
            EdgeServices = $edgeServices
            AdminUsers   = $adminUsers
            SslCerts     = $sslCerts
            AuthMethods  = $authMethods
        })
    }

    return $results.ToArray()
}
