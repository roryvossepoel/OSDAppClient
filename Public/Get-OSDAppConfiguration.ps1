function Get-OSDAppConfiguration {
    [CmdletBinding()]
    param()

    if (-not $script:OSDAppConfiguration) {
        $script:OSDAppConfiguration = [pscustomobject]@{
            CatalogUri       = $null
            CleanupMode      = 'OnSuccess'
            CacheVolumeLabel = 'OSDCloud'
            LogPath          = '%ProgramData%\OSDApps\Logs\Install.log'
        }
    }

    [pscustomobject]@{
        PSTypeName       = 'OSDAppClient.Configuration'
        CatalogUri       = $script:OSDAppConfiguration.CatalogUri
        CleanupMode      = $script:OSDAppConfiguration.CleanupMode
        CacheVolumeLabel = $script:OSDAppConfiguration.CacheVolumeLabel
        LogPath          = $script:OSDAppConfiguration.LogPath
        Scope            = 'Session'
    }
}
