# Repository applications

Repository applications use the OSD Apps package contract.

## Package contract

Every application is represented by a single `Package.zip`.

The payload can contain any files required by the application, including EXE and MSI installers.

```text
Package.zip
├── Install.ps1
├── setup.exe
├── setup.msi
├── Config/
├── Modules/
└── Files/
```

Only `Install.ps1` is mandatory at the archive root. OSD Apps does not require the installer itself to be an EXE; the package author decides how the payload is installed.

## Package author responsibility

Repository packages run during SetupComplete before interactive OOBE / Autopilot.

The package author is responsible for:
- fully unattended installation;
- vendor-supported silent switches;
- prerequisite validation;
- waiting for child processes;
- handling exit codes;
- meaningful application-specific logging when useful;
- avoiding prompts or UI;
- predictable failure behavior.

Default success codes are:

```text
0
3010
```

Packages can define their own `SuccessCodes` metadata.


## Install.ps1 examples

### EXE installer

A typical silent EXE installer:

```powershell
$ErrorActionPreference = 'Stop'

$installer = Join-Path $PSScriptRoot 'setup.exe'

if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Installer not found: $installer"
}

$process = Start-Process `
    -FilePath $installer `
    -ArgumentList '/S' `
    -WorkingDirectory $PSScriptRoot `
    -Wait `
    -PassThru

if ($process.ExitCode -notin @(0,3010)) {
    throw "Installer failed with exit code $($process.ExitCode)."
}

exit $process.ExitCode
```

The silent arguments are vendor-specific. Package authors must use the switches supported by the application vendor.

### MSI installer

MSI packages can be installed directly with `msiexec.exe`.

This example also writes a verbose MSI log alongside the persistent OSD Apps runtime log under `%ProgramData%\OSDApps\Logs`:

```powershell
$ErrorActionPreference = 'Stop'

$installer = Join-Path $PSScriptRoot 'setup.msi'
$logDirectory = Join-Path $env:ProgramData 'OSDApps\Logs'
$msiLog = Join-Path $logDirectory 'ExampleApp-MSI.log'

if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Installer not found: $installer"
}

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

$arguments = @(
    '/i'
    ('"{0}"' -f $installer)
    '/qn'
    '/norestart'
    '/L*v'
    ('"{0}"' -f $msiLog)
)

$process = Start-Process `
    -FilePath 'msiexec.exe' `
    -ArgumentList $arguments `
    -WorkingDirectory $PSScriptRoot `
    -Wait `
    -PassThru

if ($process.ExitCode -notin @(0,3010)) {
    throw "MSI installation failed with exit code $($process.ExitCode). See $msiLog."
}

exit $process.ExitCode
```

Because the MSI log is written to `%ProgramData%\OSDApps\Logs`, it is preserved even when the temporary runtime source under `%SystemRoot%\Temp\OSDApps` is cleaned up after a successful deployment.

## Repository layout

```text
Repository/
├── catalog.json
└── Packages/
    └── <AppId>/
        └── <Version>/
            └── <Architecture>/
                └── Package.zip
```

Supported architectures:

```text
x64
arm64
any
```

Resolution order:
1. exact architecture;
2. `any`;
3. fail.

OSD Apps does not silently run x64 repository packages on ARM64.

## WinPE flow

```powershell
Set-OSDAppCatalog 'https://example.blob.core.windows.net/osdapps/catalog.json'

# Status only: URI, availability and package count
Get-OSDAppCatalog

# Populate/update <OSDCloud>:\OSDApps\Packages and CacheCatalog.json
Sync-OSDAppRepository

# Unified application discovery
Get-OSDApp

Add-OSDApp NotepadPlusPlus
```

Repository packages are synchronized and SHA-256 validated in WinPE.

The runner validates the staged package hash again before extraction and installation.

## Installation order

Repository packages are installed in the order supplied to `Add-OSDApp`.

```powershell
Add-OSDApp VCPlusPlusRuntime,LineOfBusinessApp
```

Built-ins use their dedicated commands:

```powershell
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
```

`Add-OSDApp` is repository-only and returns a clear error if a built-in application is passed to it.


## Local cache metadata

Repository synchronization writes:

```text
<OSDCloud>:\OSDApps\CacheCatalog.json
<OSDCloud>:\OSDApps\Packages\<AppId>\Package.zip
```

`CacheCatalog.json` is the local snapshot of repository packages selected for the current WinPE architecture. It is intentionally distinct from the online `catalog.json` and the per-device `DeviceManifest.json`.
