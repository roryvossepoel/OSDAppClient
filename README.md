# OSD App Client

OSD App Client is a PowerShell module and standalone runtime for OSDCloud v2 application caching, staging, refresh, and pre-OOBE installation.

It is designed around a simple deployment model:

```text
WinPE
→ OSDCloud applies Windows and drivers
→ OSDAppClient synchronizes repository packages
→ Add-OSDApp stages selected applications

First boot / full Windows
→ built-in Office / Teams cache refresh
→ current payload is restaged
→ SetupComplete installs applications
→ temporary source is removed
→ OOBE / Autopilot continues
```

## Key concepts

OSD Apps supports two application sources:

| Source | Acquisition / sync | Installation |
| --- | --- | --- |
| Repository apps | WinPE | SetupComplete |
| Built-in Microsoft 365 Apps / Teams | Full Windows pre-install phase | SetupComplete |

Repository apps use the OSD Apps package contract: `Package.zip` with a root-level `Install.ps1`.

Built-in apps use vendor-native acquisition and installation:
- Microsoft 365 Apps uses the Office Deployment Tool.
- Microsoft Teams uses the Teams bootstrapper and official MSIX.

## Quick start

Typical WinPE flow after OSDCloud v2 has finished:

```powershell
Import-Module OSDAppClient

Set-OSDAppCatalog 'https://example.blob.core.windows.net/osdapps/catalog.json'

Sync-OSDAppRepository

Get-OSDApp

Add-OSDApp NotepadPlusPlus
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
```

For built-in cache configuration and synchronization on full Windows:

```powershell
Sync-OSDAppMicrosoft365Apps `
    -Channel Current `
    -Architecture 64 `
    -ProductId O365ProPlusRetail `
    -Language nl-nl,en-us

Sync-OSDAppTeams -Architecture x64
```

## Important: keep the USB connected

> **Keep the OSDCloud USB connected until OOBE is displayed.**

Repository packages are synchronized in WinPE immediately after OSDCloud completes.

OSD Apps can run built-in applications without USB media. If a USB volume labeled `OSDCloud` is connected, cache functionality is enabled automatically. Built-in Office and Teams content is synchronized/updated during SetupComplete in full Windows; without an `OSDCloud` USB cache, the content is acquired directly to the local Windows runtime. Repository applications currently use the OSDCloud cache and synchronize in WinPE after OSDCloud completes.

## Runtime locations

Temporary deployment source:

```text
%SystemRoot%\Temp\OSDApps
```

Persistent logs:

```text
%ProgramData%\OSDApps\Logs\Install.log
```

After a successful run, the temporary runtime/source directory is removed automatically. Logs remain available.

Use `-KeepSource` when troubleshooting:

```powershell
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
```

## Built-in applications

Currently supported:

```text
Microsoft365Apps
Teams
```

Each built-in has its own configuration/synchronization cmdlet and its own Add cmdlet:

```powershell
Sync-OSDAppMicrosoft365Apps
Sync-OSDAppTeams

Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
```

There is intentionally no generic `Sync-OSDAppBuiltIn` command. Each built-in owns its own parameter set and configuration.

See [Built-in applications](docs/built-in-apps.md).

## Repository applications

Repository packages remain compressed while cached and staged.

```text
Package.zip
├── Install.ps1
├── setup.exe / setup.msi / other payload
├── Config/
└── Files/
```

The package author is responsible for making `Install.ps1` completely unattended and suitable for SetupComplete.

See [Repository applications](docs/repository.md).

## Runtime behavior

The standalone runtime does not require the OSDAppClient module to be installed in Windows.

`Add-OSDApp` stages everything needed for the first boot:
- `DeviceManifest.json`
- `Invoke-OSDAppPreInstall.ps1`
- `Invoke-OSDAppRunner.ps1`
- repository packages
- built-in payloads

SetupComplete runs the standalone pre-install phase first and the installer second.

See [Runtime and cleanup](docs/runtime.md).

## Commands

Primary commands:

```text
Set-OSDAppCatalog
Get-OSDAppCatalog
Sync-OSDAppRepository
Sync-OSDAppMicrosoft365Apps
Sync-OSDAppTeams
Get-OSDApp
Add-OSDApp
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
Clear-OSDAppCache
```

Lower-level cache and staging commands are also exported for testing and advanced scenarios.

## Documentation

- [Architecture](docs/architecture.md)
- [Built-in applications](docs/built-in-apps.md)
- [Repository applications](docs/repository.md)
- [Runtime and cleanup](docs/runtime.md)
- [FAQ and troubleshooting](docs/faq.md)

## Related project

[OSDAppRepo](https://github.com/roryvossepoel/OSDAppRepo) is the companion authoring and repository-management module. It builds and validates packages and maintains the central `catalog.json`.
