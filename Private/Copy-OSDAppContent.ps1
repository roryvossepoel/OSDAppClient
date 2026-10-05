function Copy-OSDAppContent {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]]$Name,

        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [string]$WindowsPath,

        [string]$DestinationRelativePath = 'Windows\Temp\OSDApps'
    )

    $cacheManifestPath = Join-Path $CachePath 'CacheCatalog.json'
    $manifest = Get-OSDAppManifest -Path $cacheManifestPath

    $packages = @(
        foreach ($requestedName in $Name) {
            $match = @($manifest.Packages | Where-Object { $_.Id -eq $requestedName })
            if ($match.Count -gt 0) {
                $match[0]
            }
        }
    )
    $missing = @($Name | Where-Object { $_ -notin @($packages.Id) })
    if ($missing.Count -gt 0) {
        throw "Requested package(s) not found in cache catalog: $($missing -join ', ')"
    }

    $invalid = @(Test-OSDAppCache -CachePath $CachePath -Name $Name | Where-Object { -not $_.Valid })
    if ($invalid.Count -gt 0) {
        throw "Cache validation failed for: $((@($invalid.Id | Select-Object -Unique)) -join ', ')"
    }

    $clientLogPath = Join-Path $CachePath 'Logs\\Client.log'
    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Stage' -Event 'StageStart' -Message 'Starting application staging.' -Data @{ WindowsPath = $WindowsPath; DestinationRelativePath = $DestinationRelativePath; Packages = @($packages | ForEach-Object { "$($_.Id):$($_.Architecture)" }) }

    $destinationRoot = Join-Path $WindowsPath $DestinationRelativePath
    $destinationPackages = Join-Path $destinationRoot 'Packages'

    if ($PSCmdlet.ShouldProcess($destinationRoot, 'Stage OSD Apps content')) {
        New-Item -ItemType Directory -Path $destinationPackages -Force | Out-Null

        foreach ($package in $packages) {
            $source = Join-Path $CachePath (Join-Path 'Packages' $package.Id)
            $target = Join-Path $destinationPackages $package.Id

            if (Test-Path -LiteralPath $target) {
                Remove-Item -LiteralPath $target -Recurse -Force
            }
            Copy-Item -LiteralPath $source -Destination $target -Recurse -Force
            Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Stage' -Event 'PackageStaged' -Message 'Package copied to offline Windows volume.' -Data @{ Id = $package.Id; Version = $package.Version; Architecture = $package.Architecture; Destination = $target }
        }

        $deviceManifest = [ordered]@{
            SchemaVersion = $manifest.SchemaVersion
            StagedAt      = (Get-Date).ToUniversalTime().ToString('o')
            Packages      = @($packages)
        }

        $deviceManifest | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $destinationRoot 'DeviceManifest.json') -Encoding UTF8

        $moduleRoot = Split-Path $PSScriptRoot -Parent
        $runtimeSource = Join-Path $moduleRoot 'Runtime\Invoke-OSDAppRunner.ps1'
        Copy-Item -LiteralPath $runtimeSource -Destination (Join-Path $destinationRoot 'Invoke-OSDAppRunner.ps1') -Force
        Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Stage' -Event 'StageComplete' -Message 'Application staging completed.' -Data @{ Destination = $destinationRoot; PackageCount = @($packages).Count }
    }

    Get-Item -LiteralPath $destinationRoot
}
