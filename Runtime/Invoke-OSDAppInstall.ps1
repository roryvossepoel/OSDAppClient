[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$StagedPath,
    [string[]]$Name
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $StagedPath 'DeviceManifest.json'
$logPath = Join-Path $StagedPath 'Install.log'
$workRoot = Join-Path $StagedPath 'Work'

function Write-RuntimeLog {
    param([string]$Message)
    $line = '{0:u} {1}' -f (Get-Date), $Message
    $line | Tee-Object -FilePath $logPath -Append
}

try {
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Device manifest not found: $manifestPath" }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
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
        if (Test-Path -LiteralPath $packageWork) { Remove-Item -LiteralPath $packageWork -Recurse -Force }
        New-Item -ItemType Directory -Path $packageWork -Force | Out-Null

        Write-RuntimeLog "Extracting $($package.Id) $($package.Version)"
        Expand-Archive -LiteralPath $archivePath -DestinationPath $packageWork -Force

        $installScript = Join-Path $packageWork 'Install.ps1'
        if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
            throw "Package '$($package.Id)' does not contain Install.ps1 at the root of Package.zip."
        }

        Write-RuntimeLog "Installing $($package.Id) $($package.Version)"
        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installScript) -WorkingDirectory $packageWork -Wait -PassThru

        $successCodes = @(0,3010)
        if ($package.SuccessCodes) { $successCodes = @($package.SuccessCodes | ForEach-Object { [int]$_ }) }

        if ($process.ExitCode -notin $successCodes) {
            throw "Installation of '$($package.Id)' failed with exit code $($process.ExitCode)."
        }

        Write-RuntimeLog "Installed $($package.Id) successfully (exit code $($process.ExitCode))."
    }

    Write-RuntimeLog 'OSD Apps runtime completed successfully.'
    exit 0
}
catch {
    Write-RuntimeLog "ERROR: $($_.Exception.Message)"
    exit 1
}
