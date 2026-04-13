# =============================================================================
# Render-SamlAuthenticators — New-HtmlSamlAuthenticatorsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlSamlAuthenticatorsSection {
    param($Saml)
    if (-not $Saml -or $Saml.Count -eq 0) {
        return ""
    }
    $rows = foreach ($s in $Saml) {
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $s.Label),
            (Invoke-HtmlEncode $s.AuthenticatorType),
            (Invoke-HtmlEncode $s.AdministratorUrl),
            (Invoke-HtmlEncode $s.MetadataUrl),
            (Invoke-HtmlEncode $s.TriggerMode),
            (Invoke-HtmlEncode "$($s.WorkspaceOneEnabled)")
        )
    }
    $table = New-HtmlTable -Headers @("Label","Type","Admin URL","Metadata URL","Trigger Mode","Workspace ONE") -Rows $rows
    return New-HtmlSection -Id "saml-authenticators" -Title "SAML Authenticators" -Content $table
}

