# =============================================================================
# Get-HznGoldenImages — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

# -----------------------------------------------------------------------------
# Internal helper — PSRemoting guest scan for a single VM
# Returns a hashtable with IP, software versions, disk, local admins
# -----------------------------------------------------------------------------
function Invoke-GoldenImageGuestScan {
    param(
        [string]$HostName,
        [System.Management.Automation.PSCredential]$Credential
    )

    $result = @{
        IpAddresses      = @()
        HorizonAgentVer  = ""
        AppVolumesVer    = ""
        DemVer           = ""
        FsLogixVer       = ""
        VmwareToolsVer   = ""
        NvidiaDriverVer  = ""
        LastPatchDate    = ""
        SystemDiskGB     = ""
        SystemDiskFreeGB = ""
        LocalAdmins      = @()
        GuestQueryError  = ""
    }

    if ([string]::IsNullOrEmpty($HostName)) {
        $result.GuestQueryError = "No hostname provided"
        return $result
    }

    $guestScriptBlock = {
        $out = @{
            IpAddresses      = @()
            HorizonAgentVer  = ""
            AppVolumesVer    = ""
            DemVer           = ""
            FsLogixVer       = ""
            VmwareToolsVer   = ""
            NvidiaDriverVer  = ""
            LastPatchDate    = ""
            SystemDiskGB     = ""
            SystemDiskFreeGB = ""
            LocalAdmins      = @()
        }

        # --- IP Addresses (non-loopback, non-APIPA) ---
        try {
            $out.IpAddresses = @(
                Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.IPAddress -ne "127.0.0.1" -and
                    -not $_.IPAddress.StartsWith("169.254")
                } |
                Select-Object -ExpandProperty IPAddress
            )
        } catch {}

        # --- Software versions via Uninstall registry keys ---
        $uninstallPaths = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )
        $allApps = @()
        foreach ($path in $uninstallPaths) {
            try {
                $allApps += Get-ItemProperty $path -ErrorAction SilentlyContinue |
                            Where-Object { $_.DisplayName } |
                            Select-Object DisplayName, DisplayVersion
            } catch {}
        }

        # Horizon Agent
        $horizonApp = $allApps | Where-Object {
            $_.DisplayName -match "Horizon Agent" -or
            $_.DisplayName -match "VMware Horizon Agent" -or
            $_.DisplayName -match "Omnissa Horizon Agent"
        } | Select-Object -First 1
        if ($horizonApp) { $out.HorizonAgentVer = $horizonApp.DisplayVersion }

        # App Volumes Agent
        $avApp = $allApps | Where-Object {
            $_.DisplayName -match "App Volumes Agent" -or
            $_.DisplayName -match "VMware App Volumes Agent" -or
            $_.DisplayName -match "Omnissa App Volumes Agent"
        } | Select-Object -First 1
        if ($avApp) { $out.AppVolumesVer = $avApp.DisplayVersion }

        # Dynamic Environment Manager
        $demApp = $allApps | Where-Object {
            $_.DisplayName -match "Dynamic Environment Manager" -or
            $_.DisplayName -match "User Environment Manager" -or
            $_.DisplayName -match "DEM" -and $_.DisplayName -match "(Omnissa|VMware)"
        } | Select-Object -First 1
        if ($demApp) { $out.DemVer = $demApp.DisplayVersion }

        # FSLogix
        $fsLogixApp = $allApps | Where-Object {
            $_.DisplayName -match "FSLogix" -or
            $_.DisplayName -match "Microsoft FSLogix Apps"
        } | Select-Object -First 1
        if ($fsLogixApp) { $out.FsLogixVer = $fsLogixApp.DisplayVersion }

        # VMware Tools
        $toolsApp = $allApps | Where-Object {
            $_.DisplayName -match "VMware Tools" -or
            $_.DisplayName -match "Open VM Tools"
        } | Select-Object -First 1
        if ($toolsApp) { $out.VmwareToolsVer = $toolsApp.DisplayVersion }

        # NVIDIA driver / vGPU guest driver
        $nvidiaApp = $allApps | Where-Object {
            $_.DisplayName -match "NVIDIA" -and
            ($_.DisplayName -match "Graphics Driver" -or
             $_.DisplayName -match "Grafiktreiber" -or
             $_.DisplayName -match "Display Driver" -or
             $_.DisplayName -match "vGPU" -or
             $_.DisplayName -match "GRID")
        } | Sort-Object DisplayVersion -Descending | Select-Object -First 1
        if ($nvidiaApp) { $out.NvidiaDriverVer = $nvidiaApp.DisplayVersion }

        # --- Last installed patch date ---
        try {
            $lastPatch = Get-HotFix -ErrorAction SilentlyContinue |
                         Where-Object { $_.InstalledOn } |
                         Sort-Object InstalledOn -Descending |
                         Select-Object -First 1
            if ($lastPatch -and $lastPatch.InstalledOn) {
                $out.LastPatchDate = $lastPatch.InstalledOn.ToString("yyyy-MM-dd")
            }
        } catch {}

        # --- System drive (C:) capacity ---
        try {
            $cDrive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
            if ($cDrive) {
                $usedGB  = [math]::Round($cDrive.Used  / 1GB, 1)
                $freeGB  = [math]::Round($cDrive.Free  / 1GB, 1)
                $totalGB = [math]::Round(($cDrive.Used + $cDrive.Free) / 1GB, 1)
                $out.SystemDiskGB     = $totalGB
                $out.SystemDiskFreeGB = $freeGB
            }
        } catch {}

        # --- Local Administrators group members ---
        try {
            $members = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
            if (-not $members) {
                # Fallback: try German group name
                $members = Get-LocalGroupMember -Group "Administratoren" -ErrorAction SilentlyContinue
            }
            if ($members) {
                $out.LocalAdmins = @($members | ForEach-Object {
                    $n = $_.Name
                    $t = switch ($_.ObjectClass) {
                        "Group" { "Group" }
                        "User"  { "User" }
                        default { $_.ObjectClass }
                    }
                    "$n [$t]"
                })
            }
        } catch {}

        return $out
    }

    try {
        $invokeParams = @{
            ComputerName = $HostName
            ScriptBlock  = $guestScriptBlock
            ErrorAction  = "Stop"
        }
        if ($Credential) { $invokeParams.Credential = $Credential }

        $raw = Invoke-Command @invokeParams

        $result.IpAddresses      = @($raw.IpAddresses)
        $result.HorizonAgentVer  = $raw.HorizonAgentVer
        $result.AppVolumesVer    = $raw.AppVolumesVer
        $result.DemVer           = $raw.DemVer
        $result.FsLogixVer       = $raw.FsLogixVer
        $result.VmwareToolsVer   = $raw.VmwareToolsVer
        $result.NvidiaDriverVer  = $raw.NvidiaDriverVer
        $result.LastPatchDate    = $raw.LastPatchDate
        $result.SystemDiskGB     = $raw.SystemDiskGB
        $result.SystemDiskFreeGB = $raw.SystemDiskFreeGB
        $result.LocalAdmins      = @($raw.LocalAdmins)

    } catch {
        $errMsg = $_.Exception.Message
        $result.GuestQueryError = switch -Wildcard ($errMsg) {
            "*Access is denied*"           { "Access denied" }
            "*WinRM*"                      { "PSRemoting not reachable" }
            "*cannot be resolved*"         { "Hostname not resolvable" }
            "*No such host*"               { "Host not found" }
            "*timed out*"                  { "Connection timed out" }
            "*The client cannot connect*"  { "PSRemoting not enabled" }
            default                        { "Guest scan failed: $errMsg" }
        }
    }

    return $result
}

