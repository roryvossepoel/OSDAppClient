function Get-OSDAppManifest {
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$Path,

        [Parameter(Mandatory, ParameterSetName = 'Uri')]
        [uri]$Uri
    )

    if ($PSCmdlet.ParameterSetName -eq 'Uri') {
        return Invoke-RestMethod -Uri $Uri -Method Get -UseBasicParsing
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Manifest not found: $Path"
    }

    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
