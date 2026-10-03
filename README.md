# OSD Apps Client

OSD Apps Client is a PowerShell module for Windows PE, designed specifically to complement OSDCloud v2.

It runs after OSDCloud v2 has applied Windows and drivers. The module consumes a prepared OSD Apps repository, synchronizes and validates application packages, stages selected packages to the offline Windows volume, and appends a SetupComplete hook so the applications are installed before OOBE.

## Scope

OSD Apps Client does not build application packages and does not authenticate to Intune or Microsoft Graph.

It consumes repositories that follow the OSD Apps repository contract.

Supported repository locations:
- Local path
- UNC path
- HTTP/HTTPS

## Package contract

Every application is represented by a single archive named `Package.zip`.

`Package.zip` must contain `Install.ps1` at the archive root.

Example:

```text
Package.zip
├── Install.ps1
├── setup.exe
├── Config/
├── Modules/
└── Files/
```

The ZIP remains compressed while it is stored, cached, and staged. It is extracted only at installation time.

## Runtime flow

```text
OSDCloud v2 in WinPE
        ↓
Windows + drivers applied
        ↓
OSDAppsClient
        ↓
Read repository manifest
        ↓
Sync / validate Package.zip
        ↓
Stage selected packages to offline Windows
        ↓
Append SetupComplete.cmd
        ↓
Reboot into installed Windows
        ↓
OSD Apps Runner
        ↓
Expand Package.zip
        ↓
Run Install.ps1
        ↓
OOBE / Autopilot
```

## Initial commands

```powershell
Get-OSDApp
Sync-OSDAppCache
Test-OSDAppCache
Copy-OSDAppContent
Add-OSDAppSetupComplete
Install-OSDApp
```

## Example

```powershell
Import-Module OSDAppsClient

Sync-OSDAppCache `
    -ManifestPath '\\server\OSDApps\manifest.json' `
    -CachePath 'E:\OSDCloud\Apps'

Copy-OSDAppContent `
    -Name 'NotepadPlusPlus' `
    -CachePath 'E:\OSDCloud\Apps' `
    -WindowsPath 'C:\'

Add-OSDAppSetupComplete -WindowsPath 'C:\'
```

## Relationship with OSDAppsRepo

OSDAppsRepo is the recommended authoring and repository-management module. It builds and validates packages and maintains the manifest. OSDAppsClient only consumes the resulting repository contract.
