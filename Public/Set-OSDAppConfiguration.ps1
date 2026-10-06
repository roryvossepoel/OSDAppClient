function Set-OSDAppConfiguration {
    [CmdletBinding()]
    param(
        [uri]$CatalogUri,

        [ValidateSet('OnSuccess','Never')]
        [string]$CleanupMode = 'OnSuccess',

        [ValidateNotNullOrEmpty()]
        [string]$CacheVolumeLabel = 'OSDCloud',

        [ValidateNotNullOrEmpty()]
        [string]$LogPath = '%ProgramData%\OSDApps\Logs\Install.log'
    )

    if ($CatalogUri -and $CatalogUri.Scheme -notin @('http','https')) {
        throw "OSD App Catalog must use HTTP or HTTPS. Unsupported URI scheme: $($CatalogUri.Scheme)"
    }

    $script:OSDAppConfiguration = [pscustomobject]@{
        CatalogUri       = $CatalogUri
        CleanupMode      = $CleanupMode
        CacheVolumeLabel = $CacheVolumeLabel
        LogPath          = $LogPath
    }

    Get-OSDAppConfiguration
}
