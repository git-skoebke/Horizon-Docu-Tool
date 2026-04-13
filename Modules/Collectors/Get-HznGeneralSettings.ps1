# =============================================================================
# Get-HznGeneralSettings — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznGeneralSettings {
    if (-not $restToken) { return $null }
    try {
        $raw = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @(
            "config/v7/settings","config/v6/settings","config/v5/settings","config/v4/settings"
        )
        if (-not $raw) { return $null }
        $gs  = $raw.general_settings
        $sec = $raw.security_settings
        $fs  = $raw.feature_settings
        $cs  = $raw.client_settings
        return [PSCustomObject]@{
            # General
            ClientMaxSessionTimeoutPolicy    = if ($gs) { "$($gs.client_max_session_timeout_policy)" } else { "" }
            ClientMaxSessionTimeoutMinutes   = if ($gs) { "$($gs.client_max_session_timeout_minutes)" } else { "" }
            ClientIdleSessionTimeoutPolicy   = if ($gs) { "$($gs.client_idle_session_timeout_policy)" } else { "" }
            ClientSessionTimeoutMinutes      = if ($gs) { "$($gs.client_session_timeout_minutes)" } else { "" }
            ConsoleSessionTimeoutMinutes     = if ($gs) { "$($gs.console_session_timeout_minutes)" } else { "" }
            ApiSessionTimeoutMinutes         = if ($gs) { "$($gs.api_session_timeout_minutes)" } else { "" }
            DisplayPreLoginMessage           = if ($gs) { "$($gs.display_pre_login_message)" } else { "" }
            EnableServerInSingleUserMode     = if ($gs) { "$($gs.enable_server_in_single_user_mode)" } else { "" }
            EnableAutomaticStatusUpdates     = if ($gs) { "$($gs.enable_automatic_status_updates)" } else { "" }
            EnableSendingDomainList          = if ($gs) { "$($gs.enable_sending_domain_list)" } else { "" }
            EnableCredentialCleanupHtmlAccess = if ($gs) { "$($gs.enable_credential_cleanup_for_htmlaccess)" } else { "" }
            HideServerInformationInClient    = if ($gs) { "$($gs.hide_server_information_in_client)" } else { "" }
            HideDomainListInClient           = if ($gs) { "$($gs.hide_domain_list_in_client)" } else { "" }
            DisplayWarningBeforeForcedLogoff = if ($gs) { "$($gs.display_warning_before_forced_logoff)" } else { "" }
            ForcedLogoffTimeoutMinutes       = if ($gs) { "$($gs.forced_logoff_timeout_minutes)" } else { "" }
            ForcedLogoffMessage              = if ($gs) { "$($gs.forced_logoff_message)" } else { "" }
            EnableMultiFactorReAuth          = if ($gs) { "$($gs.enable_multi_factor_re_authentication)" } else { "" }
            BlockRestrictedClients           = if ($gs) { "$($gs.block_restricted_clients)" } else { "" }
            DisplayPreLoginAdminBanner       = if ($gs) { "$($gs.display_pre_login_admin_banner)" } else { "" }
            PreLoginAdminBannerHeader        = if ($gs) { "$($gs.pre_login_admin_banner_header)" } else { "" }
            PreLoginAdminBannerMessage       = if ($gs) { "$($gs.pre_login_admin_banner_message)" } else { "" }
            ClientFoldersEnabled             = if ($gs) { "$($gs.client_folders_enabled)" } else { "" }
            DisconnectWarningTime            = if ($gs) { "$($gs.disconnect_warning_time)" } else { "" }
            DisconnectWarningMessage         = if ($gs) { "$($gs.disconnect_warning_message)" } else { "" }
            DisconnectMessage                = if ($gs) { "$($gs.disconnect_message)" } else { "" }
            PasswordPolicyErrorMessage       = if ($gs) { "$($gs.password_policy_error_message)" } else { "" }
            HelpdeskAppPrivacy               = if ($gs) { "$($gs.helpdesk_app_privacy)" } else { "" }
            AgentUpgradeNotificationsEnabled = if ($gs) { "$($gs.agent_upgrade_notifications_enabled)" } else { "" }
            MachineSsoTimeoutPolicy          = if ($gs) { "$($gs.machine_sso_timeout_policy)" } else { "" }
            ApplicationSsoTimeoutPolicy      = if ($gs) { "$($gs.application_sso_timeout_policy)" } else { "" }
            StoreCalOnConnectionServer       = if ($gs) { "$($gs.store_cal_on_connection_server)" } else { "" }
            StoreCalOnClient                 = if ($gs) { "$($gs.store_cal_on_client)" } else { "" }
            # Restricted Client Data
            RestrictedClientData             = if ($gs) { $gs.restricted_client_data_v3 } else { $null }
            # Security
            ReAuthSecureTunnel               = if ($sec) { "$($sec.re_auth_secure_tunnel_after_interruption)" } else { "" }
            MessageSecurityMode              = if ($sec) { "$($sec.message_security_mode)" } else { "" }
            MessageSecurityStatus            = if ($sec) { "$($sec.message_security_status)" } else { "" }
            DataRecoveryPasswordConfigured   = if ($sec) { "$($sec.data_recovery_password_configured)" } else { "" }
            DisallowEnhancedSecurityMode     = if ($sec) { "$($sec.disallow_enhanced_security_mode)" } else { "" }
            CertAuthMappingControl           = if ($sec -and $sec.cert_auth_mapping_control) { ($sec.cert_auth_mapping_control -join ", ") } else { "" }
            CrlFileMaxSizeKb                 = if ($sec) { "$($sec.crl_file_max_size_kb)" } else { "" }
            CrlRefreshPeriodMinutes          = if ($sec) { "$($sec.crl_refresh_period_minutes)" } else { "" }
            NoManagedCerts                   = if ($sec) { "$($sec.no_managed_certs)" } else { "" }
            EnforceStrongAuth                = if ($sec) { "$($sec.enforce_strong_auth)" } else { "" }
            # Feature
            EnableHelpdesk                   = if ($fs) { "$($fs.enable_helpdesk)" } else { "" }
            EnableImageManagement            = if ($fs) { "$($fs.enable_image_management)" } else { "" }
            CloudManaged                     = if ($fs) { "$($fs.cloud_managed)" } else { "" }
            EnableSysprepDomainJoin          = if ($fs) { "$($fs.enable_sysprep_domain_join)" } else { "" }
            CloudEntitlementsEnabled         = if ($fs) { "$($fs.cloud_entitlements_enabled)" } else { "" }
            EnforceAccessPathRestriction     = if ($fs) { "$($fs.enforce_access_path_restriction)" } else { "" }
            SharedEntityIdEnabled            = if ($fs) { "$($fs.shared_entity_id_enabled)" } else { "" }
            SamlKeySharingEnabled            = if ($fs) { "$($fs.samlkey_sharing_enabled)" } else { "" }
            # Client
            ClientPolicies                   = if ($cs) { $cs.client_policies } else { $null }
        }
    } catch {
        Write-RunspaceLog "WARNING: General Settings collection failed: $($_.Exception.Message)" "WARN"
        return $null
    }
}