# -----------------------------------------------------------------------------
# Internal helper — Power on a VM and wait until poweredOn + VMware Tools ready
# Returns $true on success, $false on timeout/error
# -----------------------------------------------------------------------------
function Invoke-VmPowerOn {
    param(
        [string]$VmName,
        [int]$TimeoutSeconds = 300
    )
    # Returns the live $vmView object on success (caller uses it for UpdateViewData),
    # or $null on failure.
    try {
        $vmView = Get-View -ViewType VirtualMachine `
                  -Filter @{"Name" = $VmName} `
                  -Property Name,Runtime.PowerState,Guest.ToolsRunningStatus,Guest.HostName,Guest.Net `
                  -ErrorAction Stop |
                  Where-Object { $_.Name -eq $VmName } | Select-Object -First 1

        if (-not $vmView) {
            Write-RunspaceLog "Golden Images: $VmName not found in vCenter" "WARN"
            return $null
        }

        if ($vmView.Runtime.PowerState -eq "poweredOn") {
            Write-RunspaceLog "Golden Images: $VmName already powered on" "INFO"
            return $vmView
        }

        Write-RunspaceLog "Golden Images: starting VM $VmName ..." "INFO"
        $vm = Get-VM -Name $VmName -ErrorAction Stop
        Start-VM -VM $vm -ErrorAction Stop | Out-Null

        # Poll until poweredOn + VMware Tools running
        # Use UpdateViewData on the existing MoRef — bypasses filter cache
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            try {
                $vmView.UpdateViewData("Runtime.PowerState","Guest.ToolsRunningStatus","Guest.HostName","Guest.Net")
            } catch {
                Write-RunspaceLog "Golden Images: $VmName UpdateViewData failed — $($_.Exception.Message)" "WARN"
                continue
            }

            $state      = $vmView.Runtime.PowerState
            $toolsState = $vmView.Guest.ToolsRunningStatus
            Write-RunspaceLog "Golden Images: $VmName — power: $state, tools: $toolsState" "INFO"

            if ($state -eq "poweredOn" -and $toolsState -eq "guestToolsRunning") {
                Write-RunspaceLog "Golden Images: $VmName is up, VMware Tools running" "INFO"
                return $vmView
            }
        }
        Write-RunspaceLog "Golden Images: timeout waiting for $VmName — VMware Tools did not report running" "WARN"
        return $null
    } catch {
        Write-RunspaceLog "Golden Images: failed to start $VmName — $($_.Exception.Message)" "WARN"
        return $null
    }
}

# -----------------------------------------------------------------------------
# Internal helper — Wait for WinRM (TCP 5985) to become reachable.
# Waits 30 s after VM boot before first probe, then tests every 5 s.
# Returns the hostname/IP that responded, or $null on timeout.
# -----------------------------------------------------------------------------
function Wait-WinRM {
    param(
        [object]$VmView,             # Live vmView object — UpdateViewData used for hostname/IP refresh
        [string]$VmName,             # For log messages and NetBIOS fallback
        [int]$InitialWaitSeconds = 30,
        [int]$ProbeIntervalSeconds = 5,
        [int]$TimeoutSeconds = 180
    )

    Write-RunspaceLog "Golden Images: waiting ${InitialWaitSeconds}s for OS/WinRM to settle after boot..." "INFO"
    Start-Sleep -Seconds $InitialWaitSeconds

    $resolvedHostname = ""
    $resolvedIP       = ""
    $targets          = @()

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {

        # Refresh Guest properties via MoRef — bypasses filter cache
        if ($VmView) {
            try {
                $VmView.UpdateViewData("Guest.HostName","Guest.Net")
                if (-not [string]::IsNullOrEmpty($VmView.Guest.HostName)) {
                    $resolvedHostname = $VmView.Guest.HostName
                }
                if ([string]::IsNullOrEmpty($resolvedIP) -and $VmView.Guest.Net) {
                    $ip = @($VmView.Guest.Net | Where-Object { $_.IpAddress } |
                        ForEach-Object { $_.IpAddress } |
                        Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+$" -and
                                       $_ -ne "127.0.0.1" -and -not $_.StartsWith("169.254") }) |
                        Select-Object -First 1
                    if ($ip) { $resolvedIP = $ip }
                }
            } catch {}
        }

        # Build target list — hostname first, then IP, then VM name as NetBIOS fallback
        $targets = @()
        if (-not [string]::IsNullOrEmpty($resolvedHostname)) { $targets += $resolvedHostname }
        if (-not [string]::IsNullOrEmpty($resolvedIP))       { $targets += $resolvedIP }
        if ($targets.Count -eq 0 -and -not [string]::IsNullOrEmpty($VmName)) {
            $targets += $VmName   # NetBIOS fallback — often works even before vCenter reports hostname
        }

        foreach ($target in $targets) {
            try {
                $tcp = [System.Net.Sockets.TcpClient]::new()
                $ar  = $tcp.BeginConnect($target, 5985, $null, $null)
                $ok  = $ar.AsyncWaitHandle.WaitOne(2000)
                if ($ok -and $tcp.Connected) {
                    $tcp.Close()
                    Write-RunspaceLog "Golden Images: WinRM reachable on $target" "INFO"
                    return $target
                }
                $tcp.Close()
            } catch {}
        }

        $targetStr = if ($targets.Count -gt 0) { $targets -join ', ' } else { "(no targets yet)" }
        Write-RunspaceLog "Golden Images: WinRM not yet reachable [$targetStr] — retrying in ${ProbeIntervalSeconds}s..." "INFO"
        Start-Sleep -Seconds $ProbeIntervalSeconds
    }

    $targetStr = if ($targets.Count -gt 0) { $targets -join ', ' } else { "(no targets)" }
    Write-RunspaceLog "Golden Images: WinRM timed out after $($InitialWaitSeconds + $TimeoutSeconds)s [$targetStr]" "WARN"
    return $null
}

# -----------------------------------------------------------------------------
# Internal helper — Shut down a VM gracefully (guest shutdown), fall back to
# hard power-off, then wait until poweredOff
# Returns $true on success, $false on timeout/error
# -----------------------------------------------------------------------------
function Invoke-VmPowerOff {
    param(
        [string]$VmName,
        [int]$TimeoutSeconds = 240
    )
    try {
        # Always use Get-View for PowerState — Get-VM.PowerState can be stale
        $vmView = Get-View -ViewType VirtualMachine `
                  -Filter @{"Name" = $VmName} `
                  -Property Name,Runtime.PowerState `
                  -ErrorAction Stop |
                  Where-Object { $_.Name -eq $VmName } | Select-Object -First 1

        if (-not $vmView) {
            Write-RunspaceLog "Golden Images: $VmName not found in vCenter" "WARN"
            return $false
        }

        if ($vmView.Runtime.PowerState -eq "poweredOff") {
            Write-RunspaceLog "Golden Images: $VmName already powered off" "INFO"
            return $true
        }

        Write-RunspaceLog "Golden Images: shutting down VM $VmName (current state: $($vmView.Runtime.PowerState))..." "INFO"

        # ── Step 1: try graceful Guest Shutdown via VMware Tools ─────────────
        $guestShutdownSent = $false
        try {
            $vm = Get-VM -Name $VmName -ErrorAction Stop
            Stop-VMGuest -VM $vm -Confirm:$false -ErrorAction Stop | Out-Null
            $guestShutdownSent = $true
            Write-RunspaceLog "Golden Images: guest shutdown signal sent to $VmName" "INFO"
        } catch {
            Write-RunspaceLog "Golden Images: guest shutdown unavailable for $VmName ($($_.Exception.Message)) — using hard power-off" "WARN"
        }

        if (-not $guestShutdownSent) {
            # ── Step 2: hard power-off immediately, then short wait ──────────
            try {
                $vm = Get-VM -Name $VmName -ErrorAction Stop
                Stop-VM -VM $vm -Confirm:$false -Kill -ErrorAction Stop | Out-Null
                Write-RunspaceLog "Golden Images: hard power-off sent to $VmName — waiting for state confirmation" "INFO"
            } catch {
                Write-RunspaceLog "Golden Images: hard power-off failed for $VmName — $($_.Exception.Message)" "WARN"
                return $false
            }
            # Short wait after hard kill — vCenter needs a moment to reflect the state
            Start-Sleep -Seconds 8
        }

        # ── Step 3: poll until poweredOff — refresh view each iteration ──────
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5

            # Use MoRef directly for re-read to bypass name-filter cache
            try {
                $vmView.UpdateViewData("Runtime.PowerState")
                $state = $vmView.Runtime.PowerState
            } catch {
                # UpdateViewData failed — fall back to fresh Get-View
                $fresh = Get-View -ViewType VirtualMachine `
                         -Filter @{"Name" = $VmName} `
                         -Property Name,Runtime.PowerState `
                         -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -eq $VmName } | Select-Object -First 1
                $state = if ($fresh) { $fresh.Runtime.PowerState } else { "unknown" }
            }

            Write-RunspaceLog "Golden Images: $VmName power state: $state" "INFO"

            if ($state -eq "poweredOff") {
                Write-RunspaceLog "Golden Images: $VmName is powered off — ready for next VM" "INFO"
                return $true
            }

            # If graceful shutdown is taking too long — escalate to hard kill
            $elapsed = ($deadline - (Get-Date)).TotalSeconds
            if ($guestShutdownSent -and $elapsed -lt ($TimeoutSeconds - 60)) {
                Write-RunspaceLog "Golden Images: graceful shutdown taking too long for $VmName — escalating to hard power-off" "WARN"
                try {
                    $vm = Get-VM -Name $VmName -ErrorAction SilentlyContinue
                    if ($vm) { Stop-VM -VM $vm -Confirm:$false -Kill -ErrorAction SilentlyContinue | Out-Null }
                    $guestShutdownSent = $false   # switch to hard-kill wait path
                    Start-Sleep -Seconds 8
                } catch {}
            }
        }

        Write-RunspaceLog "Golden Images: power-off timeout for $VmName after ${TimeoutSeconds}s" "WARN"
        return $false

    } catch {
        Write-RunspaceLog "Golden Images: failed to shut down $VmName — $($_.Exception.Message)" "WARN"
        return $false
    }
}

# -----------------------------------------------------------------------------
# Main collector — Phase 1: collect hardware/vCenter data for all Golden Images
# Returns array of entries; entries with PowerState=poweredOff are flagged.
# Phase 2 (guest scans incl. start/stop) is done by Invoke-HznGoldenImageGuestScans.
# -----------------------------------------------------------------------------
function Get-HznGoldenImages {
    param(
        $DesktopPools,
        $RdsFarms,
        [System.Management.Automation.PSCredential]$GuestCredential
    )
    if (-not $viConnected) { return @() }
    try {
        # Build map: GoldenImage VM name -> list of pool / farm names using it
        $imagePoolMap = @{}
        foreach ($pool in @($DesktopPools)) {
            if (-not [string]::IsNullOrEmpty($pool.GoldenImage)) {
                if (-not $imagePoolMap.ContainsKey($pool.GoldenImage)) {
                    $imagePoolMap[$pool.GoldenImage] = New-Object 'System.Collections.Generic.List[string]'
                }
                [void]$imagePoolMap[$pool.GoldenImage].Add($pool.Name)
            }
        }
        foreach ($farm in @($RdsFarms)) {
            if (-not [string]::IsNullOrEmpty($farm.GoldenImage)) {
                if (-not $imagePoolMap.ContainsKey($farm.GoldenImage)) {
                    $imagePoolMap[$farm.GoldenImage] = New-Object 'System.Collections.Generic.List[string]'
                }
                [void]$imagePoolMap[$farm.GoldenImage].Add($farm.Name + " (RDS)")
            }
        }
        if ($imagePoolMap.Count -eq 0) { return @() }

        # Pre-fetch DVS portgroup MoRef -> name for NIC network resolution
        $pgKeyToName = @{}
        try {
            $pgViews = Get-View -ViewType DistributedVirtualPortgroup -Property Name -ErrorAction SilentlyContinue
            foreach ($pg in @($pgViews)) { $pgKeyToName[$pg.MoRef.Value] = $pg.Name }
        } catch {}

        # ── "Apply to all" state — persists across VM iterations ──────────────
        # $null = not yet decided, $true = always start, $false = always skip
        $result = foreach ($vmName in $imagePoolMap.Keys) {
            Write-RunspaceLog "Golden Images: collecting vCenter data for $vmName" "INFO"
            $entry = [PSCustomObject]@{
                VmName           = $vmName
                UsedByPools      = ($imagePoolMap[$vmName] -join ", ")
                vCPU             = ""
                Sockets          = ""
                CoresPerSocket   = ""
                RamGB            = ""
                Disks            = @()
                NetworkAdapters  = @()
                VgpuProfile      = ""
                SnapshotCount    = 0
                Found            = $false
                PowerState       = ""      # poweredOn / poweredOff / suspended
                # Guest scan fields (filled in Phase 2)
                GuestHostName    = ""
                IpAddresses      = @()
                HorizonAgentVer  = ""
                AppVolumesVer    = ""
                DemVer           = ""
                FsLogixVer       = ""
                VmwareToolsVer   = ""
                NvidiaDriverVer  = ""
                LastPatchDate    = ""
                SystemDiskGB     = ""
                SystemDiskFreeGB = ""
                LocalAdmins      = @()
                GuestQueryError  = ""
                GuestScanned     = $false
            }
            try {
                $vmView = Get-View -ViewType VirtualMachine `
                          -Filter @{"Name" = $vmName} `
                          -Property Name,Config.Hardware,Snapshot,Guest.Net,Guest.HostName,Runtime.PowerState `
                          -ErrorAction Stop |
                          Where-Object { $_.Name -eq $vmName } | Select-Object -First 1
                if ($vmView) {
                    $entry.Found      = $true
                    $entry.PowerState = "$($vmView.Runtime.PowerState)"
                    $hw = $vmView.Config.Hardware

                    # Guest hostname
                    if ($vmView.Guest -and -not [string]::IsNullOrEmpty($vmView.Guest.HostName)) {
                        $entry.GuestHostName = $vmView.Guest.HostName
                    }

                    # CPU topology
                    $entry.vCPU           = $hw.NumCPU
                    $entry.CoresPerSocket = if ($hw.NumCoresPerSocket -gt 0) { $hw.NumCoresPerSocket } else { 1 }
                    $entry.Sockets        = [int]($entry.vCPU / $entry.CoresPerSocket)
                    $entry.RamGB          = [math]::Round($hw.MemoryMB / 1024, 1)

                    # Disks
                    $entry.Disks = @(
                        $hw.Device | Where-Object { $_.GetType().Name -eq "VirtualDisk" } |
                        ForEach-Object {
                            $sizeGB   = [math]::Round($_.CapacityInKB / 1MB, 0)
                            $provType = "Unknown"
                            $backName = $_.Backing.GetType().Name
                            if ($backName -eq "VirtualDiskFlatVer2BackingInfo") {
                                if ($_.Backing.ThinProvisioned)  { $provType = "Thin" }
                                elseif ($_.Backing.EagerlyScrub) { $provType = "Thick Eager" }
                                else                              { $provType = "Thick Lazy" }
                            } elseif ($backName -eq "VirtualDiskSeSparseBackingInfo") {
                                $provType = "SE Sparse"
                            }
                            [PSCustomObject]@{ Label = $_.DeviceInfo.Label; SizeGB = $sizeGB; Type = $provType }
                        }
                    )

                    # Network adapters
                    $entry.NetworkAdapters = @(
                        $hw.Device | Where-Object {
                            $tn = $_.GetType().Name
                            $tn -eq "VirtualVmxnet3" -or $tn -eq "VirtualVmxnet2" -or
                            $tn -eq "VirtualE1000"   -or $tn -eq "VirtualE1000e"  -or
                            ($_.GetType().BaseType -and $_.GetType().BaseType.Name -eq "VirtualEthernetCard")
                        } | ForEach-Object {
                            $nicTypeName = switch ($_.GetType().Name) {
                                "VirtualVmxnet3" { "VMXNET3" }; "VirtualVmxnet2" { "VMXNET2" }
                                "VirtualE1000"   { "E1000"   }; "VirtualE1000e"  { "E1000e"  }
                                default          { $_.GetType().Name -replace "^Virtual","" }
                            }
                            $netName = ""
                            $bt = $_.Backing.GetType().Name
                            if ($bt -eq "VirtualEthernetCardNetworkBackingInfo") {
                                $netName = $_.Backing.DeviceName
                            } elseif ($bt -eq "VirtualEthernetCardDistributedVirtualPortBackingInfo") {
                                $pgKey = "$($_.Backing.Port.PortgroupKey)"
                                $netName = if ($pgKeyToName.ContainsKey($pgKey)) { $pgKeyToName[$pgKey] } else { $pgKey }
                            }
                            [PSCustomObject]@{ Type = $nicTypeName; Network = $netName }
                        }
                    )

                    # vGPU
                    $vgpuList = @(
                        $hw.Device | Where-Object { $_.GetType().Name -eq "VirtualPCIPassthrough" } |
                        ForEach-Object {
                            if ($_.Backing.GetType().Name -eq "VirtualPCIPassthroughVmiopBackingInfo" -and
                                -not [string]::IsNullOrEmpty($_.Backing.Vgpu)) { $_.Backing.Vgpu }
                        } | Where-Object { $_ }
                    )
                    $entry.VgpuProfile = $vgpuList -join ", "

                    # Snapshot count
                    if ($vmView.Snapshot -and $vmView.Snapshot.RootSnapshotList) {
                        $snapCount = 0
                        $stack = New-Object System.Collections.Stack
                        foreach ($s in $vmView.Snapshot.RootSnapshotList) { [void]$stack.Push($s) }
                        while ($stack.Count -gt 0) {
                            $s = $stack.Pop(); $snapCount++
                            foreach ($c in $s.ChildSnapshotList) { [void]$stack.Push($c) }
                        }
                        $entry.SnapshotCount = $snapCount
                    }

                    # vCenter IP (best-effort, no PSRemoting needed)
                    if ($vmView.Guest -and $vmView.Guest.Net) {
                        $vcIp = @($vmView.Guest.Net | Where-Object { $_.IpAddress } |
                            ForEach-Object { $_.IpAddress } |
                            Where-Object { $_ -match "^\d+\.\d+\.\d+\.\d+$" -and
                                           $_ -ne "127.0.0.1" -and -not $_.StartsWith("169.254") }) |
                            Select-Object -First 1
                        if ($vcIp) { $entry.IpAddresses = @($vcIp) }
                    }
                }
            } catch {
                Write-RunspaceLog "Golden Images: vCenter query failed for $vmName — $($_.Exception.Message)" "WARN"
            }
            $entry
        }
        return @($result)
    } catch {
        Write-RunspaceLog "WARNING: Golden Images collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

# -----------------------------------------------------------------------------
# Phase 2 — Guest scans (called AFTER the dialog decisions are collected on the
# UI thread).  $StartDecisions is a hashtable: VmName -> $true (scan) / $false (skip)
# -----------------------------------------------------------------------------
function Invoke-HznGoldenImageGuestScans {
    param(
        [object[]]$Entries,
        [System.Management.Automation.PSCredential]$GuestCredential,
        [hashtable]$StartDecisions    # VmName -> $true/$false
    )
    if (-not $GuestCredential) { return $Entries }

    foreach ($entry in $Entries) {
        $vmName      = $entry.VmName
        $startedByUs = $false

        if ($entry.PowerState -ne "poweredOn") {
            # ── VM is off — check user decision ──────────────────────────────
            $shouldStart = if ($StartDecisions.ContainsKey($vmName)) { $StartDecisions[$vmName] } else { $false }
            if (-not $shouldStart) {
                $entry.GuestQueryError = "Skipped — VM was powered off"
                $entry.GuestScanned   = $true
                continue
            }

            # Power on — returns live $vmView object on success, $null on failure
            $bootedView = Invoke-VmPowerOn -VmName $vmName
            if (-not $bootedView) {
                # VM may have partially booted — shut it down before moving on
                Write-RunspaceLog "Golden Images: $vmName failed to start — forcing power-off before next VM" "WARN"
                Invoke-VmPowerOff -VmName $vmName | Out-Null
                $entry.GuestQueryError = "VM start failed or timed out — VM has been powered off"
                $entry.GuestScanned   = $true
                continue
            }
            $startedByUs = $true

            # ── WinRM reachability probe ──────────────────────────────────────
            # Pass the live vmView so Wait-WinRM can call UpdateViewData directly
            # on the MoRef — bypasses Get-View filter cache that returns stale data.
            # VM name is passed as NetBIOS fallback if vCenter has no hostname yet.
            $winrmTarget = Wait-WinRM -VmView $bootedView `
                                      -VmName $vmName `
                                      -InitialWaitSeconds 30 `
                                      -ProbeIntervalSeconds 5 `
                                      -TimeoutSeconds 180
            if (-not $winrmTarget) {
                Write-RunspaceLog "Golden Images: $vmName WinRM not reachable — shutting down before next VM" "WARN"
                Invoke-VmPowerOff -VmName $vmName | Out-Null
                $entry.GuestQueryError = "WinRM not reachable after boot — VM has been powered off"
                $entry.GuestScanned   = $true
                continue
            }

            # Use the target that responded (hostname, IP, or NetBIOS name)
            $entry.GuestHostName = $winrmTarget
        }

        # ── Guest scan ────────────────────────────────────────────────────────
        if (-not [string]::IsNullOrEmpty($entry.GuestHostName)) {
            Write-RunspaceLog "Golden Images: guest scan for $vmName (hostname: $($entry.GuestHostName))" "INFO"
            $guestInfo = Invoke-GoldenImageGuestScan -HostName $entry.GuestHostName -Credential $GuestCredential
        } else {
            Write-RunspaceLog "Golden Images: no guest hostname for $vmName — cannot run guest scan" "WARN"
            $guestInfo = @{
                IpAddresses = $entry.IpAddresses; HorizonAgentVer = ""; AppVolumesVer = ""
                DemVer = ""; FsLogixVer = ""; VmwareToolsVer = ""; NvidiaDriverVer = ""
                LastPatchDate = ""; SystemDiskGB = ""; SystemDiskFreeGB = ""
                LocalAdmins = @(); GuestQueryError = "No hostname available"
            }
        }

        $entry.IpAddresses      = $guestInfo.IpAddresses
        $entry.HorizonAgentVer  = $guestInfo.HorizonAgentVer
        $entry.AppVolumesVer    = $guestInfo.AppVolumesVer
        $entry.DemVer           = $guestInfo.DemVer
        $entry.FsLogixVer       = $guestInfo.FsLogixVer
        $entry.VmwareToolsVer   = $guestInfo.VmwareToolsVer
        $entry.NvidiaDriverVer  = $guestInfo.NvidiaDriverVer
        $entry.LastPatchDate    = $guestInfo.LastPatchDate
        $entry.SystemDiskGB     = $guestInfo.SystemDiskGB
        $entry.SystemDiskFreeGB = $guestInfo.SystemDiskFreeGB
        $entry.LocalAdmins      = $guestInfo.LocalAdmins
        $entry.GuestQueryError  = $guestInfo.GuestQueryError
        $entry.GuestScanned     = $true

        if ($guestInfo.GuestQueryError) {
            Write-RunspaceLog "Golden Images: guest scan error for $vmName — $($guestInfo.GuestQueryError)" "WARN"
        }

        # ── Shut down if WE started it — MUST complete before next VM ────────
        if ($startedByUs) {
            Write-RunspaceLog "Golden Images: shutting down $vmName (started by scan) — waiting for full power-off" "INFO"
            $offOk = Invoke-VmPowerOff -VmName $vmName
            if ($offOk) {
                Write-RunspaceLog "Golden Images: $vmName is powered off — ready for next VM" "INFO"
            } else {
                Write-RunspaceLog "Golden Images: WARNING — $vmName may still be running, proceeding anyway" "WARN"
            }
        }
    }
    return $Entries
}

