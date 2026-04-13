# =============================================================================
# Get-HznAppVolumesManager — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznAppVolumesManager {
    if (-not $restToken) { return @() }
    try {
        $raw = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v2/app-volumes-manager","config/v1/app-volumes-manager")
        if (-not $raw) { return @() }

        # Convert epoch-ms or ISO string → yyyy-MM-dd
        $toDate = {
            param($v)
            if (-not $v) { return "N/A" }
            try {
                if ($v -match '^\d{10,}$') {
                    return ([datetime]'1970-01-01T00:00:00Z').AddMilliseconds([long]$v).ToLocalTime().ToString("yyyy-MM-dd")
                }
                return ([datetime]$v).ToString("yyyy-MM-dd")
            } catch { return "$v" }
        }

        return @($raw) | ForEach-Object {
            $avm = $_
            $avmHost = $avm.server_name

            # --- Remote data collection ---
            $remoteSkipped   = @()
            $netIPAddress    = ""
            $netSubnet       = ""
            $netGateway      = ""
            $netDNS1         = ""
            $netDNS2         = ""
            $avVersion       = ""
            $svcStatus       = ""
            $osVersion       = ""
            $nginxCertFile   = ""
            $nginxKeyFile    = ""
            $certValidFrom   = "N/A"
            $certValidTo     = "N/A"
            $certValid       = $null
            $guestFreeMemMB  = $null
            $guestTotalMemMB = $null
            $localAdmins     = @()
            $diskFreeGB      = $null
            $diskTotalGB     = $null
            $lastPatchId     = ""
            $lastPatchDate   = ""
            $odbcDsnEntries  = @()

            # PSRemoting block: version, service, OS, nginx cert, network, local admins, ODBC DSN
            try {
                $remoteInfo = Invoke-Command -ComputerName $avmHost -Credential $cred -ErrorAction Stop -ScriptBlock {
                    $result = @{}

                    # App Volumes Version from registry
                    $avReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\CloudVolumes\Manager" -ErrorAction SilentlyContinue
                    if (-not $avReg) {
                        $avReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\CloudVolumes\Manager" -ErrorAction SilentlyContinue
                    }
                    $result.Version = if ($avReg -and $avReg.Version) { $avReg.Version } else {
                        # Fallback: check uninstall entries
                        $uninstall = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue |
                                     Where-Object { $_.DisplayName -match 'App Volumes Manager|CloudVolumes Manager' } |
                                     Select-Object -First 1
                        if ($uninstall) { $uninstall.DisplayVersion } else { "" }
                    }

                    # Service status: svmanager (CVManager)
                    $svc = Get-Service -Name "CVManager" -ErrorAction SilentlyContinue
                    if (-not $svc) { $svc = Get-Service -Name "svmanager" -ErrorAction SilentlyContinue }
                    $result.ServiceStatus = if ($svc) { $svc.Status.ToString() } else { "Not Found" }

                    # OS Version
                    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
                    $result.OsVersion = if ($os) { "$($os.Caption) ($($os.Version))" } else { "" }

                    # nginx.conf certificate paths
                    $nginxConf = "C:\Program Files (x86)\CloudVolumes\Manager\nginx\conf\nginx.conf"
                    $result.NginxCertFile = ""
                    $result.NginxKeyFile  = ""
                    if (Test-Path $nginxConf) {
                        $lines = Get-Content $nginxConf -ErrorAction SilentlyContinue
                        foreach ($line in $lines) {
                            if ($line -match '^\s*ssl_certificate\s+([^;]+);') {
                                $result.NginxCertFile = $Matches[1].Trim()
                            }
                            if ($line -match '^\s*ssl_certificate_key\s+([^;]+);') {
                                $result.NginxKeyFile = $Matches[1].Trim()
                            }
                        }
                    }

                    # Certificate validity (read the cert file if it exists)
                    $result.CertValidFrom = $null
                    $result.CertValidTo   = $null
                    $result.CertValid     = $null
                    if ($result.NginxCertFile) {
                        # nginx paths may be relative to nginx prefix
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
                        $ifIndex  = $adapter.InterfaceIndex
                        $ipAddr   = ($adapter.IPv4Address | Select-Object -First 1).IPAddress
                        $gateway  = ($adapter.IPv4DefaultGateway | Select-Object -First 1).NextHop
                        $prefix   = (Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 | Select-Object -First 1).PrefixLength
                        $dns      = (Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4).ServerAddresses
                        $maskBin  = ('1' * $prefix).PadRight(32, '0')
                        $mask     = (0..3 | ForEach-Object { [convert]::ToInt32($maskBin.Substring($_ * 8, 8), 2) }) -join '.'
                        $result.NetIP      = $ipAddr
                        $result.NetSubnet  = $mask
                        $result.NetGateway = $gateway
                        $result.NetDNS1    = if ($dns.Count -ge 1) { $dns[0] } else { "" }
                        $result.NetDNS2    = if ($dns.Count -ge 2) { $dns[1] } else { "" }
                    }

                    # Local Administrators
                    $result.LocalAdmins = @()
                    try {
                        $members = net localgroup Administrators 2>$null
                        $collecting = $false
                        $admins = @()
                        foreach ($line in $members) {
                            if ($line -match '^---') { $collecting = $true; continue }
                            if ($collecting -and $line -match '\S' -and $line -notmatch 'Der Befehl|The command') {
                                $admins += $line.Trim()
                            }
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
                                    # Check if 64-bit
                                    $platform = "64-bit"
                                    $wow = Get-ItemProperty "HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBC.INI\ODBC Data Sources" -ErrorAction SilentlyContinue
                                    if ($wow -and $wow.$dsnName) { $platform = "32-bit" }
                                    # Get server from DSN config
                                    $dsnDetail = Get-ItemProperty "HKLM:\SOFTWARE\ODBC\ODBC.INI\$dsnName" -ErrorAction SilentlyContinue
                                    $dsnServer = if ($dsnDetail -and $dsnDetail.Server) { $dsnDetail.Server } else { "" }
                                    $dsnDB     = if ($dsnDetail -and $dsnDetail.Database) { $dsnDetail.Database } else { "" }
                                    $entries += [PSCustomObject]@{
                                        Name     = $dsnName
                                        Platform = $platform
                                        Driver   = $dsnDriver
                                        Server   = $dsnServer
                                        Database = $dsnDB
                                    }
                                }
                            }
                            $result.OdbcDsn = $entries
                        }
                    } catch {}

                    # Guest Memory (physical RAM)
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
                    $avVersion       = $remoteInfo.Version
                    $svcStatus       = $remoteInfo.ServiceStatus
                    $osVersion       = $remoteInfo.OsVersion
                    $nginxCertFile   = $remoteInfo.NginxCertFile
                    $nginxKeyFile    = $remoteInfo.NginxKeyFile
                    $certValidFrom   = if ($remoteInfo.CertValidFrom) { $remoteInfo.CertValidFrom } else { "N/A" }
                    $certValidTo     = if ($remoteInfo.CertValidTo)   { $remoteInfo.CertValidTo }   else { "N/A" }
                    $certValid       = $remoteInfo.CertValid
                    $netIPAddress    = $remoteInfo.NetIP
                    $netSubnet       = $remoteInfo.NetSubnet
                    $netGateway      = $remoteInfo.NetGateway
                    $netDNS1         = $remoteInfo.NetDNS1
                    $netDNS2         = $remoteInfo.NetDNS2
                    $localAdmins     = @($remoteInfo.LocalAdmins) | Where-Object { $_ }
                    $odbcDsnEntries  = @($remoteInfo.OdbcDsn)
                    $guestFreeMemMB  = $remoteInfo.GuestFreeMemMB
                    $guestTotalMemMB = $remoteInfo.GuestTotalMemMB
                }
            } catch {
                Write-RunspaceLog "AVM $avmHost remote query failed (PSRemoting): $($_.Exception.Message)" "WARN"
                $remoteSkipped += "PSRemoting"
            }

            # Disk space (C:) - WS-MAN with credential, then DCOM with credential
            $diskCim = $null
            try {
                $cimSessW = New-CimSession -ComputerName $avmHost -Credential $cred `
                            -ErrorAction Stop -OperationTimeoutSec 15
                $diskCim  = Get-CimInstance -CimSession $cimSessW -ClassName Win32_LogicalDisk `
                            -Filter "DeviceID='C:'" -ErrorAction Stop
                Remove-CimSession $cimSessW -ErrorAction SilentlyContinue
            } catch {
                try {
                    $cimOptD  = New-CimSessionOption -Protocol Dcom
                    $cimSessD = New-CimSession -ComputerName $avmHost -SessionOption $cimOptD `
                                -Credential $cred -ErrorAction Stop -OperationTimeoutSec 15
                    $diskCim  = Get-CimInstance -CimSession $cimSessD -ClassName Win32_LogicalDisk `
                                -Filter "DeviceID='C:'" -ErrorAction Stop
                    Remove-CimSession $cimSessD -ErrorAction SilentlyContinue
                } catch {
                    $remoteSkipped += "disk space"
                }
            }
            if ($diskCim) {
                $diskFreeGB  = [math]::Round($diskCim.FreeSpace / 1GB, 1)
                $diskTotalGB = [math]::Round($diskCim.Size      / 1GB, 1)
            }

            # Last Windows patch - WS-MAN with credential, then DCOM with credential
            $patchList = $null
            try {
                $cimSessW = New-CimSession -ComputerName $avmHost -Credential $cred `
                            -ErrorAction Stop -OperationTimeoutSec 20
                $patchList = Get-CimInstance -CimSession $cimSessW -ClassName Win32_QuickFixEngineering `
                             -ErrorAction Stop
                Remove-CimSession $cimSessW -ErrorAction SilentlyContinue
            } catch {
                try {
                    $cimOptD  = New-CimSessionOption -Protocol Dcom
                    $cimSessD = New-CimSession -ComputerName $avmHost -SessionOption $cimOptD `
                                -Credential $cred -ErrorAction Stop -OperationTimeoutSec 20
                    $patchList = Get-CimInstance -CimSession $cimSessD -ClassName Win32_QuickFixEngineering `
                                 -ErrorAction Stop
                    Remove-CimSession $cimSessD -ErrorAction SilentlyContinue
                } catch {
                    $remoteSkipped += "patches"
                }
            }
            if ($remoteSkipped.Count -gt 0) {
                $skipList = $remoteSkipped -join ", "
                Write-RunspaceLog "AVM $avmHost remote query skipped: $skipList" "WARN"
            }
            if ($patchList) {
                $topPatch = $patchList | Where-Object { $_.InstalledOn } |
                            Sort-Object InstalledOn -Descending | Select-Object -First 1
                if (-not $topPatch) {
                    $topPatch = $patchList | Sort-Object HotFixID -Descending | Select-Object -First 1
                }
                if ($topPatch) {
                    $lastPatchId   = $topPatch.HotFixID
                    $lastPatchDate = if ($topPatch.InstalledOn) { $topPatch.InstalledOn.ToString("yyyy-MM-dd") } else { "" }
                }
            }

            [PSCustomObject]@{
                ServerName       = $avm.server_name
                Port             = $avm.port
                UserName         = $avm.username
                AppVolumesVersion = $avVersion
                ServiceStatus    = $svcStatus
                OsVersion        = $osVersion
                NginxCertFile    = $nginxCertFile
                NginxKeyFile     = $nginxKeyFile
                CertValid        = $certValid
                CertValidFrom    = $certValidFrom
                CertValidTo      = $certValidTo
                GuestFreeMemMB   = $guestFreeMemMB
                GuestTotalMemMB  = $guestTotalMemMB
                LocalAdmins      = $localAdmins
                DiskFreeGB       = $diskFreeGB
                DiskTotalGB      = $diskTotalGB
                LastPatchId      = $lastPatchId
                LastPatchDate    = $lastPatchDate
                OdbcDsnEntries   = $odbcDsnEntries
                NetIPAddress     = $netIPAddress
                NetSubnet        = $netSubnet
                NetGateway       = $netGateway
                NetDNS1          = $netDNS1
                NetDNS2          = $netDNS2
            }
        }
    } catch {
        Write-RunspaceLog "WARNING: App Volumes Manager collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}
