function Sync-OSDAppRepository {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [uri]$CatalogUri,

        [string[]]$Name
    )

    $sourceUri = if ($CatalogUri) { $CatalogUri } else { $script:OSDAppCatalogUri }

    if (-not $sourceUri) {
        throw 'No OSD App Catalog is configured. Run Set-OSDAppCatalog -Uri <catalog.json URL> first, or specify -CatalogUri.'
    }

    $cachePath = Get-OSDAppCachePath

    Sync-OSDAppCache `
        -ManifestUri $sourceUri `
        -CachePath $cachePath `
        -Name $Name `
        -Confirm:$false
}
