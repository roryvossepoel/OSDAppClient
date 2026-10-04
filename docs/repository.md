# Repository applications

Repository applications use the OSD Apps package contract.

## Package contract

Every application is represented by a single `Package.zip`.

```text
Package.zip
├── Install.ps1
├── setup.exe
├── Config/
├── Modules/
└── Files/
```

`Install.ps1` must exist at the root of the archive.

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

Get-OSDAppCatalog

Sync-OSDAppRepository

Get-OSDApp

Add-OSDApp NotepadPlusPlus
```

Repository packages are synchronized and SHA-256 validated in WinPE.

The runner validates the staged package hash again before extraction and installation.

## Installation order

Repository packages are installed in the order supplied to `Add-OSDApp`.

```powershell
Add-OSDApp VCPlusPlusRuntime,LineOfBusinessApp,Microsoft365Apps,Teams
```

Repository apps run first in the requested order. Built-ins run afterwards.
