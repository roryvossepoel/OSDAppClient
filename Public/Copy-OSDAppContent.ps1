function Copy-OSDAppContent {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]]$Name,

        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [string]$WindowsPath,

        [string]$DestinationRelativePath = 'OSDApps'
    )

    $cacheManifestPath = Join-Path $CachePath 'CacheManifest.json'
    $manifest = Get-OSDAppManifest -Path $cacheManifestPath

    $packages = @($manifest.Packages | Where-Object { $_.Id -in $Name })
    $missing = @($Name | Where-Object { $_ -notin @($packages.Id) })
    if ($missing.Count -gt 0) {
        throw "Requested package(s) not found in cache manifest: $($missing -join ', ')"
    }

    $invalid = @(Test-OSDAppCache -CachePath $CachePath -Name $Name | Where-Object { -not $_.Valid })
    if ($invalid.Count -gt 0) {
        throw "Cache validation failed for: $((@($invalid.Id | Select-Object -Unique)) -join ', ')"
    }

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
        }

        $deviceManifest = [ordered]@{
            SchemaVersion = $manifest.SchemaVersion
            StagedAt      = (Get-Date).ToUniversalTime().ToString('o')
            Packages      = @($packages)
        }

        $deviceManifest | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath (Join-Path $destinationRoot 'DeviceManifest.json') -Encoding UTF8

        $moduleRoot = Split-Path $PSScriptRoot -Parent
        $runtimeSource = Join-Path $moduleRoot 'Runtime\Invoke-OSDAppInstall.ps1'
        Copy-Item -LiteralPath $runtimeSource -Destination (Join-Path $destinationRoot 'Invoke-OSDAppInstall.ps1') -Force
    }

    Get-Item -LiteralPath $destinationRoot
}
