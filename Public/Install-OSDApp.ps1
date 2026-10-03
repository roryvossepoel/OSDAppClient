function Install-OSDApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$StagedPath,

        [string[]]$Name
    )

    $runner = Join-Path $StagedPath 'Invoke-OSDAppInstall.ps1'
    if (-not (Test-Path -LiteralPath $runner)) {
        throw "OSD Apps runtime not found: $runner"
    }

    $arguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $runner,
        '-StagedPath', $StagedPath
    )

    if ($Name) {
        $arguments += '-Name'
        $arguments += $Name
    }

    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "OSD Apps runtime returned exit code $($process.ExitCode)."
    }
}
