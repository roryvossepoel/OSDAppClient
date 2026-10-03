function Set-OSDAppCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [uri]$Uri
    )

    if ($Uri.Scheme -notin @('http','https')) {
        throw "OSD App Catalog must use HTTP or HTTPS. Unsupported URI scheme: $($Uri.Scheme)"
    }

    $script:OSDAppCatalogUri = $Uri

    [pscustomobject]@{
        PSTypeName = 'OSDAppClient.CatalogConfiguration'
        Uri        = $script:OSDAppCatalogUri
        Scope      = 'Session'
    }
}
