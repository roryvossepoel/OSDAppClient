# OSD App Client

OSD App Client is a PowerShell module for Windows PE, designed specifically to complement OSDCloud v2.

It runs after OSDCloud v2 has applied Windows and drivers. The module consumes a prepared OSD Apps repository, synchronizes and validates application packages, stages selected packages to the offline Windows volume, and appends a SetupComplete hook so the applications are installed before OOBE.

## Scope

OSD App Client does not build application packages and does not authenticate to Intune or Microsoft Graph.

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
OSDAppClient
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
OSD App Runner
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
Add-OSDApp
```

## Example

After OSDCloud v2 has finished applying Windows and drivers:

```powershell
Import-Module OSDAppClient

Add-OSDApp NotepadPlusPlus
```

OSD App Client automatically finds the volume labeled `OSDCloud`, uses `\OSDApps` on that volume as the cache, detects the offline Windows installation, stages the requested app, writes the device manifest, and appends the OSD App Runner to `SetupComplete.cmd`.

## Relationship with OSDAppRepo

OSDAppRepo is the recommended authoring and repository-management module. It builds and validates packages and maintains the manifest. OSDAppClient only consumes the resulting repository contract.


## Logging

OSD App Client writes structured JSON-lines logs designed for both human troubleshooting and machine analysis.

### WinPE / client log

Repository synchronization and staging events are written to:

```text
<CachePath>\Logs\Client.log
```

For the standard OSDCloud USB layout this is typically:

```text
E:\OSDApps\Logs\Client.log
```

The log includes events such as synchronization start/completion, packages already current, package acquisition, SHA-256 validation, and staging.

Logs are bounded and rotated automatically. The default limit is 1 MB per file with three retained rotated files.

### Installed Windows / runtime log

Application installation events are written to:

```text
%SystemDrive%\OSDApps\Logs\Install.log
```

Runtime logs use the same bounded JSON-lines format and automatic rotation.


## Architecture resolution

OSD App Client understands the repository architectures:

```text
x64
arm64
any
```

The client detects the WinPE host architecture automatically:

```text
AMD64 -> x64
ARM64 -> arm64
```

For every requested application, package selection follows this order:

1. Exact architecture match.
2. `any` as an architecture-independent fallback.
3. Fail clearly when no compatible package exists.

OSD App Client does not silently select an x64 package on ARM64. Cross-architecture support must be represented explicitly by the repository package metadata.
