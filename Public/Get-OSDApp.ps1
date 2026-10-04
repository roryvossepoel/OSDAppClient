function Get-OSDApp {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]$Name
    )

    $apps = [System.Collections.Generic.List[object]]::new()

    $cachePath = $null
    try {
        $cachePath = Get-OSDAppCachePath
    }
    catch {
        Write-Verbose 'No OSDCloud volume was found. Returning built-in applications only.'
    }

    if ($cachePath) {
        $manifestPath = Join-Path $cachePath 'CacheManifest.json'

        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            $manifest = Get-OSDAppManifest -Path $manifestPath

            foreach ($package in @($manifest.Packages)) {
                $apps.Add([pscustomobject]@{
                    PSTypeName   = 'OSDAppClient.App'
                    Id           = $package.Id
                    Name         = $package.Id
                    DisplayName  = $package.DisplayName
                    Version      = $package.Version
                    Architecture = $package.Architecture
                    Source       = 'Repository'
                    Availability = 'Cached'
                    Valid        = (Test-OSDAppFileHash -Path (Join-Path $cachePath (Join-Path 'Packages' (Join-Path $package.Id 'Package.zip'))) -ExpectedSha256 $package.Archive.Sha256)
                })
            }
        }
    }

    $officeCacheInfo = $null
    $teamsCacheInfo = $null

    if ($cachePath) {
        $officeCacheInfoPath = Join-Path $cachePath 'BuiltIn\Microsoft365Apps\CacheInfo.json'
        $teamsCacheInfoPath = Join-Path $cachePath 'BuiltIn\Teams\CacheInfo.json'

        if (Test-Path -LiteralPath $officeCacheInfoPath -PathType Leaf) {
            try { $officeCacheInfo = Get-Content -LiteralPath $officeCacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        }

        if (Test-Path -LiteralPath $teamsCacheInfoPath -PathType Leaf) {
            try { $teamsCacheInfo = Get-Content -LiteralPath $teamsCacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        }
    }

    foreach ($builtInApp in @(
        [pscustomobject]@{
            PSTypeName   = 'OSDAppClient.App'
            Id           = 'Microsoft365Apps'
            Name         = 'Microsoft365Apps'
            DisplayName  = 'Microsoft 365 Apps'
            Version      = if ($officeCacheInfo) { $officeCacheInfo.Version } else { 'Current' }
            Architecture = if ($officeCacheInfo) { $officeCacheInfo.Architecture } else { 'any' }
            Source       = 'BuiltIn'
            Availability = if ($officeCacheInfo) { 'Cached' } else { 'Available' }
            Valid        = $true
        },
        [pscustomobject]@{
            PSTypeName   = 'OSDAppClient.App'
            Id           = 'Teams'
            Name         = 'Teams'
            DisplayName  = 'Microsoft Teams'
            Version      = if ($teamsCacheInfo) { $teamsCacheInfo.Version } else { 'Current' }
            Architecture = if ($teamsCacheInfo) { $teamsCacheInfo.Architecture } else { 'any' }
            Source       = 'BuiltIn'
            Availability = if ($teamsCacheInfo) { 'Cached' } else { 'Available' }
            Valid        = $true
        }
    )) {
        $apps.Add($builtInApp)
    }

    $result = @($apps)

    if ($Name) {
        $result = @(
            $result | Where-Object {
                foreach ($pattern in $Name) {
                    if ($_.Id -like $pattern -or $_.DisplayName -like $pattern) {
                        return $true
                    }
                }
                return $false
            }
        )
    }

    $result
}
