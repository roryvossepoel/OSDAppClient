function Set-OSDAppManifestRuntimeConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest
    )

    $configuration = Get-OSDAppConfiguration

    $runtime = [pscustomobject]@{
        CleanupMode      = $configuration.CleanupMode
        CacheVolumeLabel = $configuration.CacheVolumeLabel
        LogPath          = $configuration.LogPath
    }

    if ($Manifest.PSObject.Properties.Name -contains 'Runtime') {
        $Manifest.Runtime = $runtime
    }
    else {
        $Manifest | Add-Member -NotePropertyName Runtime -NotePropertyValue $runtime
    }

    $Manifest
}
