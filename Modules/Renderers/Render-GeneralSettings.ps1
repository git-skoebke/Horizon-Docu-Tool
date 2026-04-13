# =============================================================================
# Render-GeneralSettings — New-HtmlGeneralSettingsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlGeneralSettingsSection {
    param($Settings)
    if ($null -eq $Settings) {
        return ""
    }
    $content = [System.Text.StringBuilder]::new()
    # Helper: render a row only when value is non-null/empty
    $row = { param($label, $val)
        if ($null -ne $val -and "$val" -ne "") {
            New-HtmlTableRow -Cells @((Invoke-HtmlEncode $label), (Invoke-HtmlEncode "$val"))
        }
    }

    # --- General Settings ---
    $null = $content.Append("<h4>Session &amp; Timeout</h4>")
    $genRows = @(
        (& $row "Client Max Session Timeout Policy"     $Settings.ClientMaxSessionTimeoutPolicy),
        (& $row "Client Max Session Timeout (min)"      $Settings.ClientMaxSessionTimeoutMinutes),
        (& $row "Client Idle Session Timeout Policy"    $Settings.ClientIdleSessionTimeoutPolicy),
        (& $row "Client Session Timeout (min)"          $Settings.ClientSessionTimeoutMinutes),
        (& $row "Console Session Timeout (min)"         $Settings.ConsoleSessionTimeoutMinutes),
        (& $row "API Session Timeout (min)"             $Settings.ApiSessionTimeoutMinutes),
        (& $row "Machine SSO Timeout Policy"            $Settings.MachineSsoTimeoutPolicy),
        (& $row "Application SSO Timeout Policy"        $Settings.ApplicationSsoTimeoutPolicy)
    ) | Where-Object { $_ }
    if ($genRows) { $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $genRows)) }

    $null = $content.Append("<h4>Forced Logoff &amp; Disconnect</h4>")
    $logoffRows = @(
        (& $row "Forced Logoff Timeout (min)"           $Settings.ForcedLogoffTimeoutMinutes),
        (& $row "Forced Logoff Message"                 $Settings.ForcedLogoffMessage),
        (& $row "Warn Before Forced Logoff"             $Settings.DisplayWarningBeforeForcedLogoff),
        (& $row "Disconnect Warning Time (min)"         $Settings.DisconnectWarningTime),
        (& $row "Disconnect Warning Message"            $Settings.DisconnectWarningMessage),
        (& $row "Disconnect Message"                    $Settings.DisconnectMessage)
    ) | Where-Object { $_ }
    if ($logoffRows) { $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $logoffRows)) }

    $null = $content.Append("<h4>Client &amp; Display</h4>")
    $clientRows = @(
        (& $row "Hide Domain List in Client"            $Settings.HideDomainListInClient),
        (& $row "Hide Server Info in Client"            $Settings.HideServerInformationInClient),
        (& $row "Enable Sending Domain List"            $Settings.EnableSendingDomainList),
        (& $row "Enable Automatic Status Updates"       $Settings.EnableAutomaticStatusUpdates),
        (& $row "Client Folders Enabled"                $Settings.ClientFoldersEnabled),
        (& $row "Block Restricted Clients"              $Settings.BlockRestrictedClients),
        (& $row "Enable Credential Cleanup (HTML Access)" $Settings.EnableCredentialCleanupHtmlAccess),
        (& $row "Store CAL on Client"                   $Settings.StoreCalOnClient),
        (& $row "Store CAL on Connection Server"        $Settings.StoreCalOnConnectionServer),
        (& $row "Agent Upgrade Notifications"           $Settings.AgentUpgradeNotificationsEnabled)
    ) | Where-Object { $_ }
    if ($clientRows) { $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $clientRows)) }

    $null = $content.Append("<h4>Authentication &amp; Login</h4>")
    $authRows = @(
        (& $row "Multi-Factor Re-Authentication"        $Settings.EnableMultiFactorReAuth),
        (& $row "Enable Server in Single User Mode"     $Settings.EnableServerInSingleUserMode),
        (& $row "Display Pre-Login Message"             $Settings.DisplayPreLoginMessage),
        (& $row "Display Pre-Login Admin Banner"        $Settings.DisplayPreLoginAdminBanner),
        (& $row "Admin Banner Header"                   $Settings.PreLoginAdminBannerHeader),
        (& $row "Admin Banner Message"                  $Settings.PreLoginAdminBannerMessage),
        (& $row "Helpdesk App Privacy"                  $Settings.HelpdeskAppPrivacy),
        (& $row "Password Policy Error Message"         $Settings.PasswordPolicyErrorMessage)
    ) | Where-Object { $_ }
    if ($authRows) { $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $authRows)) }

    # --- Restricted Client Data ---
    if ($Settings.RestrictedClientData -and @($Settings.RestrictedClientData).Count -gt 0) {
        $null = $content.Append("<h4>Restricted Client Versions</h4>")
        $rcRows = foreach ($rc in @($Settings.RestrictedClientData)) {
            $warnVers = if ($rc.warn_specific_versions) { ($rc.warn_specific_versions -join ", ") } else { "-" }
            New-HtmlTableRow -Cells @(
                (Invoke-HtmlEncode "$($rc.type)"),
                (Invoke-HtmlEncode $warnVers),
                (Invoke-HtmlEncode "$($rc.upgrade_type)")
            )
        }
        $null = $content.Append((New-HtmlTable -Headers @("Client Type","Warn Versions","Upgrade Type") -Rows $rcRows))
    }

    # --- Security Settings ---
    $null = $content.Append("<h4>Security</h4>")
    $secRows = @(
        (& $row "Message Security Mode"                 $Settings.MessageSecurityMode),
        (& $row "Message Security Status"               $Settings.MessageSecurityStatus),
        (& $row "Disallow Enhanced Security Mode"       $Settings.DisallowEnhancedSecurityMode),
        (& $row "Re-Auth Secure Tunnel After Interruption" $Settings.ReAuthSecureTunnel),
        (& $row "Data Recovery Password Configured"     $Settings.DataRecoveryPasswordConfigured),
        (& $row "Cert Auth Mapping Control"             $Settings.CertAuthMappingControl),
        (& $row "CRL File Max Size (KB)"                $Settings.CrlFileMaxSizeKb),
        (& $row "CRL Refresh Period (min)"              $Settings.CrlRefreshPeriodMinutes),
        (& $row "No Managed Certs"                      $Settings.NoManagedCerts),
        (& $row "Enforce Strong Auth"                   $Settings.EnforceStrongAuth)
    ) | Where-Object { $_ }
    if ($secRows) { $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $secRows)) }

    # --- Feature Settings ---
    $null = $content.Append("<h4>Features</h4>")
    $featRows = @(
        (& $row "Helpdesk Enabled"                      $Settings.EnableHelpdesk),
        (& $row "Image Management Enabled"              $Settings.EnableImageManagement),
        (& $row "Cloud Managed"                         $Settings.CloudManaged),
        (& $row "Cloud Entitlements Enabled"            $Settings.CloudEntitlementsEnabled),
        (& $row "Sysprep Domain Join"                   $Settings.EnableSysprepDomainJoin),
        (& $row "Enforce Access Path Restriction"       $Settings.EnforceAccessPathRestriction),
        (& $row "Shared Entity ID Enabled"              $Settings.SharedEntityIdEnabled),
        (& $row "SAML Key Sharing Enabled"              $Settings.SamlKeySharingEnabled)
    ) | Where-Object { $_ }
    if ($featRows) { $null = $content.Append((New-HtmlTable -Headers @("Setting","Value") -Rows $featRows)) }

    # --- Client Policies ---
    if ($Settings.ClientPolicies -and @($Settings.ClientPolicies).Count -gt 0) {
        $null = $content.Append("<h4>Client Policies</h4>")
        $cpRows = foreach ($cp in @($Settings.ClientPolicies)) {
            New-HtmlTableRow -Cells @(
                (Invoke-HtmlEncode "$($cp.policy)"),
                (Invoke-HtmlEncode "$($cp.enforcement_state)")
            )
        }
        $null = $content.Append((New-HtmlTable -Headers @("Policy","Enforcement State") -Rows $cpRows))
    }

    if ($content.Length -eq 0) {
        return ""
    }
    return New-HtmlSection -Id "general-settings" -Title "General Settings" -Content $content.ToString()
}

