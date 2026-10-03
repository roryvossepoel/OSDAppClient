function Get-OSDAppCatalog {
    [CmdletBinding(DefaultParameterSetName = 'Local')]
    param(
        [Parameter(Position = 0)]
        [string[]]$Name,

        [Parameter(ParameterSetName = 'Local')]
        [switch]$Local,

        [Parameter(Mandatory, ParameterSetName = 'Online')]
        [switch]$Online,

        [Parameter(Mandatory, ParameterSetName = 'Online')]
        [uri]$ManifestUri
    )

    $apps = [System.Collections.Generic.List[object]]::new()

    $builtInApps = @(
        [pscustomobject]@{
            PSTypeName   = 'OSDAppClient.CatalogApp'
            Id           = 'Microsoft365Apps'
            Name         = 'Microsoft365Apps'
            DisplayName  = 'Microsoft 365 Apps'
            Version      = 'Current'
            Architecture = 'any'
            Source       = 'BuiltIn'
            Availability = 'Available'
            Valid        = $true
        },
        [pscustomobject]@{
            PSTypeName   = 'OSDAppClient.CatalogApp'
            Id           = 'Teams'
            Name         = 'Teams'
            DisplayName  = 'Microsoft Teams'
            Version      = 'Current'
            Architecture = 'any'
            Source       = 'BuiltIn'
            Availability = 'Available'
            Valid        = $true
        }
    )

    if ($PSCmdlet.ParameterSetName -eq 'Online') {
        try {
            $response = Invoke-WebRequest -Uri $ManifestUri -UseBasicParsing -ErrorAction Stop
            $manifest = $response.Content | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Failed to read online OSD App repository manifest '$ManifestUri': $($_.Exception.Message)"
        }

        foreach ($package in @($manifest.Packages)) {
            $apps.Add([pscustomobject]@{
                PSTypeName   = 'OSDAppClient.CatalogApp'
                Id           = $package.Id
                Name         = $package.Id
                DisplayName  = $package.DisplayName
                Version      = $package.Version
                Architecture = $package.Architecture
                Source       = 'Repository'
                Availability = 'Online'
                Valid        = $null
            })
        }
    }
    else {
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
                        PSTypeName   = 'OSDAppClient.CatalogApp'
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
    }

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
