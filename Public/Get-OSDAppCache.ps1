function Get-OSDAppCache {
    [CmdletBinding()]
    param(
        [string[]]$Name
    )

    # Cache inspection is optional when no OSDCloud media is attached.
    try {
        $cachePath = Get-OSDAppCachePath
    }
    catch {
        Write-Verbose 'No OSDCloud cache volume is available.'
        return
    }
    $results = [System.Collections.Generic.List[object]]::new()

    $cacheCatalogPath = Join-Path $cachePath 'CacheCatalog.json'
    if (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf) {
        try {
            $catalog = Get-OSDAppManifest -Path $cacheCatalogPath
            foreach ($package in @($catalog.Packages)) {
                $archivePath = Join-Path $cachePath (Join-Path 'Packages' (Join-Path $package.Id 'Package.zip'))
                $exists = Test-Path -LiteralPath $archivePath -PathType Leaf
                $valid = $false
                $sizeMB = $null

                if ($exists) {
                    $sizeMB = [math]::Round((Get-Item -LiteralPath $archivePath).Length / 1MB, 1)
                    if ($package.Archive -and $package.Archive.Sha256) {
                        $valid = Test-OSDAppFileHash -Path $archivePath -ExpectedSha256 $package.Archive.Sha256
                    }
                }

                $results.Add([pscustomobject]@{
                    PSTypeName   = 'OSDApps.CacheEntry'
                    Id           = [string]$package.Id
                    Source       = 'Repository'
                    Version      = [string]$package.Version
                    Architecture = [string]$package.Architecture
                    Channel      = $null
                    Language     = $null
                    SourcePolicy = 'RepositoryManaged'
                    SyncMethod   = 'ManifestSha256'
                    LastSynced   = $catalog.GeneratedAt
                    SizeMB       = $sizeMB
                    Valid        = $valid
                    CachePath    = if ($exists) { $archivePath } else { Join-Path $cachePath (Join-Path 'Packages' $package.Id) }
                })
            }
        }
        catch {
            Write-Warning "Failed to read repository cache catalog '$cacheCatalogPath': $($_.Exception.Message)"
        }
    }

    $builtInRoot = Join-Path $cachePath 'BuiltIn'
    if (Test-Path -LiteralPath $builtInRoot -PathType Container) {
        foreach ($cacheInfoFile in @(Get-ChildItem -LiteralPath $builtInRoot -Filter 'CacheInfo.json' -File -Recurse -ErrorAction SilentlyContinue)) {
            try {
                $info = Get-Content -LiteralPath $cacheInfoFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $entryRoot = Split-Path -Path $cacheInfoFile.FullName -Parent
                $files = @(Get-ChildItem -LiteralPath $entryRoot -File -Recurse -ErrorAction SilentlyContinue)
                $bytes = ($files | Measure-Object -Property Length -Sum).Sum
                if ($null -eq $bytes) { $bytes = 0 }

                $payloadValid = switch ([string]$info.Id) {
                    'Microsoft365Apps' {
                        (Test-Path -LiteralPath (Join-Path $entryRoot 'setup.exe') -PathType Leaf) -and
                        (Test-Path -LiteralPath (Join-Path $entryRoot 'configuration.xml') -PathType Leaf) -and
                        (Test-Path -LiteralPath (Join-Path $entryRoot 'Office\Data') -PathType Container)
                    }
                    'MicrosoftTeams' {
                        (Test-Path -LiteralPath (Join-Path $entryRoot 'teamsbootstrapper.exe') -PathType Leaf) -and
                        (Test-Path -LiteralPath (Join-Path $entryRoot 'teams.msix') -PathType Leaf)
                    }
                    'AdobeAcrobatUnified' {
                        Test-Path -LiteralPath (Join-Path $entryRoot 'Package.zip') -PathType Leaf
                    }
                    'GoogleChromeEnterprise' {
                        Test-Path -LiteralPath (Join-Path $entryRoot 'Package.msi') -PathType Leaf
                    }
                    'CiscoWebex' {
                        Test-Path -LiteralPath (Join-Path $entryRoot 'Package.msi') -PathType Leaf
                    }
                    'MozillaFirefoxEnterprise' {
                        Test-Path -LiteralPath (Join-Path $entryRoot 'Package.msi') -PathType Leaf
                    }
                    default {
                        $files.Count -gt 0
                    }
                }

                $results.Add([pscustomobject]@{
                    PSTypeName   = 'OSDApps.CacheEntry'
                    Id           = [string]$info.Id
                    Source       = 'BuiltIn'
                    Version      = if ($info.Version) { [string]$info.Version } else { $null }
                    Architecture = if ($info.Architecture) { [string]$info.Architecture } else { $null }
                    Channel      = if ($info.Channel) { [string]$info.Channel } else { $null }
                    Language     = if ($info.Language -is [System.Collections.IEnumerable] -and $info.Language -isnot [string]) { @($info.Language) -join ',' } elseif ($info.Language) { [string]$info.Language } else { $null }
                    SourcePolicy = if ($info.SourcePolicy) { [string]$info.SourcePolicy } else { 'Evergreen' }
                    SyncMethod   = if ($info.SyncMethod) { [string]$info.SyncMethod } else { $null }
                    LastSynced   = $info.SyncedAt
                    SizeMB       = [math]::Round([double]$bytes / 1MB, 1)
                    Valid        = [bool]$payloadValid
                    CachePath    = $entryRoot
                })
            }
            catch {
                Write-Warning "Failed to inspect built-in cache '$($cacheInfoFile.FullName)': $($_.Exception.Message)"
            }
        }
    }

    $output = @($results)
    if ($Name) {
        $output = @($output | Where-Object {
            $entry = $_
            @($Name | Where-Object { $entry.Id -like $_ }).Count -gt 0
        })
    }

    $output | Sort-Object Source, Id, Architecture, Channel, Language
}
