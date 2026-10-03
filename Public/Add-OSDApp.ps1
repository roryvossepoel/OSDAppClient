function Add-OSDApp {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string[]]$Name
    )

    begin {
        $requestedApps = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($item in $Name) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $requestedApps.Add($item)
            }
        }
    }

    end {
        $uniqueApps = @($requestedApps | Select-Object -Unique)
        if ($uniqueApps.Count -eq 0) {
            throw 'No applications were supplied.'
        }

        $cachePath = Get-OSDAppCachePath
        $cacheManifestPath = Join-Path $cachePath 'CacheManifest.json'

        if (-not (Test-Path -LiteralPath $cacheManifestPath -PathType Leaf)) {
            throw "OSD App cache manifest not found: $cacheManifestPath. Run Sync-OSDAppRepository first."
        }

        $windowsCandidates = @(
            Get-Volume -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveLetter -and $_.DriveLetter -ne 'X' } |
                ForEach-Object {
                    $root = "$($_.DriveLetter):\"
                    $systemHive = Join-Path $root 'Windows\System32\Config\SYSTEM'

                    if (Test-Path -LiteralPath $systemHive -PathType Leaf) {
                        $root
                    }
                }
        )

        if ($windowsCandidates.Count -eq 0) {
            throw 'No offline Windows installation was found.'
        }

        if ($windowsCandidates.Count -gt 1) {
            throw "Multiple Windows installations were found: $($windowsCandidates -join ', ')."
        }

        $windowsPath = $windowsCandidates[0]

        if ($PSCmdlet.ShouldProcess(($uniqueApps -join ', '), "Stage applications for SetupComplete on $windowsPath")) {
            Copy-OSDAppContent -Name $uniqueApps -CachePath $cachePath -WindowsPath $windowsPath
            Add-OSDAppSetupComplete -WindowsPath $windowsPath | Out-Null
        }

        foreach ($app in $uniqueApps) {
            [pscustomobject]@{
                PSTypeName  = 'OSDAppClient.StagedApp'
                Name        = $app
                CachePath   = $cachePath
                WindowsPath = $windowsPath
                StagedPath  = Join-Path $windowsPath 'OSDApps'
            }
        }
    }
}
