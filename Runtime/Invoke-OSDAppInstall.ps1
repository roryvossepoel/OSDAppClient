[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$StagedPath,
    [string[]]$Name
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $StagedPath 'DeviceManifest.json'
$workRoot = Join-Path $StagedPath 'Work'

function Initialize-RuntimeLog {
    param(
        [string]$RequestedPath,
        [string]$FallbackRoot
    )

    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        $RequestedPath = '%SystemDrive%\OSDApps\Logs'
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($RequestedPath)

    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $expanded = Join-Path $FallbackRoot $expanded
    }

    New-Item -ItemType Directory -Path $expanded -Force | Out-Null
    Join-Path $expanded 'Install.log'
}

function Write-RuntimeLog {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Event,
        [ValidateSet('Info','Warning','Error')][string]$Level = 'Info',
        [string]$Message,
        [hashtable]$Data,
        [int]$MaxSizeMB = 1,
        [int]$RetainFiles = 3
    )

    if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
        $maxBytes = $MaxSizeMB * 1MB
        if ((Get-Item -LiteralPath $LogPath).Length -ge $maxBytes) {
            for ($i = $RetainFiles - 1; $i -ge 1; $i--) {
                $source = "$LogPath.$i"
                $target = "$LogPath.$($i + 1)"
                if (Test-Path -LiteralPath $source) {
                    Move-Item -LiteralPath $source -Destination $target -Force
                }
            }

            Move-Item -LiteralPath $LogPath -Destination "$LogPath.1" -Force
            $oldest = "$LogPath.$($RetainFiles + 1)"
            if (Test-Path -LiteralPath $oldest) {
                Remove-Item -LiteralPath $oldest -Force
            }
        }
    }

    $entry = [ordered]@{
        Timestamp = (Get-Date).ToUniversalTime().ToString('o')
        Level     = $Level
        Component = 'Install'
        Event     = $Event
        Message   = $Message
    }

    if ($Data) {
        $entry.Data = $Data
    }

    ($entry | ConvertTo-Json -Compress -Depth 10) |
        Add-Content -LiteralPath $LogPath -Encoding UTF8
}

$logPath = $null

try {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Device manifest not found: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $requestedLogPath = $null
    if ($manifest.Runtime -and $manifest.Runtime.LogPath) {
        $requestedLogPath = [string]$manifest.Runtime.LogPath
    }

    $logPath = Initialize-RuntimeLog -RequestedPath $requestedLogPath -FallbackRoot $StagedPath
    Write-RuntimeLog -LogPath $logPath -Event 'InstallStart' -Message 'OSD Apps installation runtime started.' -Data @{ StagedPath = $StagedPath }

    $packages = @($manifest.Packages)
    if ($Name) { $packages = $packages | Where-Object { $_.Id -in $Name } }

    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    foreach ($package in $packages) {
        $packageRoot = Join-Path $StagedPath (Join-Path 'Packages' $package.Id)
        $archivePath = Join-Path $packageRoot 'Package.zip'

        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            throw "Package.zip not found for '$($package.Id)': $archivePath"
        }

        $packageWork = Join-Path $workRoot $package.Id
        if (Test-Path -LiteralPath $packageWork) {
            Remove-Item -LiteralPath $packageWork -Recurse -Force
        }
        New-Item -ItemType Directory -Path $packageWork -Force | Out-Null

        Write-RuntimeLog -LogPath $logPath -Event 'PackageExtractStart' -Message 'Extracting package archive.' -Data @{ Id = $package.Id; Version = $package.Version; Archive = $archivePath }
        Expand-Archive -LiteralPath $archivePath -DestinationPath $packageWork -Force

        $installScript = Join-Path $packageWork 'Install.ps1'
        if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
            throw "Package '$($package.Id)' does not contain Install.ps1 at the root of Package.zip."
        }

        Write-RuntimeLog -LogPath $logPath -Event 'PackageInstallStart' -Message 'Starting package installation.' -Data @{ Id = $package.Id; Version = $package.Version }

        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installScript) -WorkingDirectory $packageWork -Wait -PassThru

        $successCodes = @(0,3010)
        if ($package.SuccessCodes) {
            $successCodes = @($package.SuccessCodes | ForEach-Object { [int]$_ })
        }

        if ($process.ExitCode -notin $successCodes) {
            throw "Installation of '$($package.Id)' failed with exit code $($process.ExitCode)."
        }

        Write-RuntimeLog -LogPath $logPath -Event 'PackageInstallComplete' -Message 'Package installation completed.' -Data @{ Id = $package.Id; Version = $package.Version; ExitCode = $process.ExitCode }
    }

    Write-RuntimeLog -LogPath $logPath -Event 'InstallComplete' -Message 'OSD Apps installation runtime completed successfully.' -Data @{ PackageCount = @($packages).Count }
    exit 0
}
catch {
    if (-not $logPath) {
        try {
            $fallbackDir = Join-Path $StagedPath 'Logs'
            New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null
            $logPath = Join-Path $fallbackDir 'Install.log'
        }
        catch { }
    }

    if ($logPath) {
        Write-RuntimeLog -LogPath $logPath -Event 'InstallFailed' -Level 'Error' -Message $_.Exception.Message
    }

    exit 1
}
