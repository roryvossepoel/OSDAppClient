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
    }

    if ($cachePath -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
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
                Valid        = (Test-OSDAppFileHash -Path (Join-Path $cachePath (Join-Path 'Packages' (Join-Path $package.Id 'Package.zip'))) -ExpectedSha256 $package.Archive.Sha256)
            })
        }
    }

    $builtInApps = @(
        [pscustomobject]@{
            PSTypeName   = 'OSDAppClient.App'
            Id           = 'Microsoft365Apps'
            Name         = 'Microsoft365Apps'
            DisplayName  = 'Microsoft 365 Apps'
            Version      = 'Current'
            Architecture = 'any'
            Source       = 'BuiltIn'
            Valid        = $true
        },
        [pscustomobject]@{
            PSTypeName   = 'OSDAppClient.App'
            Id           = 'Teams'
            Name         = 'Teams'
            DisplayName  = 'Microsoft Teams'
            Version      = 'Current'
            Architecture = 'any'
            Source       = 'BuiltIn'
            Valid        = $true
        }
    )

    foreach ($builtInApp in $builtInApps) {
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
