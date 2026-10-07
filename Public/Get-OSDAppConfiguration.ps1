function Get-OSDAppConfiguration {
    [CmdletBinding()]
    param()

    if (-not $script:OSDAppConfiguration) {
        $script:OSDAppConfiguration = [pscustomobject]@{
            CatalogUri       = $null
            CleanupMode      = 'OnSuccess'
            CacheVolumeLabel = 'OSDCloud'
            LogPath          = '%ProgramData%\OSDApps\Logs\Runtime.log'
        }
    }

    [pscustomobject]@{
        PSTypeName       = 'OSDApps.Configuration'
        CatalogUri       = $script:OSDAppConfiguration.CatalogUri
        CleanupMode      = $script:OSDAppConfiguration.CleanupMode
        CacheVolumeLabel = $script:OSDAppConfiguration.CacheVolumeLabel
        LogPath          = $script:OSDAppConfiguration.LogPath
        Scope            = 'Session'
    }
}
