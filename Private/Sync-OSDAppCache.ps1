function Sync-OSDAppCache {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Uri')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Uri')]
        [uri]$CatalogUri,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [string]$CatalogPath,

        [Parameter(Mandatory)]
        [string]$CachePath,

        [string[]]$Name
    )

    $logPath = Join-Path $CachePath 'Logs\\Client.log'

    Write-OSDAppClientLog -LogPath $logPath -Component 'Sync' -Event 'SyncStart' -Message 'Starting repository synchronization.' -Data @{ CachePath = $CachePath; ParameterSet = $PSCmdlet.ParameterSetName }

    if ($PSCmdlet.ParameterSetName -eq 'Uri') {
        $sourceCatalog = Get-OSDAppManifest -Uri $CatalogUri
        $catalogSourceDescription = $CatalogUri.AbsoluteUri
        $repositoryRoot = $null
        $repositoryBaseUri = [uri]::new($CatalogUri, '.')
    }
    else {
        $resolvedCatalogPath = (Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).Path
        $sourceCatalog = Get-OSDAppManifest -Path $resolvedCatalogPath
        $catalogSourceDescription = $resolvedCatalogPath
        $repositoryRoot = Split-Path -Path $resolvedCatalogPath -Parent
        $repositoryBaseUri = $null
    }

    $hostArchitecture = Get-OSDAppHostArchitecture
    $allPackages = @($sourceCatalog.Packages)

    if ($Name) {
        $allPackages = @($allPackages | Where-Object { $_.Id -in $Name })
        $missingIds = @($Name | Where-Object { $_ -notin @($allPackages.Id) })
        if ($missingIds.Count -gt 0) {
            throw "Requested application(s) not found in repository: $($missingIds -join ', ')"
        }
    }

    # Resolve one compatible package variant per application.
    # Exact architecture always wins; 'any' is the fallback.
    $packages = @(
        foreach ($group in ($allPackages | Group-Object Id)) {
            $exact = @(
                $group.Group |
                    Where-Object { ([string]$_.Architecture).ToLowerInvariant() -eq $hostArchitecture }
            )

            $neutral = @(
                $group.Group |
                    Where-Object { ([string]$_.Architecture).ToLowerInvariant() -eq 'any' }
            )

            if ($exact.Count -gt 0) {
                $exact | Select-Object -First 1
            }
            elseif ($neutral.Count -gt 0) {
                $neutral | Select-Object -First 1
            }
            else {
                throw "No compatible package variant for '$($group.Name)' on '$hostArchitecture'. Available: $((@($group.Group.Architecture) -join ', '))"
            }
        }
    )

    Write-OSDAppClientLog -LogPath $logPath -Component 'Sync' -Event 'ArchitectureResolved' -Message 'Resolved package variants for host architecture.' -Data @{ HostArchitecture = $hostArchitecture; Packages = @($packages | ForEach-Object { "$($_.Id):$($_.Architecture)" }) }

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
            Write-OSDAppClientLog -LogPath $logPath -Component 'Sync' -Event 'PackageCurrent' -Message 'Cached package is current.' -Data @{ Id = $package.Id; Version = $package.Version; Architecture = $package.Architecture }
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($package.Id, "Synchronize version $($package.Version)")) { continue }

        $packageTemp = Join-Path $stagingRoot $package.Id
        if (Test-Path -LiteralPath $packageTemp) { Remove-Item -LiteralPath $packageTemp -Recurse -Force }
        New-Item -ItemType Directory -Path $packageTemp -Force | Out-Null
        $tempArchive = Join-Path $packageTemp 'Package.zip'

        if ($package.Archive.Uri) {
            Write-Verbose "Downloading $($package.Archive.Uri)"
            Write-OSDAppClientLog -LogPath $logPath -Component 'Sync' -Event 'AcquireStart' -Message 'Downloading package archive.' -Data @{ Id = $package.Id; Version = $package.Version; Architecture = $package.Architecture; Source = $package.Archive.Uri }
            Invoke-WebRequest -Uri $package.Archive.Uri -OutFile $tempArchive -UseBasicParsing
        }
        elseif ($package.Archive.SourcePath) {
            if ($PSCmdlet.ParameterSetName -eq 'Uri') {
                $relativeSourcePath = ([string]$package.Archive.SourcePath).Replace('\','/')
                $sourceArchiveUri = [uri]::new($repositoryBaseUri, $relativeSourcePath)

                Write-Verbose "Downloading $sourceArchiveUri"
                Write-OSDAppClientLog -LogPath $logPath -Component 'Sync' -Event 'AcquireStart' -Message 'Downloading package archive from repository-relative path.' -Data @{ Id = $package.Id; Version = $package.Version; Architecture = $package.Architecture; Source = $sourceArchiveUri.AbsoluteUri }
                Invoke-WebRequest -Uri $sourceArchiveUri -OutFile $tempArchive -UseBasicParsing
            }
            else {
                $sourceArchive = Join-Path $repositoryRoot ($package.Archive.SourcePath -replace '/', [IO.Path]::DirectorySeparatorChar)
                if (-not (Test-Path -LiteralPath $sourceArchive -PathType Leaf)) { throw "Source archive not found: $sourceArchive" }
                Write-Verbose "Copying $sourceArchive"
                Write-OSDAppClientLog -LogPath $logPath -Component 'Sync' -Event 'AcquireStart' -Message 'Copying package archive.' -Data @{ Id = $package.Id; Version = $package.Version; Architecture = $package.Architecture; Source = $sourceArchive }
                Copy-Item -LiteralPath $sourceArchive -Destination $tempArchive -Force
            }
        }
        else {
            throw "Package '$($package.Id)' archive has neither Uri nor SourcePath."
        }

        if (-not (Test-OSDAppFileHash -Path $tempArchive -ExpectedSha256 $package.Archive.Sha256)) {
            Write-OSDAppClientLog -LogPath $logPath -Component 'Sync' -Event 'HashValidationFailed' -Level 'Error' -Message 'SHA-256 validation failed.' -Data @{ Id = $package.Id; Version = $package.Version; Architecture = $package.Architecture }
            throw "SHA-256 validation failed for '$($package.Id)/Package.zip'."
        }

        Write-OSDAppClientLog -LogPath $logPath -Component 'Sync' -Event 'PackageUpdated' -Message 'Package synchronized and validated.' -Data @{ Id = $package.Id; Version = $package.Version; Architecture = $package.Architecture; Sha256 = $package.Archive.Sha256 }

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

    $selectedCatalog = [ordered]@{
        SchemaVersion  = $sourceCatalog.SchemaVersion
        GeneratedAt    = $sourceCatalog.GeneratedAt
        SourceCatalog = $catalogSourceDescription
        Packages       = @($packages)
    }

    $cacheCatalogPath = Join-Path $CachePath 'CacheCatalog.json'
    $selectedCatalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $cacheCatalogPath -Encoding UTF8
    Write-OSDAppClientLog -LogPath $logPath -Component 'Sync' -Event 'SyncComplete' -Message 'Repository synchronization completed.' -Data @{ Catalog = $cacheCatalogPath; PackageCount = @($packages).Count }

    Get-Item -LiteralPath $cacheCatalogPath
}
