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

    if ($PSCmdlet.ParameterSetName -eq 'Uri') {
        $sourceCatalog = Get-OSDAppCatalogPackages -CatalogUri $CatalogUri -Name $Name
        $catalogSourceDescription = $CatalogUri.AbsoluteUri
        $repositoryRoot = $null
        $repositoryBaseUri = [uri]::new($CatalogUri, '.')
    }
    else {
        $resolvedCatalogPath = (Resolve-Path -LiteralPath $CatalogPath -ErrorAction Stop).Path
        $sourceCatalog = Get-OSDAppCatalogPackages -CatalogPath $resolvedCatalogPath -Name $Name
        $catalogSourceDescription = $resolvedCatalogPath
        $repositoryRoot = Split-Path -Path $resolvedCatalogPath -Parent
        $repositoryBaseUri = $null
    }

    $hostArchitecture = Get-OSDAppHostArchitecture
    $allPackages = @($sourceCatalog.Packages)

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


    $packagesRoot = Join-Path $CachePath 'Packages'
    $cacheCatalogPath = Join-Path $CachePath 'CacheCatalog.json'
    $stagingRoot = Join-Path $CachePath '.staging'

    # Validate ALL entries before touching the persistent cache.
    # IDs are directory names, so arbitrary paths and traversal are forbidden.
    foreach ($package in $packages) {
        if (-not $package.Id -or -not $package.Archive -or -not $package.Archive.Sha256) {
            throw "Package '$($package.Id)' has an incomplete Archive definition."
        }
        if ([string]$package.Id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            [string]$package.Id -match '\.\.') {
            throw "Invalid package Id '$($package.Id)' in repository catalog."
        }
        if ($package.Archive.FileName -and $package.Archive.FileName -ne 'Package.zip') {
            throw "Package '$($package.Id)' must use the fixed archive name Package.zip."
        }
        if ([string]$package.Archive.Sha256 -notmatch '^[A-Fa-f0-9]{64}$') {
            throw "Package '$($package.Id)' has an invalid SHA-256 hash."
        }
    }

    # Never discard existing cache entries because a catalog is unreadable.
    $existingPackages = @()
    if (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf) {
        try {
            $existingCatalog = Get-OSDAppManifest -Path $cacheCatalogPath
            if ($null -eq $existingCatalog -or
                -not ($existingCatalog.PSObject.Properties.Name -contains 'Packages')) {
                throw 'Cache catalog is missing Packages.'
            }
            $existingPackages = @($existingCatalog.Packages)
        }
        catch {
            throw "Existing cache catalog '$cacheCatalogPath' cannot be read safely: $($_.Exception.Message)"
        }
    }

    $updatedIds = @($packages.Id)
    $mergedPackages = @(
        @($existingPackages | Where-Object { $_.Id -notin $updatedIds }) +
        @($packages)
    )
    $selectedCatalog = [ordered]@{
        SchemaVersion = $sourceCatalog.SchemaVersion
        GeneratedAt = $sourceCatalog.GeneratedAt
        SourceCatalog = $catalogSourceDescription
        Packages = @($mergedPackages)
    }

    $toAcquire = [System.Collections.Generic.List[object]]::new()
    foreach ($package in $packages) {
        $targetRoot = Join-Path $packagesRoot $package.Id
        $targetArchive = Join-Path $targetRoot 'Package.zip'
        if (Test-OSDAppFileHash -Path $targetArchive -ExpectedSha256 $package.Archive.Sha256) {
            Write-Verbose "$($package.Id) is current."
        }
        else {
            $toAcquire.Add([pscustomobject]@{
                Package = $package
                TargetRoot = $targetRoot
            })
        }
    }

    if (-not $PSCmdlet.ShouldProcess($CachePath, "Synchronize $($packages.Count) application(s) as a single cache transaction")) {
        return
    }

    Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'SyncStart' -Message 'Starting transactional repository synchronization.' -Data @{ CachePath = $CachePath; RequestedCount = $packages.Count; AcquireCount = $toAcquire.Count }
    Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'ArchitectureResolved' -Message 'Resolved package variants.' -Data @{ HostArchitecture = $hostArchitecture; Packages = @($packages | ForEach-Object { "$($_.Id):$($_.Architecture)" }) }

    # Everything is downloaded and hash-validated BEFORE an existing package is replaced.
    # All backups live on the same cache volume and are retained if rollback fails.
    $transactionRoot = Join-Path $stagingRoot ("Sync-{0}" -f [guid]::NewGuid().ToString('N'))
    $preparedRoot = Join-Path $transactionRoot 'Prepared'
    $backupRoot = Join-Path $transactionRoot 'Backup'
    $catalogPrepared = Join-Path $transactionRoot 'CacheCatalog.json.new'
    $catalogBackup = Join-Path $transactionRoot 'CacheCatalog.json.old'
    $promoted = [System.Collections.Generic.List[object]]::new()
    $keepRecoveryFiles = $false
    $catalogExisted = Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf
    $catalogCommitAttempted = $false
    $committed = $false

    try {
        New-Item -ItemType Directory -Path $packagesRoot,$preparedRoot,$backupRoot -Force -ErrorAction Stop | Out-Null

        foreach ($entry in $toAcquire) {
            $package = $entry.Package
            $packageTemp = Join-Path $preparedRoot $package.Id
            New-Item -ItemType Directory -Path $packageTemp -Force -ErrorAction Stop | Out-Null
            $tempArchive = Join-Path $packageTemp 'Package.zip'

            if ($package.Archive.Uri) {
                Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'AcquireStart' -Message 'Downloading package archive.' -Data @{ Id = $package.Id; Source = $package.Archive.Uri }
                Invoke-WebRequest -Uri $package.Archive.Uri -OutFile $tempArchive -UseBasicParsing -ErrorAction Stop
            }
            elseif ($package.Archive.SourcePath) {
                $sourceArchive = [string]$package.Archive.SourcePath
                if (-not (Test-Path -LiteralPath $sourceArchive -PathType Leaf)) {
                    throw "Source archive not found: $sourceArchive"
                }
                Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'AcquireStart' -Message 'Copying package archive.' -Data @{ Id = $package.Id; Source = $sourceArchive }
                Copy-Item -LiteralPath $sourceArchive -Destination $tempArchive -Force -ErrorAction Stop
            }
            else {
                throw "Package '$($package.Id)' archive has neither Uri nor SourcePath."
            }

            if (-not (Test-OSDAppFileHash -Path $tempArchive -ExpectedSha256 $package.Archive.Sha256)) {
                throw "SHA-256 validation failed for '$($package.Id)/Package.zip'."
            }
            Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'PackagePrepared' -Message 'Package is downloaded and SHA-256 validated.' -Data @{ Id = $package.Id; Version = $package.Version }
        }

        # Stage the new catalog and save the old one before any package promotion.
        $selectedCatalog | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $catalogPrepared -Encoding UTF8 -ErrorAction Stop
        if ($catalogExisted) {
            Copy-Item -LiteralPath $cacheCatalogPath -Destination $catalogBackup -Force -ErrorAction Stop
        }

        foreach ($entry in $toAcquire) {
            $id = [string]$entry.Package.Id
            $targetRoot = [string]$entry.TargetRoot
            $backupPath = Join-Path $backupRoot $id
            $sourcePath = Join-Path $preparedRoot $id
            $hadPrevious = Test-Path -LiteralPath $targetRoot

            if ($hadPrevious) {
                Move-Item -LiteralPath $targetRoot -Destination $backupPath -ErrorAction Stop
            }
            # Record before promoting: the second move itself could fail.
            $promoted.Add([pscustomobject]@{
                Id = $id
                TargetRoot = $targetRoot
                BackupPath = $backupPath
                HadPrevious = $hadPrevious
            })
            Move-Item -LiteralPath $sourcePath -Destination $targetRoot -ErrorAction Stop
        }

        # This is the commit point: the manifest must describe the new files.
        $catalogCommitAttempted = $true
        Move-Item -LiteralPath $catalogPrepared -Destination $cacheCatalogPath -Force -ErrorAction Stop
        $committed = $true
    }
    catch {
        $syncError = $_.Exception.Message
        $recoveryErrors = [System.Collections.Generic.List[string]]::new()
        if (-not $committed) {
            # Roll back in reverse order, restoring the exact prior directories.
            for ($i = $promoted.Count - 1; $i -ge 0; $i--) {
                $entry = $promoted[$i]
                try {
                    if (Test-Path -LiteralPath $entry.TargetRoot) {
                        Remove-Item -LiteralPath $entry.TargetRoot -Recurse -Force -ErrorAction Stop
                    }
                    if ($entry.HadPrevious) {
                        Move-Item -LiteralPath $entry.BackupPath -Destination $entry.TargetRoot -ErrorAction Stop
                    }
                }
                catch {
                    $recoveryErrors.Add("$($entry.Id): $($_.Exception.Message)")
                }
            }

            if ($catalogCommitAttempted) {
                try {
                    if ($catalogExisted) {
                        Copy-Item -LiteralPath $catalogBackup -Destination $cacheCatalogPath -Force -ErrorAction Stop
                    }
                    elseif (Test-Path -LiteralPath $cacheCatalogPath) {
                        Remove-Item -LiteralPath $cacheCatalogPath -Force -ErrorAction Stop
                    }
                }
                catch {
                    $recoveryErrors.Add("CacheCatalog.json: $($_.Exception.Message)")
                }
            }
        }
        $keepRecoveryFiles = $recoveryErrors.Count -gt 0
        Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'SyncFailed' -Level 'Error' -Message 'Cache transaction failed.' -Data @{
            Error = $syncError
            RollbackErrors = ($recoveryErrors -join ' | ')
            RecoveryPath = if ($keepRecoveryFiles) { $transactionRoot } else { '' }
        }
        if ($keepRecoveryFiles) {
            throw "Cache transaction failed: $syncError. Rollback incomplete ($($recoveryErrors -join '; ')). Preserve recovery data at '$transactionRoot'."
        }
        throw "Cache transaction failed: $syncError. Previous cache preserved."
    }
    finally {
        if (-not $keepRecoveryFiles -and (Test-Path -LiteralPath $transactionRoot)) {
            Remove-Item -LiteralPath $transactionRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($entry in $toAcquire) {
        Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'PackageUpdated' -Message 'Package transaction committed and SHA-256 validated.' -Data @{ Id = $entry.Package.Id; Version = $entry.Package.Version; Sha256 = $entry.Package.Archive.Sha256 }
    }
    Write-OSDAppLog -LogPath $logPath -Component 'Sync' -Event 'SyncComplete' -Message 'Repository synchronization committed.' -Data @{
        Catalog = $cacheCatalogPath
        SyncedPackageCount = $packages.Count
        UpdatedPackageCount = $toAcquire.Count
        CachedPackageCount = @($mergedPackages).Count
    }

    Get-Item -LiteralPath $cacheCatalogPath
}
