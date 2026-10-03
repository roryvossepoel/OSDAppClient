function Get-OSDApp {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]$Name
    )

    $cachePath = Get-OSDAppCachePath
    $manifestPath = Join-Path $cachePath 'CacheManifest.json'

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "OSD App cache manifest not found: $manifestPath. Run Sync-OSDAppRepository first."
    }

    $manifest = Get-OSDAppManifest -Path $manifestPath
    $packages = @($manifest.Packages)

    if ($Name) {
        $packages = @(
            $packages | Where-Object {
                foreach ($pattern in $Name) {
                    if ($_.Id -like $pattern -or $_.DisplayName -like $pattern) {
                        return $true
                    }
                }
                return $false
            }
        )
    }

    foreach ($package in $packages) {
        [pscustomobject]@{
            PSTypeName   = 'OSDAppClient.App'
            Id           = $package.Id
            Name         = $package.Id
            DisplayName  = $package.DisplayName
            Version      = $package.Version
            Architecture = $package.Architecture
            Valid        = (Test-OSDAppFileHash -Path (Join-Path $cachePath (Join-Path 'Packages' (Join-Path $package.Id 'Package.zip'))) -ExpectedSha256 $package.Archive.Sha256)
        }
    }
}
