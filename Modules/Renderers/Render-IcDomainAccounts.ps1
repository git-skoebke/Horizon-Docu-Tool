# =============================================================================
# Render-IcDomainAccounts — New-HtmlIcDomainAccountsSection
# Dot-sourced inside the Runspace scriptblock
# =============================================================================

function New-HtmlIcDomainAccountsSection {
    param($Accounts)
    if (-not $Accounts -or $Accounts.Count -eq 0) {
        return ""
    }
    $rows = foreach ($a in $Accounts) {
        New-HtmlTableRow -Cells @(
            (Invoke-HtmlEncode $a.UserName),
            (Invoke-HtmlEncode $a.DnsName),
            (Invoke-HtmlEncode $a.AdDomainId)
        )
    }
    $table = New-HtmlTable -Headers @("Username","DNS Name","AD Domain ID") -Rows $rows
    return New-HtmlSection -Id "ic-domain-accounts" -Title "IC Domain Accounts" -Content $table
}

