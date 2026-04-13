# =============================================================================
# Get-HznConnectionServers — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznConnectionServers {
    if (-not $restToken) { return @() }
    try {
        $csConfig  = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v2/connection-servers","config/v1/connection-servers")
        # v4 for health data (cert, memory, OS); v2 specifically for cs_replications (confirmed in swagger)
        $csMonV4   = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("monitor/v4/connection-servers","monitor/v3/connection-servers")
        $csMonV2   = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("monitor/v2/connection-servers","monitor/v1/connection-servers")
        if (-not $csConfig) { return @() }

        # Health map (v4/v3): cert, memory, OS, status — keyed by id
        $healthMap = @{}
        if ($csMonV4) { foreach ($m in $csMonV4) { $healthMap[$m.id] = $m } }

        # Replication map (v2): cs_replications — keyed by id
        $replMap = @{}
        if ($csMonV2) { foreach ($m in $csMonV2) { $replMap[$m.id] = $m } }

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

        return $csConfig | ForEach-Object {
            $cs      = $_
            $health  = $healthMap[$cs.id]
            $replMon = $replMap[$cs.id]

            # Replication partners from v2 monitor
            $repls = if ($replMon) { $replMon.cs_replications } else { $null }
            $replDisplay = if ($repls) {
                ($repls | ForEach-Object { "$($_.server_name): $($_.status)" }) -join ", "
            } else { "" }

            # Certificate from v4/v3 monitor
            $certData  = if ($health) { $health.certificate } else { $null }
            $certValid = if ($certData) { $certData.valid } else { $null }
            $certFrom  = & $toDate ($certData.valid_from)
            $certTo    = & $toDate ($certData.valid_to)

            # Status: prefer v4 health, fall back to v2, then config
            $status = if ($health -and $health.status)  { $health.status } `
                      elseif ($replMon -and $replMon.status) { $replMon.status } `
                      elseif ($cs.status) { $cs.status } else { "UNKNOWN" }

            # --- Remote data via C$ admin share and WMI ---
            $csHost        = $cs.name
            $lockedProps   = $null
            $localAdmins   = @()
            $diskFreeGB    = $null
            $diskTotalGB   = $null
            $lastPatchId   = ""
            $lastPatchDate = ""
            $netIPAddress  = ""
            $netSubnet     = ""
            $netGateway    = ""
            $netDNS1       = ""
            $netDNS2       = ""

            # locked.properties via PSRemoting (reads file locally on target server)
            try {
                $lockedProps = Invoke-Command -ComputerName $csHost -Credential $cred -ErrorAction Stop -ScriptBlock {
                    foreach ($p in @(
                        "$env:ProgramFiles\Omnissa\Horizon\Server\sslgateway\conf\locked.properties",
                        "$env:ProgramFiles\VMware\VMware View\Server\sslgateway\conf\locked.properties"
                    )) {
                        if (Test-Path $p) { return (Get-Content $p -Raw) }
                    }
                    return $null
                }
            } catch {}

            # Build credential for remote WMI/ADSI queries (reuse Horizon admin cred)
            $remoteSkipped = @()

            # Network configuration via PSRemoting
            try {
                $netInfo = Invoke-Command -ComputerName $csHost -Credential $cred -ErrorAction Stop -ScriptBlock {
                    # Get the adapter that has a default gateway (active NIC)
                    $adapter = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
                    if ($adapter) {
                        $ifIndex  = $adapter.InterfaceIndex
                        $ipAddr   = ($adapter.IPv4Address | Select-Object -First 1).IPAddress
                        $gateway  = ($adapter.IPv4DefaultGateway | Select-Object -First 1).NextHop
                        $prefix   = (Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 | Select-Object -First 1).PrefixLength
                        $dns      = (Get-DnsClientServerAddress -InterfaceIndex $ifIndex -AddressFamily IPv4).ServerAddresses
                        # Convert prefix length to subnet mask
                        $maskBin  = ('1' * $prefix).PadRight(32, '0')
                        $mask     = (0..3 | ForEach-Object { [convert]::ToInt32($maskBin.Substring($_ * 8, 8), 2) }) -join '.'
                        [PSCustomObject]@{
                            IP      = $ipAddr
                            Subnet  = $mask
                            Gateway = $gateway
                            DNS1    = if ($dns.Count -ge 1) { $dns[0] } else { "" }
                            DNS2    = if ($dns.Count -ge 2) { $dns[1] } else { "" }
                        }
                    }
                }
                if ($netInfo) {
                    $netIPAddress = $netInfo.IP
                    $netSubnet    = $netInfo.Subnet
                    $netGateway   = $netInfo.Gateway
                    $netDNS1      = $netInfo.DNS1
                    $netDNS2      = $netInfo.DNS2
                }
            } catch {
                $remoteSkipped += "network config"
            }

            # Local Administrators group via PSRemoting (runs locally on target server)
            try {
                $localAdmins = @(
                    Invoke-Command -ComputerName $csHost -Credential $cred -ErrorAction Stop -ScriptBlock {
                        $members = net localgroup Administrators 2>$null
                        $collecting = $false
                        foreach ($line in $members) {
                            if ($line -match '^---') { $collecting = $true; continue }
                            if ($collecting -and $line -match '\S' -and $line -notmatch 'Der Befehl|The command') {
                                $line.Trim()
                            }
                        }
                    }
                ) | Where-Object { $_ }
            } catch {
                $remoteSkipped += "local admins"
            }

            # Disk space (C:) - WS-MAN with credential, then DCOM with credential
            $diskCim = $null
            try {
                $cimSessW = New-CimSession -ComputerName $csHost -Credential $cred `
                            -ErrorAction Stop -OperationTimeoutSec 15
                $diskCim  = Get-CimInstance -CimSession $cimSessW -ClassName Win32_LogicalDisk `
                            -Filter "DeviceID='C:'" -ErrorAction Stop
                Remove-CimSession $cimSessW -ErrorAction SilentlyContinue
            } catch {
                try {
                    $cimOptD  = New-CimSessionOption -Protocol Dcom
                    $cimSessD = New-CimSession -ComputerName $csHost -SessionOption $cimOptD `
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
                $cimSessW = New-CimSession -ComputerName $csHost -Credential $cred `
                            -ErrorAction Stop -OperationTimeoutSec 20
                $patchList = Get-CimInstance -CimSession $cimSessW -ClassName Win32_QuickFixEngineering `
                             -ErrorAction Stop
                Remove-CimSession $cimSessW -ErrorAction SilentlyContinue
            } catch {
                try {
                    $cimOptD  = New-CimSessionOption -Protocol Dcom
                    $cimSessD = New-CimSession -ComputerName $csHost -SessionOption $cimOptD `
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
                Write-RunspaceLog "CS $csHost remote query skipped: $skipList (WMI access denied for $username)" "WARN"
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
                Name                = $cs.name
                Version             = $cs.version
                Enabled             = $cs.enabled
                ExternalURL         = $cs.external_url
                Tags                = if ($cs.tags) { $cs.tags -join ', ' } else { "" }
                Id                  = $cs.id
                Status              = $status
                ReplicationPartners = $replDisplay
                BrokerFreeMemMB     = if ($health) { $health.broker_free_memory  } else { $null }
                BrokerTotalMemMB    = if ($health) { $health.broker_total_memory  } else { $null }
                CertValid           = $certValid
                CertValidFrom       = $certFrom
                CertValidTo         = $certTo
                OsVersion           = if ($health) { $health.os_version } else { "" }
                LocalAdmins         = $localAdmins
                LockedProperties    = $lockedProps
                DiskFreeGB          = $diskFreeGB
                DiskTotalGB         = $diskTotalGB
                LastPatchId         = $lastPatchId
                LastPatchDate       = $lastPatchDate
                NetIPAddress        = $netIPAddress
                NetSubnet           = $netSubnet
                NetGateway          = $netGateway
                NetDNS1             = $netDNS1
                NetDNS2             = $netDNS2
            }
        }
    } catch {
        Write-RunspaceLog "WARNING: Connection Server collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

