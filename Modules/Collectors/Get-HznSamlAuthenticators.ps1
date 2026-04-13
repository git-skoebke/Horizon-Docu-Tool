# =============================================================================
# Get-HznSamlAuthenticators — Horizon data collector
# Dot-sourced inside the Runspace scriptblock
# Requires: $restToken, $restBase, $hzServices, $window, $controls (Runspace scope)
# =============================================================================

function Get-HznSamlAuthenticators {
    if (-not $restToken) { return @() }
    try {
        $raw = Invoke-HznRestGet -Token $restToken -BaseUrl $restBase -Paths @("config/v3/saml-authenticators","config/v2/saml-authenticators","config/v1/saml-authenticators")
        if (-not $raw) { return @() }
        return @($raw) | ForEach-Object {
            [PSCustomObject]@{
                Label              = $_.label
                AuthenticatorType  = $_.authenticator_type
                AdministratorUrl   = $_.administrator_url
                MetadataUrl        = $_.metadata_url
                TriggerMode        = $_.trigger_mode
                ForceSamlAuth      = $_.force_saml_auth
                WorkspaceOneEnabled= $_.workspace_one_enabled
            }
        }
    } catch {
        Write-RunspaceLog "WARNING: SAML Authenticators collection failed: $($_.Exception.Message)" "WARN"
        return @()
    }
}

