function Get-OSDApp {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]$Name
    )

    $apps = [System.Collections.Generic.List[object]]::new()
    $cachePath = $null

    try { $cachePath = Get-OSDAppCachePath } catch { }

    $cachedPackages = @()
    if ($cachePath) {
        $cacheCatalogPath = Join-Path $cachePath 'CacheCatalog.json'
        if (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf) {
            try {
                $cacheCatalog = Get-OSDAppManifest -Path $cacheCatalogPath
                $cachedPackages = @($cacheCatalog.Packages)
            }
            catch {
                Write-Warning "Failed to read OSD Apps cache catalog '$cacheCatalogPath': $($_.Exception.Message)"
            }
        }
    }

    $onlinePackages = @()
    if ($script:OSDAppCatalogUri) {
        try {
            $response = Invoke-WebRequest -Uri $script:OSDAppCatalogUri -UseBasicParsing -ErrorAction Stop
            $onlineCatalog = $response.Content | ConvertFrom-Json -ErrorAction Stop
            $onlinePackages = @($onlineCatalog.Packages)
        }
        catch {
            Write-Verbose "Online OSD App Catalog could not be read: $($_.Exception.Message)"
        }
    }

    $hostArchitecture = Get-OSDAppHostArchitecture

    $repositoryIds = @(
        (@($onlinePackages.Id) + @($cachedPackages.Id)) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    foreach ($id in $repositoryIds) {
        $onlineCandidates = @($onlinePackages | Where-Object { $_.Id -eq $id })
        $onlinePackage = @(
            $onlineCandidates | Where-Object { ([string]$_.Architecture).ToLowerInvariant() -eq $hostArchitecture } | Select-Object -First 1
        )
        if ($onlinePackage.Count -eq 0) {
            $onlinePackage = @(
                $onlineCandidates | Where-Object { ([string]$_.Architecture).ToLowerInvariant() -eq 'any' } | Select-Object -First 1
            )
        }
        $onlinePackage = if ($onlinePackage.Count -gt 0) { $onlinePackage[0] } else { $null }

        $cached = @($cachedPackages | Where-Object { $_.Id -eq $id } | Select-Object -First 1)
        $cachedPackage = if ($cached.Count -gt 0) { $cached[0] } else { $null }

        $cachedValid = $null
        if ($cachedPackage -and $cachePath) {
            $archivePath = Join-Path $cachePath (Join-Path 'Packages' (Join-Path $id 'Package.zip'))
            $cachedValid = Test-OSDAppFileHash -Path $archivePath -ExpectedSha256 $cachedPackage.Archive.Sha256
        }

        $availability = if ($cachedPackage -and $cachedValid) {
            if ($onlinePackage) { 'Cached' } else { 'CachedOnly' }
        }
        elseif ($onlinePackage) {
            'Online'
        }
        elseif ($cachedPackage) {
            'InvalidCache'
        }
        else {
            'Unavailable'
        }

        $apps.Add([pscustomobject]@{
            PSTypeName    = 'OSDAppClient.App'
            Id            = $id
            Name          = $id
            DisplayName   = if ($onlinePackage -and $onlinePackage.DisplayName) { $onlinePackage.DisplayName } elseif ($cachedPackage) { $cachedPackage.DisplayName } else { $id }
            Source        = 'Repository'
            OnlineVersion = if ($onlinePackage) { $onlinePackage.Version } else { $null }
            CachedVersion = if ($cachedPackage) { $cachedPackage.Version } else { $null }
            Version       = if ($cachedPackage) { $cachedPackage.Version } elseif ($onlinePackage) { $onlinePackage.Version } else { $null }
            Architecture  = if ($cachedPackage) { $cachedPackage.Architecture } elseif ($onlinePackage) { $onlinePackage.Architecture } else { $null }
            Availability  = $availability
            Valid         = $cachedValid
        })
    }

    $officeCacheInfo = $null
    $teamsCacheInfo = $null
    $adobeCacheInfo = $null

    if ($cachePath) {
        foreach ($definition in @(
            @{ Id='Microsoft365Apps'; Path=(Join-Path $cachePath 'BuiltIn\Microsoft365Apps\CacheInfo.json') },
            @{ Id='Teams'; Path=(Join-Path $cachePath 'BuiltIn\Teams\CacheInfo.json') },
            @{ Id='AdobeAcrobatUnified'; Path=(Join-Path $cachePath (Join-Path 'BuiltIn\AdobeAcrobatUnified' (Join-Path $(if ($hostArchitecture -eq 'x86') { 'x86' } else { 'x64' }) 'CacheInfo.json'))) }
        )) {
            if (Test-Path -LiteralPath $definition.Path -PathType Leaf) {
                try {
                    $info = Get-Content -LiteralPath $definition.Path -Raw -Encoding UTF8 | ConvertFrom-Json
                    switch ($definition.Id) {
                        'Microsoft365Apps' { $officeCacheInfo = $info }
                        'Teams' { $teamsCacheInfo = $info }
                        'AdobeAcrobatUnified' { $adobeCacheInfo = $info }
                    }
                }
                catch { }
            }
        }
    }

    foreach ($builtIn in @(
        @{ Id='Microsoft365Apps'; DisplayName='Microsoft 365 Apps'; Info=$officeCacheInfo },
        @{ Id='Teams'; DisplayName='Microsoft Teams'; Info=$teamsCacheInfo },
        @{ Id='AdobeAcrobatUnified'; DisplayName='Adobe Acrobat Unified'; Info=$adobeCacheInfo }
    )) {
        $apps.Add([pscustomobject]@{
            PSTypeName    = 'OSDAppClient.App'
            Id            = $builtIn.Id
            Name          = $builtIn.Id
            DisplayName   = $builtIn.DisplayName
            Source        = 'BuiltIn'
            OnlineVersion = 'Current'
            CachedVersion = if ($builtIn.Info) { $builtIn.Info.Version } else { $null }
            Version       = if ($builtIn.Info) { $builtIn.Info.Version } else { 'Current' }
            Architecture  = if ($builtIn.Info -and $builtIn.Info.Architecture) { $builtIn.Info.Architecture } else { 'Auto' }
            Availability  = if ($builtIn.Info) { 'Cached' } else { 'Available' }
            Valid         = $true
        })
    }

    $result = @($apps)

    if ($Name) {
        $result = @(
            $result | Where-Object {
                $app = $_
                @($Name | Where-Object { $app.Id -like $_ -or $app.DisplayName -like $_ }).Count -gt 0
            }
        )
    }

    $result
}