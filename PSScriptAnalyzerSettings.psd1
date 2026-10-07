@{
    Severity = @('Error','Warning')

    ExcludeRules = @(
        # OSDApps intentionally uses Write-Host only through its console helper
        # for deployment-oriented interactive output.
        'PSAvoidUsingWriteHost'
    )
}
