function Sync-OSDAppAdobeAcrobatUnified {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [double]$MinimumFreeSpaceGB = 3,

        [string]$PackageUri = 'https://trials.adobe.com/AdobeProducts/APRO/Acrobat_HelpX/win32/Acrobat_DC_Web_x64_WWMUI.zip'
    )

    if (Test-OSDAppWinPE) {
        throw 'Sync-OSDAppAdobeAcrobatUnified is intended for full Windows. Built-in cache refresh is deferred until the pre-install phase.'
    }

    $cachePath = Get-OSDAppCachePath
    $clientLogPath = Join-Path $cachePath 'Logs\Client.log'
    $root = Join-Path $cachePath 'BuiltIn\AdobeAcrobatUnified'
    $packagePath = Join-Path $root 'Package.zip'
    $cacheInfoPath = Join-Path $root 'CacheInfo.json'

    New-Item -ItemType Directory -Path $root -Force | Out-Null

    if (-not $PSCmdlet.ShouldProcess($root, 'Synchronize Adobe Acrobat Unified built-in cache')) { return }

    Assert-OSDAppCacheFreeSpace -CachePath $cachePath -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Operation 'Adobe Acrobat Unified cache synchronization' -LogPath $clientLogPath | Out-Null
    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'AdobeAcrobatUnified' -Event 'BuiltInSyncStart' -Message 'Synchronizing Adobe Acrobat Unified built-in cache.'

    $remoteMetadata = Get-OSDAppRemoteFileMetadata -Uri $PackageUri

    $previousCacheInfo = $null
    if (Test-Path -LiteralPath $cacheInfoPath -PathType Leaf) {
        try { $previousCacheInfo = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }

    $metadataMatches = $false
    if ((Test-Path -LiteralPath $packagePath -PathType Leaf) -and $previousCacheInfo) {
        if ($remoteMetadata.ETag -and $previousCacheInfo.RemoteETag) {
            $metadataMatches = $remoteMetadata.ETag -eq [string]$previousCacheInfo.RemoteETag
        }
        elseif ($remoteMetadata.LastModified -and $previousCacheInfo.RemoteLastModified -and $remoteMetadata.ContentLength -and $previousCacheInfo.RemoteContentLength) {
            $metadataMatches = (
                $remoteMetadata.LastModified -eq [string]$previousCacheInfo.RemoteLastModified -and
                [int64]$remoteMetadata.ContentLength -eq [int64]$previousCacheInfo.RemoteContentLength
            )
        }
    }

    if ($metadataMatches) {
        $updated = $false
        Write-Verbose 'Cached Adobe Acrobat Unified package is current. No download required.'
    }
    else {
        Save-OSDAppDownload -Uri $PackageUri -DestinationPath $packagePath -Activity 'Downloading Adobe Acrobat Unified x64 package' | Out-Null
        $updated = $true
    }

    [ordered]@{
        Id                  = 'AdobeAcrobatUnified'
        Cached              = $true
        Version             = 'Current'
        Architecture        = 'x64'
        PackageUri          = $PackageUri
        RemoteETag          = $remoteMetadata.ETag
        RemoteLastModified  = $remoteMetadata.LastModified
        RemoteContentLength = $remoteMetadata.ContentLength
        RemoteFinalUri      = $remoteMetadata.FinalUri
        SyncedAt            = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'AdobeAcrobatUnified' -Event 'BuiltInSyncComplete' -Message 'Adobe Acrobat Unified built-in cache synchronized.' -Data @{
        Architecture='x64'
        Updated=$updated
        Path=$root
    }

    [pscustomobject]@{
        PSTypeName='OSDAppClient.BuiltInCache'
        Id='AdobeAcrobatUnified'
        Version='Current'
        Architecture='x64'
        CachePath=$root
        Cached=$true
        Updated=$updated
    }
}
