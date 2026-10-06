function Add-OSDAppSetupComplete {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsPath,

        [string]$StagedRelativePath = 'Windows\Temp\OSDApps'
    )

    $scriptsPath = Join-Path $WindowsPath 'Windows\Setup\Scripts'
    $setupComplete = Join-Path $scriptsPath 'SetupComplete.cmd'
    $stagedRoot = Join-Path $WindowsPath $StagedRelativePath

    New-Item -ItemType Directory -Path $scriptsPath -Force | Out-Null
    New-Item -ItemType Directory -Path $stagedRoot -Force | Out-Null

    $moduleRoot = Split-Path $PSScriptRoot -Parent
    $runnerSource = Join-Path $moduleRoot 'Runtime\Invoke-OSDAppRunner.ps1'
    $preInstallSource = Join-Path $moduleRoot 'Runtime\Invoke-OSDAppPreInstall.ps1'

    if (-not (Test-Path -LiteralPath $runnerSource -PathType Leaf)) {
        throw "OSD App runner was not found: $runnerSource"
    }

    if (-not (Test-Path -LiteralPath $preInstallSource -PathType Leaf)) {
        throw "OSD App pre-install runtime was not found: $preInstallSource"
    }

    if ($PSCmdlet.ShouldProcess($stagedRoot, 'Stage OSD Apps runtime scripts')) {
        Copy-Item -LiteralPath $runnerSource -Destination (Join-Path $stagedRoot 'Invoke-OSDAppRunner.ps1') -Force
        Copy-Item -LiteralPath $preInstallSource -Destination (Join-Path $stagedRoot 'Invoke-OSDAppPreInstall.ps1') -Force
    }

    $preInstallMarker = ':: OSDApps PreInstall'
    $begin = ':: OSDApps Begin'
    $end   = ':: OSDApps End'

    $preInstallPath = "%SystemDrive%\$StagedRelativePath\Invoke-OSDAppPreInstall.ps1"
    $runnerPath = "%SystemDrive%\$StagedRelativePath\Invoke-OSDAppRunner.ps1"

    $preInstallBlock = @(
        $preInstallMarker
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -StagedPath "%SystemDrive%\{1}"' -f $preInstallPath, $StagedRelativePath)
        'set "OSDAPPS_PREINSTALL_EXITCODE=%ERRORLEVEL%"'
        'if not "%OSDAPPS_PREINSTALL_EXITCODE%"=="0" exit /b %OSDAPPS_PREINSTALL_EXITCODE%'
    )

    $runnerBlock = @(
        $begin
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -StagedPath "%SystemDrive%\{1}"' -f $runnerPath, $StagedRelativePath)
        'set "OSDAPPS_EXITCODE=%ERRORLEVEL%"'
        'if not "%OSDAPPS_EXITCODE%"=="0" exit /b %OSDAPPS_EXITCODE%'
        $end
    )

    if (-not (Test-Path -LiteralPath $setupComplete)) {
        if ($PSCmdlet.ShouldProcess($setupComplete, 'Create SetupComplete.cmd and append OSD Apps blocks')) {
            '@echo off' | Set-Content -LiteralPath $setupComplete -Encoding ASCII
            Add-Content -LiteralPath $setupComplete -Value $preInstallBlock -Encoding ASCII
            Add-Content -LiteralPath $setupComplete -Value $runnerBlock -Encoding ASCII
        }

        return Get-Item -LiteralPath $setupComplete
    }

    $existing = Get-Content -LiteralPath $setupComplete -Raw -ErrorAction Stop
    $hasPreInstall = $existing -match [regex]::Escape($preInstallMarker)
    $hasRunner = $existing -match [regex]::Escape($begin)

    if ($hasPreInstall -and $hasRunner) {
        if ($PSCmdlet.ShouldProcess($setupComplete, 'Refresh existing OSD Apps SetupComplete blocks')) {
            $existingText = [System.IO.File]::ReadAllText($setupComplete)
            $lineEnding = if ($existingText -match "`r`n") { "`r`n" } else { "`n" }

            $desiredBlock = @(
                $preInstallBlock
                $runnerBlock
            ) -join $lineEnding

            $pattern = '(?ms)^:: OSDApps PreInstall\r?\n.*?^:: OSDApps End(?:\r?\n)?'
            if (-not [regex]::IsMatch($existingText, $pattern)) {
                throw 'Existing OSD Apps SetupComplete block could not be parsed for refresh.'
            }

            $updatedText = [regex]::Replace(
                $existingText,
                $pattern,
                [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $desiredBlock + $lineEnding },
                1
            )

            [System.IO.File]::WriteAllText(
                $setupComplete,
                $updatedText,
                [System.Text.Encoding]::ASCII
            )

            Write-Verbose 'Existing OSD Apps SetupComplete blocks were refreshed.'
        }

        return Get-Item -LiteralPath $setupComplete
    }

    if ($hasRunner -and -not $hasPreInstall) {
        if ($PSCmdlet.ShouldProcess($setupComplete, 'Insert OSD Apps pre-install block before existing OSD Apps runner block')) {
            $bytes = [System.IO.File]::ReadAllBytes($setupComplete)
            $markerBytes = [System.Text.Encoding]::ASCII.GetBytes($begin)

            $markerIndex = -1
            for ($i = 0; $i -le ($bytes.Length - $markerBytes.Length); $i++) {
                $match = $true
                for ($j = 0; $j -lt $markerBytes.Length; $j++) {
                    if ($bytes[$i + $j] -ne $markerBytes[$j]) {
                        $match = $false
                        break
                    }
                }

                if ($match) {
                    $markerIndex = $i
                    break
                }
            }

            if ($markerIndex -lt 0) {
                throw 'Existing OSD Apps runner marker could not be located in SetupComplete.cmd.'
            }

            $lineEnding = [Environment]::NewLine
            if ($markerIndex -gt 0 -and $bytes[$markerIndex - 1] -eq 10 -and ($markerIndex -lt 2 -or $bytes[$markerIndex - 2] -ne 13)) {
                $lineEnding = [char]10
            }

            $insertText = ($preInstallBlock -join $lineEnding) + $lineEnding
            $insertBytes = [System.Text.Encoding]::ASCII.GetBytes($insertText)

            $newBytes = New-Object byte[] ($bytes.Length + $insertBytes.Length)
            [System.Buffer]::BlockCopy($bytes, 0, $newBytes, 0, $markerIndex)
            [System.Buffer]::BlockCopy($insertBytes, 0, $newBytes, $markerIndex, $insertBytes.Length)
            [System.Buffer]::BlockCopy($bytes, $markerIndex, $newBytes, ($markerIndex + $insertBytes.Length), ($bytes.Length - $markerIndex))

            [System.IO.File]::WriteAllBytes($setupComplete, $newBytes)
        }

        return Get-Item -LiteralPath $setupComplete
    }

    if ($PSCmdlet.ShouldProcess($setupComplete, 'Append OSD Apps pre-install and runner blocks to existing SetupComplete.cmd')) {
        $bytes = [System.IO.File]::ReadAllBytes($setupComplete)
        if ($bytes.Length -gt 0) {
            $lastByte = $bytes[$bytes.Length - 1]
            if ($lastByte -ne 10 -and $lastByte -ne 13) {
                Add-Content -LiteralPath $setupComplete -Value '' -Encoding ASCII
            }
        }

        Add-Content -LiteralPath $setupComplete -Value $preInstallBlock -Encoding ASCII
        Add-Content -LiteralPath $setupComplete -Value $runnerBlock -Encoding ASCII
    }

    Get-Item -LiteralPath $setupComplete
}
