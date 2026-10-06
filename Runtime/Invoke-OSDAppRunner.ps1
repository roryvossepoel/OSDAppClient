[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$StagedPath,
    [string[]]$Name
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $StagedPath 'DeviceManifest.json'
$workRoot = Join-Path $StagedPath 'Work'

function Initialize-RunnerLog {
    $logDirectory = Join-Path $env:ProgramData 'OSDApps\Logs'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    Join-Path $logDirectory 'Install.log'
}

function Write-RunnerLog {
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

    $type = switch ($Level) {
        'Warning' { 2 }
        'Error'   { 3 }
        default   { 1 }
    }

    $details = @()
    if ($Data) {
        foreach ($key in @($Data.Keys | Sort-Object)) {
            $value = $Data[$key]
            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                $value = @($value) -join ','
            }
            $details += ('{0}={1}' -f $key, $value)
        }
    }

    $logMessage = if ($Message) { "[$Event] $Message" } else { "[$Event]" }
    if ($details.Count -gt 0) {
        $logMessage += ' | ' + ($details -join '; ')
    }
    $logMessage = $logMessage -replace '\]LOG\]!>', ']LOG]! >'

    $now = (Get-Date).ToUniversalTime()
    $time = $now.ToString('HH:mm:ss.fff') + '+000'
    $date = $now.ToString('MM-dd-yyyy')
    $thread = [System.Threading.Thread]::CurrentThread.ManagedThreadId

    $line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="Install" context="" type="{3}" thread="{4}" file="">' -f $logMessage, $time, $date, $type, $thread
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Start-RunnerCleanup {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $cleanupScript = Join-Path $env:TEMP ("OSDApps-Cleanup-{0}.cmd" -f ([guid]::NewGuid().ToString('N')))
    $cleanupContent = @(
        '@echo off'
        'timeout /t 2 /nobreak >nul'
        ('rd /s /q "{0}"' -f $Path)
        'del /f /q "%~f0"'
    )

    Set-Content -LiteralPath $cleanupScript -Value $cleanupContent -Encoding ASCII

    Write-RunnerLog -LogPath $LogPath -Event 'CleanupScheduled' -Message 'Runtime source cleanup was scheduled.' -Data @{ Path = $Path; CleanupScript = $cleanupScript }

    Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',('"{0}"' -f $cleanupScript)) -WindowStyle Hidden | Out-Null
}

$logPath = $null

try {
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Device manifest not found: $manifestPath"
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $logPath = Initialize-RunnerLog
    Write-RunnerLog -LogPath $logPath -Event 'InstallStart' -Message 'OSD App Runner started.' -Data @{ StagedPath = $StagedPath }

    $packages = @($manifest.Packages)
    if ($Name) { $packages = @($packages | Where-Object { $_.Id -in $Name }) }

    New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

    foreach ($package in $packages) {
        $packageRoot = Join-Path $StagedPath (Join-Path 'Packages' $package.Id)
        $archivePath = Join-Path $packageRoot 'Package.zip'

        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            throw "Package.zip not found for '$($package.Id)': $archivePath"
        }

        if ($package.Archive -and $package.Archive.Sha256) {
            $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
            if ($actualHash -ne $package.Archive.Sha256) {
                Write-RunnerLog -LogPath $logPath -Event 'PackageIntegrityFailed' -Level 'Error' -Message 'Staged package SHA-256 validation failed.' -Data @{ Id = $package.Id; ExpectedSha256 = $package.Archive.Sha256; ActualSha256 = $actualHash; Archive = $archivePath }
                throw "SHA-256 validation failed for staged package '$($package.Id)'."
            }

            Write-RunnerLog -LogPath $logPath -Event 'PackageIntegrityValidated' -Message 'Staged package SHA-256 validation succeeded.' -Data @{ Id = $package.Id; Sha256 = $actualHash; Archive = $archivePath }
        }

        $packageWork = Join-Path $workRoot $package.Id
        if (Test-Path -LiteralPath $packageWork) {
            Remove-Item -LiteralPath $packageWork -Recurse -Force
        }
        New-Item -ItemType Directory -Path $packageWork -Force | Out-Null

        Write-RunnerLog -LogPath $logPath -Event 'PackageExtractStart' -Message 'Extracting package archive.' -Data @{ Id = $package.Id; Version = $package.Version; Archive = $archivePath }
        Expand-Archive -LiteralPath $archivePath -DestinationPath $packageWork -Force

        $payloadRoot = Join-Path $packageWork 'Package'
        $installScript = Join-Path $payloadRoot 'Install.ps1'
        if (-not (Test-Path -LiteralPath $installScript -PathType Leaf)) {
            throw "Package '$($package.Id)' does not contain Package\Install.ps1."
        }

        Write-RunnerLog -LogPath $logPath -Event 'PackageInstallStart' -Message 'Starting package installation.' -Data @{ Id = $package.Id; Version = $package.Version }

        $process = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installScript) -WorkingDirectory $payloadRoot -Wait -PassThru

        $successCodes = @(0,3010)
        if ($package.SuccessCodes) {
            $successCodes = @($package.SuccessCodes | ForEach-Object { [int]$_ })
        }

        if ($process.ExitCode -notin $successCodes) {
            throw "Installation of '$($package.Id)' failed with exit code $($process.ExitCode)."
        }

        Write-RunnerLog -LogPath $logPath -Event 'PackageInstallComplete' -Message 'Package installation completed.' -Data @{ Id = $package.Id; Version = $package.Version; ExitCode = $process.ExitCode }
    }

    $builtInApps = @()
    if ($manifest.PSObject.Properties.Name -contains 'BuiltInApps') {
        $builtInApps = @($manifest.BuiltInApps)
    }
    if ($Name) { $builtInApps = @($builtInApps | Where-Object { $_.Id -in $Name }) }

    # Keep built-in installation order deterministic. Microsoft 365 Apps is
    # installed before the other built-ins, while Adobe Acrobat Unified is
    # installed last. All remaining built-ins retain their manifest order.
    if ($builtInApps.Count -gt 1) {
        $officeApps = @($builtInApps | Where-Object { $_.Id -eq 'Microsoft365Apps' })
        $otherApps = @($builtInApps | Where-Object { $_.Id -notin @('Microsoft365Apps','AdobeAcrobatUnified') })
        $adobeApps = @($builtInApps | Where-Object { $_.Id -eq 'AdobeAcrobatUnified' })
        $builtInApps = @($officeApps) + @($otherApps) + @($adobeApps)
    }

    foreach ($app in $builtInApps) {
        switch ($app.Type) {
            'OfficeDeploymentTool' {
                $setupPath = Join-Path $StagedPath $app.Setup
                $configurationPath = Join-Path $StagedPath $app.Configuration
                $workingDirectory = Split-Path $setupPath -Parent

                if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
                    throw "Office setup executable not found: $setupPath"
                }
                if (-not (Test-Path -LiteralPath $configurationPath -PathType Leaf)) {
                    throw "Office configuration XML not found: $configurationPath"
                }

                $officeDataPath = Join-Path $workingDirectory 'Office\Data'
                $offlineOffice = Test-Path -LiteralPath $officeDataPath -PathType Container

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallStart' -Message 'Starting built-in Microsoft 365 Apps installation.' -Data @{ Id = $app.Id; Setup = $setupPath; Configuration = $configurationPath; Offline = $offlineOffice }

                $process = Start-Process -FilePath $setupPath -ArgumentList @('/configure', $configurationPath) -WorkingDirectory $workingDirectory -Wait -PassThru
                if ($process.ExitCode -notin @(0,3010)) {
                    throw "Installation of '$($app.Id)' failed with exit code $($process.ExitCode)."
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message 'Built-in Microsoft 365 Apps installation completed.' -Data @{ Id = $app.Id; ExitCode = $process.ExitCode }
            }
            'TeamsBootstrapper' {
                $setupPath = Join-Path $StagedPath $app.Setup
                $workingDirectory = Split-Path $setupPath -Parent

                if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
                    throw "Teams bootstrapper not found: $setupPath"
                }

                $arguments = @('-p')

                if ($app.OfflinePackage) {
                    $offlinePackagePath = Join-Path $StagedPath $app.OfflinePackage
                    if (-not (Test-Path -LiteralPath $offlinePackagePath -PathType Leaf)) {
                        throw "Teams offline MSIX not found: $offlinePackagePath"
                    }

                    $arguments += '-o'
                    $arguments += $offlinePackagePath
                }

                if ($app.InstallMeetingAddin -eq $true) {
                    $arguments += '--installTMA'
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallStart' -Message 'Starting built-in Microsoft Teams provisioning.' -Data @{ Id = $app.Id; Setup = $setupPath; Arguments = ($arguments -join ' '); Offline = [bool]$app.OfflinePackage }

                $process = Start-Process -FilePath $setupPath -ArgumentList $arguments -WorkingDirectory $workingDirectory -Wait -PassThru
                if ($process.ExitCode -ne 0) {
                    throw "Installation of '$($app.Id)' failed with exit code $($process.ExitCode)."
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message 'Built-in Microsoft Teams provisioning completed.' -Data @{ Id = $app.Id; ExitCode = $process.ExitCode }
            }
            'AdobeAcrobatUnifiedZip' {
                $packagePath = Join-Path $StagedPath $app.Package
                if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
                    throw "Adobe Acrobat Unified package not found: $packagePath"
                }

                $adobeWork = Join-Path $workRoot 'AdobeAcrobatUnified'
                if (Test-Path -LiteralPath $adobeWork) {
                    Remove-Item -LiteralPath $adobeWork -Recurse -Force
                }
                New-Item -ItemType Directory -Path $adobeWork -Force | Out-Null

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInExtractStart' -Message 'Extracting Adobe Acrobat Unified package.' -Data @{ Id=$app.Id; Archive=$packagePath; Destination=$adobeWork }
                Expand-Archive -LiteralPath $packagePath -DestinationPath $adobeWork -Force

                $setupPath = Get-ChildItem -LiteralPath $adobeWork -Filter 'Setup.exe' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
                if (-not $setupPath) {
                    throw "Adobe Acrobat Unified Setup.exe was not found after extracting '$packagePath'."
                }

                $arguments = if ($app.InstallArguments) { [string]$app.InstallArguments } else { '/sAll /msi ADDLOCAL=ALL' }
                $workingDirectory = Split-Path $setupPath -Parent

                $timeoutMinutes = if ($app.InstallTimeoutMinutes) { [int]$app.InstallTimeoutMinutes } else { 15 }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallStart' -Message 'Starting built-in Adobe Acrobat Unified installation.' -Data @{ Id=$app.Id; Setup=$setupPath; Arguments=$arguments; Offline=$true; TimeoutMinutes=$timeoutMinutes }

                $process = Start-Process -FilePath $setupPath -ArgumentList $arguments -WorkingDirectory $workingDirectory -PassThru
                $installStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $nextHeartbeat = [TimeSpan]::FromMinutes(1)

                while (-not $process.HasExited) {
                    if ($installStopwatch.Elapsed.TotalMinutes -ge $timeoutMinutes) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallTimeout' -Level 'Error' -Message 'Adobe Acrobat Unified installation exceeded its timeout.' -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds); TimeoutMinutes=$timeoutMinutes }

                        try {
                            Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID',[string]$process.Id,'/T','/F') -WindowStyle Hidden -Wait | Out-Null
                        }
                        catch { }

                        throw "Installation of '$($app.Id)' exceeded the $timeoutMinutes minute timeout."
                    }

                    if ($installStopwatch.Elapsed -ge $nextHeartbeat) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallWaiting' -Message 'Adobe Acrobat Unified installation is still running.' -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                        $nextHeartbeat = $nextHeartbeat.Add([TimeSpan]::FromMinutes(1))
                    }

                    Start-Sleep -Seconds 2
                    $process.Refresh()
                }

                $installStopwatch.Stop()

                if ($process.ExitCode -notin @(0,3010)) {
                    throw "Installation of '$($app.Id)' failed with exit code $($process.ExitCode)."
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message 'Built-in Adobe Acrobat Unified installation completed.' -Data @{ Id=$app.Id; ExitCode=$process.ExitCode; DurationSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
            }
            'VendorMsi' {
                $packagePath = Join-Path $StagedPath $app.Package
                if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
                    throw "MSI package not found for '$($app.Id)': $packagePath"
                }

                $displayName = if ($app.DisplayName) { [string]$app.DisplayName } else { [string]$app.Id }
                $timeoutMinutes = if ($app.InstallTimeoutMinutes) { [int]$app.InstallTimeoutMinutes } else { 10 }
                $arguments = @('/i', ('"{0}"' -f $packagePath), '/qn', '/norestart')
                if ($app.PSObject.Properties.Name -contains 'MsiProperties' -and $app.MsiProperties) {
                    $arguments += @($app.MsiProperties)
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallStart' -Message "Starting built-in $displayName MSI installation." -Data @{ Id=$app.Id; Package=$packagePath; Arguments=($arguments -join ' '); Offline=$true; TimeoutMinutes=$timeoutMinutes }

                $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -PassThru
                $installStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                $nextHeartbeat = [TimeSpan]::FromMinutes(1)

                while (-not $process.HasExited) {
                    if ($installStopwatch.Elapsed.TotalMinutes -ge $timeoutMinutes) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallTimeout' -Level 'Error' -Message "$displayName installation exceeded its timeout." -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds); TimeoutMinutes=$timeoutMinutes }

                        try {
                            Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID',[string]$process.Id,'/T','/F') -WindowStyle Hidden -Wait | Out-Null
                        }
                        catch { }

                        throw "Installation of '$($app.Id)' exceeded the $timeoutMinutes minute timeout."
                    }

                    if ($installStopwatch.Elapsed -ge $nextHeartbeat) {
                        Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallWaiting' -Message "$displayName installation is still running." -Data @{ Id=$app.Id; ProcessId=$process.Id; ElapsedSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
                        $nextHeartbeat = $nextHeartbeat.Add([TimeSpan]::FromMinutes(1))
                    }

                    Start-Sleep -Seconds 2
                    $process.Refresh()
                }

                $installStopwatch.Stop()

                if ($process.ExitCode -notin @(0,3010)) {
                    throw "Installation of '$($app.Id)' failed with exit code $($process.ExitCode)."
                }

                Write-RunnerLog -LogPath $logPath -Event 'BuiltInInstallComplete' -Message "Built-in $displayName installation completed." -Data @{ Id=$app.Id; ExitCode=$process.ExitCode; DurationSeconds=[math]::Round($installStopwatch.Elapsed.TotalSeconds) }
            }
            default {
                throw "Unsupported built-in application type '$($app.Type)' for '$($app.Id)'."
            }
        }
    }

    $keepSource = $false
    if (
        $manifest.PSObject.Properties.Name -contains 'Runtime' -and
        $manifest.Runtime -and
        $manifest.Runtime.PSObject.Properties.Name -contains 'KeepSource'
    ) {
        $keepSource = [bool]$manifest.Runtime.KeepSource
    }

    Write-RunnerLog -LogPath $logPath -Event 'InstallComplete' -Message 'OSD App Runner completed successfully.' -Data @{ PackageCount = @($packages).Count; BuiltInAppCount = @($builtInApps).Count; KeepSource = $keepSource }

    if ($keepSource) {
        Write-RunnerLog -LogPath $logPath -Event 'CleanupSkipped' -Message 'Runtime source cleanup was skipped because KeepSource is enabled.' -Data @{ Path = $StagedPath }
    }
    else {
        Start-RunnerCleanup -Path $StagedPath -LogPath $logPath
    }

    exit 0
}
catch {
    if (-not $logPath) {
        try {
            $fallbackDir = Join-Path $env:ProgramData 'OSDApps\Logs'
            New-Item -ItemType Directory -Path $fallbackDir -Force | Out-Null
            $logPath = Join-Path $fallbackDir 'Install.log'
        }
        catch { }
    }

    if ($logPath) {
        Write-RunnerLog -LogPath $logPath -Event 'InstallFailed' -Level 'Error' -Message $_.Exception.Message
    }

    exit 1
}
