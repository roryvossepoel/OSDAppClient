function Sync-OSDAppRepository {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string[]]$Name
    )

    $sourceUri = (Get-OSDAppConfiguration).CatalogUri

    if (-not $sourceUri) {
        throw 'No OSD App Catalog is configured. Set CatalogUri with Set-OSDAppConfiguration first.'
    }

    $cachePath = Get-OSDAppCachePath

    Sync-OSDAppCache `
        -CatalogUri $sourceUri `
        -CachePath $cachePath `
        -Name $Name `
        -Confirm:$false
}
