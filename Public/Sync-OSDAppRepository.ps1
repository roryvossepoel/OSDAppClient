function Sync-OSDAppRepository {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [uri]$ManifestUri,

        [string[]]$Name
    )

    $cachePath = Get-OSDAppCachePath

    Sync-OSDAppCache `
        -ManifestUri $ManifestUri `
        -CachePath $cachePath `
        -Name $Name `
        -Confirm:$false
}
