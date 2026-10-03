function Sync-OSDAppCache {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Uri')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Uri')]
        [uri]$ManifestUri,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [string]$CachePath,

        [string[]]$Name
    )

    $logPath = Join-Path $CachePath 'Logs\\Client.log'

    Write-OSDAppsClientLog -LogPath $logPath -Component 'Sync' -Event 'SyncStart' -Message 'Starting repository synchronization.' -Data @{ CachePath = $CachePath; ParameterSet = $PSCmdlet.ParameterSetName }

    if ($PSCmdlet.ParameterSetName -eq 'Uri') {
        $sourceManifest = Get-OSDAppManifest -Uri $ManifestUri
        $manifestSourceDescription = $ManifestUri.AbsoluteUri
        $repositoryRoot = $null
    }
    else {
        $resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
        $sourceManifest = Get-OSDAppManifest -Path $resolvedManifestPath
        $manifestSourceDescription = $resolvedManifestPath
        $repositoryRoot = Split-Path -Path $resolvedManifestPath -Parent
    }

    $packages = @($sourceManifest.Packages)
    if ($Name) { $packages = $packages | Where-Object { $_.Id -in $Name } }

    $packagesRoot = Join-Path $CachePath 'Packages'
    $stagingRoot  = Join-Path $CachePath '.staging'
    New-Item -ItemType Directory -Path $packagesRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null

    foreach ($package in $packages) {
        if (-not $package.Id -or -not $package.Archive -or -not $package.Archive.Sha256) {
            throw "Package '$($package.Id)' has an incomplete Archive definition."
        }

        if ($package.Archive.FileName -and $package.Archive.FileName -ne 'Package.zip') {
            throw "Package '$($package.Id)' must use the fixed archive name Package.zip."
        }

        $targetRoot = Join-Path $packagesRoot $package.Id
        $targetArchive = Join-Path $targetRoot 'Package.zip'

        if (Test-OSDAppFileHash -Path $targetArchive -ExpectedSha256 $package.Archive.Sha256) {
            Write-Verbose "$($package.Id) is current."
            Write-OSDAppsClientLog -LogPath $logPath -Component 'Sync' -Event 'PackageCurrent' -Message 'Cached package is current.' -Data @{ Id = $package.Id; Version = $package.Version }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($package.Id, "Synchronize version $($package.Version)")) { continue }

        $packageTemp = Join-Path $stagingRoot $package.Id
        if (Test-Path -LiteralPath $packageTemp) { Remove-Item -LiteralPath $packageTemp -Recurse -Force }
        New-Item -ItemType Directory -Path $packageTemp -Force | Out-Null
        $tempArchive = Join-Path $packageTemp 'Package.zip'

        if ($package.Archive.Uri) {
            Write-Verbose "Downloading $($package.Archive.Uri)"
            Write-OSDAppsClientLog -LogPath $logPath -Component 'Sync' -Event 'AcquireStart' -Message 'Downloading package archive.' -Data @{ Id = $package.Id; Version = $package.Version; Source = $package.Archive.Uri }
            Invoke-WebRequest -Uri $package.Archive.Uri -OutFile $tempArchive -UseBasicParsing
        }
        elseif ($package.Archive.SourcePath) {
            if (-not $repositoryRoot) { throw "Package '$($package.Id)' uses SourcePath with -ManifestUri." }
            $sourceArchive = Join-Path $repositoryRoot ($package.Archive.SourcePath -replace '/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $sourceArchive -PathType Leaf)) { throw "Source archive not found: $sourceArchive" }
            Write-Verbose "Copying $sourceArchive"
            Write-OSDAppsClientLog -LogPath $logPath -Component 'Sync' -Event 'AcquireStart' -Message 'Copying package archive.' -Data @{ Id = $package.Id; Version = $package.Version; Source = $sourceArchive }
            Copy-Item -LiteralPath $sourceArchive -Destination $tempArchive -Force
        }
        else {
            throw "Package '$($package.Id)' archive has neither Uri nor SourcePath."
        }

        if (-not (Test-OSDAppFileHash -Path $tempArchive -ExpectedSha256 $package.Archive.Sha256)) {
            Write-OSDAppsClientLog -LogPath $logPath -Component 'Sync' -Event 'HashValidationFailed' -Level 'Error' -Message 'SHA-256 validation failed.' -Data @{ Id = $package.Id; Version = $package.Version }
            throw "SHA-256 validation failed for '$($package.Id)/Package.zip'."
        }

        Write-OSDAppsClientLog -LogPath $logPath -Component 'Sync' -Event 'PackageUpdated' -Message 'Package synchronized and validated.' -Data @{ Id = $package.Id; Version = $package.Version; Sha256 = $package.Archive.Sha256 }

        if (Test-Path -LiteralPath $targetRoot) {
            $backupRoot = "$targetRoot.previous"
            if (Test-Path -LiteralPath $backupRoot) { Remove-Item -LiteralPath $backupRoot -Recurse -Force }
            Move-Item -LiteralPath $targetRoot -Destination $backupRoot
            try {
                Move-Item -LiteralPath $packageTemp -Destination $targetRoot
                Remove-Item -LiteralPath $backupRoot -Recurse -Force
            }
            catch {
                if (Test-Path -LiteralPath $targetRoot) { Remove-Item -LiteralPath $targetRoot -Recurse -Force }
                Move-Item -LiteralPath $backupRoot -Destination $targetRoot
                throw
            }
        }
        else { Move-Item -LiteralPath $packageTemp -Destination $targetRoot }
    }

    $selectedManifest = [ordered]@{
        SchemaVersion  = $sourceManifest.SchemaVersion
        GeneratedAt    = $sourceManifest.GeneratedAt
        SourceManifest = $manifestSourceDescription
        Packages       = @($packages)
    }

    $cacheManifestPath = Join-Path $CachePath 'CacheManifest.json'
    $selectedManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $cacheManifestPath -Encoding UTF8
    Write-OSDAppsClientLog -LogPath $logPath -Component 'Sync' -Event 'SyncComplete' -Message 'Repository synchronization completed.' -Data @{ Manifest = $cacheManifestPath; PackageCount = @($packages).Count }

    Get-Item -LiteralPath $cacheManifestPath
}
