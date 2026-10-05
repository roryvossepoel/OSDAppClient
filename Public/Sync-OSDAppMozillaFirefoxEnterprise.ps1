function Sync-OSDAppMozillaFirefoxEnterprise {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Rapid','ESR')]
        [string]$Channel = 'Rapid',

        [ValidateSet('x64','x86')]
        [string]$Architecture = 'x64',

        [ValidatePattern('^[A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?$')]
        [string]$Language = 'en-US',

        [double]$MinimumFreeSpaceGB = 1,

        [string]$PackageUri
    )

    if (Test-OSDAppWinPE) {
        throw 'Sync-OSDAppMozillaFirefoxEnterprise is intended for full Windows. Built-in cache refresh is deferred until the pre-install phase.'
    }

    if (-not $PackageUri) {
        $product = if ($Channel -eq 'ESR') { 'firefox-esr-msi-latest-ssl' } else { 'firefox-msi-latest-ssl' }
        $os = if ($Architecture -eq 'x64') { 'win64' } else { 'win' }
        $PackageUri = "https://download.mozilla.org/?product=$product&os=$os&lang=$Language"
    }

    $cachePath = Get-OSDAppCachePath
    $clientLogPath = Join-Path $cachePath 'Logs\Client.log'
    $root = Join-Path $cachePath (Join-Path 'BuiltIn\MozillaFirefoxEnterprise' (Join-Path $Channel (Join-Path $Architecture $Language)))
    $packagePath = Join-Path $root 'Package.msi'
    $cacheInfoPath = Join-Path $root 'CacheInfo.json'

    New-Item -ItemType Directory -Path $root -Force | Out-Null

    if (-not $PSCmdlet.ShouldProcess($root, "Synchronize Mozilla Firefox Enterprise $Channel cache ($Architecture, $Language)")) { return }

    Assert-OSDAppCacheFreeSpace -CachePath $cachePath -MinimumFreeSpaceGB $MinimumFreeSpaceGB -Operation "Mozilla Firefox Enterprise $Channel $Architecture cache synchronization" -LogPath $clientLogPath | Out-Null
    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'MozillaFirefoxEnterprise' -Event 'BuiltInSyncStart' -Message 'Synchronizing Mozilla Firefox Enterprise built-in cache.' -Data @{ Channel=$Channel; Architecture=$Architecture; Language=$Language }

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
        Write-Verbose "Cached Mozilla Firefox Enterprise $Channel $Architecture MSI is current. No download required."
    }
    else {
        Save-OSDAppDownload -Uri $PackageUri -DestinationPath $packagePath -Activity "Downloading Mozilla Firefox Enterprise $Channel $Architecture MSI" | Out-Null
        $updated = $true
    }

    [ordered]@{
        Id                  = 'MozillaFirefoxEnterprise'
        Cached              = $true
        Version             = 'Current'
        Channel             = $Channel
        Architecture        = $Architecture
        Language            = $Language
        PackageUri          = $PackageUri
        RemoteETag          = $remoteMetadata.ETag
        RemoteLastModified  = $remoteMetadata.LastModified
        RemoteContentLength = $remoteMetadata.ContentLength
        RemoteFinalUri      = $remoteMetadata.FinalUri
        SyncedAt            = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'MozillaFirefoxEnterprise' -Event 'BuiltInSyncComplete' -Message 'Mozilla Firefox Enterprise built-in cache synchronized.' -Data @{ Channel=$Channel; Architecture=$Architecture; Language=$Language; Updated=$updated; Path=$root }

    [pscustomobject]@{
        PSTypeName='OSDAppClient.BuiltInCache'
        Id='MozillaFirefoxEnterprise'
        Version='Current'
        Channel=$Channel
        Architecture=$Architecture
        Language=$Language
        CachePath=$root
        Cached=$true
        Updated=$updated
    }
}
