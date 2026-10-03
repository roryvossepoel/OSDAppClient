function Add-OSDApp {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]$Name
    )

    $osdCloudVolumes = @(
        Get-Volume -ErrorAction Stop |
            Where-Object {
                $_.FileSystemLabel -eq 'OSDCloud' -and
                $_.DriveLetter
            }
    )

    if ($osdCloudVolumes.Count -eq 0) {
        throw "No volume with label 'OSDCloud' was found."
    }

    if ($osdCloudVolumes.Count -gt 1) {
        throw "Multiple volumes with label 'OSDCloud' were found. OSD Apps cannot determine which cache to use."
    }

    $cachePath = "$($osdCloudVolumes[0].DriveLetter):\OSDApps"
    $cacheManifestPath = Join-Path $cachePath 'CacheManifest.json'

    if (-not (Test-Path -LiteralPath $cacheManifestPath -PathType Leaf)) {
        throw "OSD Apps cache manifest not found: $cacheManifestPath"
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

    if ($PSCmdlet.ShouldProcess(($Name -join ', '), "Add applications to deployment on $windowsPath")) {
        Copy-OSDAppContent -Name $Name -CachePath $cachePath -WindowsPath $windowsPath
        Add-OSDAppSetupComplete -WindowsPath $windowsPath | Out-Null
    }

    [pscustomobject]@{
        Name        = @($Name)
        CachePath   = $cachePath
        WindowsPath = $windowsPath
        StagedPath  = Join-Path $windowsPath 'OSDApps'
    }
}
