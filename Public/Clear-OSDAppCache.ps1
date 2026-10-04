function Clear-OSDAppCache {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'All')]
    param(
        [Parameter(ParameterSetName = 'All')]
        [switch]$All,

        [Parameter(Mandatory, ParameterSetName = 'Repository')]
        [switch]$Repository,

        [Parameter(Mandatory, ParameterSetName = 'BuiltIn')]
        [switch]$BuiltIn,

        [Parameter(Mandatory, ParameterSetName = 'Name')]
        [string[]]$Name,

        [switch]$IncludeLogs
    )

    $cachePath = Get-OSDAppCachePath
    $logPath = Join-Path $cachePath 'Logs\Client.log'
    $scope = $PSCmdlet.ParameterSetName

    if ($scope -eq 'All' -and -not $All) {
        $All = $true
    }

    Write-OSDAppClientLog -LogPath $logPath -Component 'Cache' -Event 'CacheClearStart' -Message 'Starting OSD App cache clear operation.' -Data @{
        Scope       = $scope
        Names       = @($Name)
        IncludeLogs = [bool]$IncludeLogs
        CachePath   = $cachePath
    }

    $removed = [System.Collections.Generic.List[string]]::new()

    function Remove-CacheItem {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [string]$Label
        )

        if (Test-Path -LiteralPath $Path) {
            if ($PSCmdlet.ShouldProcess($Path, "Remove $Label")) {
                Remove-Item -LiteralPath $Path -Recurse -Force
                $removed.Add($Label)
            }
        }
    }

    $manifestPath = Join-Path $cachePath 'CacheManifest.json'
    $packagesPath = Join-Path $cachePath 'Packages'
    $builtInPath = Join-Path $cachePath 'BuiltIn'

    if ($All -or $Repository) {
        Remove-CacheItem -Path $packagesPath -Label 'Repository packages'
        Remove-CacheItem -Path $manifestPath -Label 'CacheManifest.json'
    }

    if ($All -or $BuiltIn) {
        Remove-CacheItem -Path $builtInPath -Label 'Built-in cache'
    }

    if ($PSCmdlet.ParameterSetName -eq 'Name') {
        $manifest = $null

        if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
            try {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            }
            catch {
                throw "Failed to read cache manifest '$manifestPath': $($_.Exception.Message)"
            }
        }

        foreach ($appName in @($Name | Select-Object -Unique)) {
            if ($appName -ieq 'Microsoft365Apps' -or $appName -ieq 'Teams') {
                $builtInAppPath = Join-Path $builtInPath $appName
                Remove-CacheItem -Path $builtInAppPath -Label "Built-in app '$appName'"
                continue
            }

            $repositoryAppPath = Join-Path $packagesPath $appName
            Remove-CacheItem -Path $repositoryAppPath -Label "Repository app '$appName'"

            if ($manifest -and $manifest.PSObject.Properties.Name -contains 'Packages') {
                $remainingPackages = @($manifest.Packages | Where-Object { $_.Id -ne $appName })

                if (@($remainingPackages).Count -ne @($manifest.Packages).Count) {
                    $manifest.Packages = $remainingPackages

                    if ($PSCmdlet.ShouldProcess($manifestPath, "Remove '$appName' from CacheManifest.json")) {
                        $manifest | ConvertTo-Json -Depth 20 |
                            Set-Content -LiteralPath $manifestPath -Encoding UTF8
                        $removed.Add("Cache manifest entry '$appName'")
                    }
                }
            }
        }
    }

    if ($IncludeLogs) {
        $logsPath = Join-Path $cachePath 'Logs'

        if ($PSCmdlet.ShouldProcess($logsPath, 'Clear OSD App client logs')) {
            if (Test-Path -LiteralPath $logsPath) {
                Get-ChildItem -LiteralPath $logsPath -File -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction Stop
            }

            # Recreate Client.log after clearing so the cache-clear action itself remains auditable.
            Write-OSDAppClientLog -LogPath $logPath -Component 'Cache' -Event 'CacheLogsCleared' -Message 'OSD App client logs were cleared by request.' -Data @{
                Scope     = $scope
                Names     = @($Name)
                CachePath = $cachePath
            }
        }
    }

    Write-OSDAppClientLog -LogPath $logPath -Component 'Cache' -Event 'CacheClearComplete' -Message 'OSD App cache clear operation completed.' -Data @{
        Scope       = $scope
        Names       = @($Name)
        IncludeLogs = [bool]$IncludeLogs
        Removed     = @($removed)
        CachePath   = $cachePath
    }

    [pscustomobject]@{
        PSTypeName  = 'OSDAppClient.CacheClearResult'
        CachePath   = $cachePath
        Scope       = $scope
        Names       = @($Name)
        IncludeLogs = [bool]$IncludeLogs
        Removed     = @($removed)
    }
}
