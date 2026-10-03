function Add-OSDAppSetupComplete {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$WindowsPath,

        [string]$StagedRelativePath = 'OSDApps'
    )

    $scriptsPath = Join-Path $WindowsPath 'Windows\Setup\Scripts'
    $setupComplete = Join-Path $scriptsPath 'SetupComplete.cmd'

    New-Item -ItemType Directory -Path $scriptsPath -Force | Out-Null

    $begin = ':: OSDApps Begin'
    $end   = ':: OSDApps End'
    $runnerPath = "%SystemDrive%\$StagedRelativePath\Invoke-OSDAppRunner.ps1"

    $block = @(
        $begin
        ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}" -StagedPath "%SystemDrive%\{1}"' -f $runnerPath, $StagedRelativePath)
        'set "OSDAPPS_EXITCODE=%ERRORLEVEL%"'
        'if not "%OSDAPPS_EXITCODE%"=="0" exit /b %OSDAPPS_EXITCODE%'
        $end
    )

    if (-not (Test-Path -LiteralPath $setupComplete)) {
        if ($PSCmdlet.ShouldProcess($setupComplete, 'Create SetupComplete.cmd and append OSD Apps block')) {
            '@echo off' | Set-Content -LiteralPath $setupComplete -Encoding ASCII
            Add-Content -LiteralPath $setupComplete -Value $block -Encoding ASCII
        }

        return Get-Item -LiteralPath $setupComplete
    }

    $existing = Get-Content -LiteralPath $setupComplete -Raw -ErrorAction Stop

    if ($existing -match [regex]::Escape($begin)) {
        Write-Verbose 'OSD Apps block already exists. Existing SetupComplete.cmd is left unchanged.'
        return Get-Item -LiteralPath $setupComplete
    }

    if ($PSCmdlet.ShouldProcess($setupComplete, 'Append OSD Apps block to existing SetupComplete.cmd')) {
        # Additive-only behavior: never rewrite, replace, reorder, or remove existing content.
        # Ensure the appended block starts on a new line even if the current file has no trailing newline.
        $bytes = [System.IO.File]::ReadAllBytes($setupComplete)
        if ($bytes.Length -gt 0) {
            $lastByte = $bytes[$bytes.Length - 1]
            if ($lastByte -ne 10 -and $lastByte -ne 13) {
                Add-Content -LiteralPath $setupComplete -Value '' -Encoding ASCII
            }
        }

        Add-Content -LiteralPath $setupComplete -Value $block -Encoding ASCII
    }

    Get-Item -LiteralPath $setupComplete
}
