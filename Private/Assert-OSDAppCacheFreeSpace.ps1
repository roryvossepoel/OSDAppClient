function Assert-OSDAppCacheFreeSpace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [double]$MinimumFreeSpaceGB,

        [Parameter(Mandatory)]
        [string]$Operation,

        [string]$LogPath
    )

    $driveLetter = [System.IO.Path]::GetPathRoot($CachePath).TrimEnd('\').TrimEnd(':')
    $volume = Get-Volume -DriveLetter $driveLetter -ErrorAction Stop

    $freeBytes = [double]$volume.SizeRemaining
    $requiredBytes = $MinimumFreeSpaceGB * 1GB
    $freeGB = [math]::Round($freeBytes / 1GB, 2)

    if ($LogPath) {
        Write-OSDAppLog -LogPath $LogPath -Component 'Cache' -Event 'FreeSpaceCheck' -Message 'Checked free space on the OSDCloud cache volume.' -Data @{
            Operation          = $Operation
            DriveLetter        = $driveLetter
            FreeSpaceGB        = $freeGB
            MinimumFreeSpaceGB = $MinimumFreeSpaceGB
        }
    }

    if ($freeBytes -lt $requiredBytes) {
        throw ('Insufficient free space on OSDCloud volume {0}: {1} GB available; {2} GB required before {3}.' -f $driveLetter, $freeGB, $MinimumFreeSpaceGB, $Operation)
    }

    [pscustomobject]@{
        DriveLetter        = $driveLetter
        FreeSpaceGB        = $freeGB
        MinimumFreeSpaceGB = $MinimumFreeSpaceGB
        Sufficient         = $true
    }
}
