function Get-OSDAppCatalogPackages {
    [CmdletBinding(DefaultParameterSetName = 'Uri')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Uri')]
        [uri]$CatalogUri,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$CatalogPath,

        [string[]]$Name
    )

    if ($PSCmdlet.ParameterSetName -eq 'Uri') {
        $catalog = Get-OSDAppManifest -Uri $CatalogUri
        $catalogBaseUri = [uri]::new($CatalogUri, '.')
        $catalogRoot = $null
    }
    else {
        $resolvedCatalogPath = (Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).Path
        $catalog = Get-OSDAppManifest -Path $resolvedCatalogPath
        $catalogBaseUri = $null
        $catalogRoot = Split-Path -Path $resolvedCatalogPath -Parent
    }

    if (-not ($catalog.PSObject.Properties.Name -contains 'Applications')) {
        throw 'Invalid OSD Apps catalog. Root catalog must contain Applications.'
    }

    $applications = @($catalog.Applications)
    if ($Name) {
        $applications = @($applications | Where-Object { $_.Id -in $Name })
        $missing = @($Name | Where-Object { $_ -notin @($applications.Id) })
        if ($missing.Count -gt 0) {
            throw "Requested application(s) not found in catalog: $($missing -join ', ')"
        }
    }

    $packages = [System.Collections.Generic.List[object]]::new()

    foreach ($application in $applications) {
        if (-not $application.Id -or -not $application.Manifest) {
            throw 'Catalog application entry must contain Id and Manifest.'
        }

        if ($PSCmdlet.ParameterSetName -eq 'Uri') {
            $appManifestUri = [uri]::new($catalogBaseUri, ([string]$application.Manifest).Replace('\','/'))
            $appManifest = Get-OSDAppManifest -Uri $appManifestUri
            $appBaseUri = [uri]::new($appManifestUri, '.')
        }
        else {
            $appManifestPath = Join-Path $catalogRoot (([string]$application.Manifest) -replace '/', [IO.Path]::DirectorySeparatorChar)
            $appManifest = Get-OSDAppManifest -Path $appManifestPath
            $appRoot = Split-Path -Path $appManifestPath -Parent
        }

        if ($appManifest.Id -and $appManifest.Id -ne $application.Id) {
            throw "Application manifest Id '$($appManifest.Id)' does not match catalog Id '$($application.Id)'."
        }

        foreach ($package in @($appManifest.Packages)) {
            $archive = [ordered]@{
                FileName = if ($package.Archive.FileName) { [string]$package.Archive.FileName } else { 'Package.zip' }
                Sha256   = [string]$package.Archive.Sha256
            }

            if ($PSCmdlet.ParameterSetName -eq 'Uri') {
                $archive.Uri = ([uri]::new($appBaseUri, ([string]$package.Archive.SourcePath).Replace('\','/'))).AbsoluteUri
            }
            else {
                $archive.SourcePath = Join-Path $appRoot (([string]$package.Archive.SourcePath) -replace '/', [IO.Path]::DirectorySeparatorChar)
            }

            $packages.Add([pscustomobject]@{
                Id           = [string]$application.Id
                DisplayName  = if ($appManifest.DisplayName) { [string]$appManifest.DisplayName } else { [string]$application.Id }
                Version      = [string]$package.Version
                Architecture = [string]$package.Architecture
                SuccessCodes = @($package.SuccessCodes)
                Archive      = [pscustomobject]$archive
            })
        }
    }

    [pscustomobject]@{
        SchemaVersion = $catalog.SchemaVersion
        GeneratedAt   = $catalog.GeneratedAt
        Packages      = @($packages)
    }
}
