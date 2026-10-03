function Test-OSDAppCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,
        [string[]]$Name
    )

    $manifestPath = Join-Path $CachePath 'CacheManifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Cache manifest not found: $manifestPath" }

    $manifest = Get-OSDAppManifest -Path $manifestPath
    $packages = @($manifest.Packages)
    if ($Name) { $packages = $packages | Where-Object { $_.Id -in $Name } }

    foreach ($package in $packages) {
        $archivePath = Join-Path $CachePath (Join-Path 'Packages' (Join-Path $package.Id 'Package.zip'))
        $valid = Test-OSDAppFileHash -Path $archivePath -ExpectedSha256 $package.Archive.Sha256

        [pscustomobject]@{
            Id      = $package.Id
            Version = $package.Version
            Architecture = $package.Architecture
            Path    = $archivePath
            Valid   = $valid
        }
    }
}
