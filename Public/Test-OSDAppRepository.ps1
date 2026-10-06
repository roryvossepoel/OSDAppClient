function Test-OSDAppRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position=0)]
        [string]$RepositoryPath
    )

    $catalog = Get-OSDAppRepositoryManifest -RepositoryPath $RepositoryPath

    foreach ($application in @($catalog.Applications)) {
        foreach ($packageRef in @($application.Packages)) {
            $manifestPath = Join-Path $RepositoryPath ($packageRef.Manifest -replace '/', [IO.Path]::DirectorySeparatorChar)
            $manifestExists = Test-Path -LiteralPath $manifestPath -PathType Leaf

            if (-not $manifestExists) {
                [pscustomobject]@{
                    PSTypeName        = 'OSDApps.RepositoryValidation'
                    Id                = $application.Id
                    Version           = $null
                    Architecture      = $packageRef.Architecture
                    ManifestExists    = $false
                    PackageExists     = $false
                    HashValid         = $false
                    PackageValid      = $false
                    ArchitectureValid = $false
                    IdValid           = $false
                    Valid             = $false
                }
                continue
            }

            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $packagePath = Join-Path (Split-Path -Path $manifestPath -Parent) 'Package.zip'
            $exists = Test-Path -LiteralPath $packagePath -PathType Leaf
            $hashValid = $false
            $packageValid = $false

            if ($exists) {
                $actualHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
                $hashValid = $actualHash.Equals([string]$manifest.Archive.Sha256, [System.StringComparison]::OrdinalIgnoreCase)
                $packageValid = (Test-OSDAppPackage -PackagePath $packagePath).Valid
            }

            $architectureValid = (
                ([string]$manifest.Architecture).ToLowerInvariant() -in @('x64','arm64','any') -and
                ([string]$manifest.Architecture).ToLowerInvariant() -eq ([string]$packageRef.Architecture).ToLowerInvariant()
            )
            $idValid = [string]$manifest.Id -eq [string]$application.Id

            [pscustomobject]@{
                PSTypeName        = 'OSDApps.RepositoryValidation'
                Id                = $manifest.Id
                Version           = $manifest.Version
                Architecture      = $manifest.Architecture
                ManifestExists    = $true
                PackageExists     = $exists
                HashValid         = $hashValid
                PackageValid      = $packageValid
                ArchitectureValid = $architectureValid
                IdValid           = $idValid
                Valid             = ($exists -and $hashValid -and $packageValid -and $architectureValid -and $idValid)
            }
        }
    }
}
