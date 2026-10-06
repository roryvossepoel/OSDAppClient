# Repository applications

Repository applications use a layered static repository contract.

## Online repository layout

```text
Repository/
├── catalog.json
└── Apps/
    └── <AppId>/
        ├── manifest.json
        └── <Version>/
            └── <Architecture>/
                └── Package.zip
```

The root `catalog.json` contains only application references. Application-specific metadata lives in `Apps/<AppId>/manifest.json`.

Example catalog entry:

```json
{
  "Id": "NotepadPlusPlus",
  "Manifest": "Apps/NotepadPlusPlus/manifest.json"
}
```

Example application manifest package:

```json
{
  "Version": "8.9.8.1",
  "Architecture": "x64",
  "SuccessCodes": [0, 3010],
  "Archive": {
    "FileName": "Package.zip",
    "SourcePath": "8.9.8.1/x64/Package.zip",
    "Sha256": "<SHA256>"
  }
}
```

The package path is relative to the application manifest.

Supported architectures:

```text
x64
arm64
any
```

Resolution order is exact architecture, then `any`, otherwise fail.

## Package contract

Every repository payload is a `Package.zip` containing `Install.ps1` at the archive root.

```text
Package.zip
├── Install.ps1
├── setup.exe / setup.msi / other payload
├── Config/
└── Files/
```

The package author is responsible for a fully unattended installation and predictable exit behavior. Default success codes are `0` and `3010`.

## WinPE flow

```powershell
Set-OSDAppCatalog 'https://example.blob.core.windows.net/osdapps/catalog.json'

Get-OSDAppCatalog
Get-OSDApp

# Automatically resolves the app manifest, synchronizes only this app,
# validates the package, and stages it for SetupComplete.
Add-OSDApp NotepadPlusPlus
```

`Sync-OSDAppRepository` remains available for explicit full or selective cache preloading, but is not required before a normal `Add-OSDApp`.

## Local cache metadata

Repository synchronization writes:

```text
<OSDCloud>:\OSDApps\CacheCatalog.json
<OSDCloud>:\OSDApps\Packages\<AppId>\Package.zip
```

`CacheCatalog.json` is a flattened local snapshot of the package metadata selected for the current architecture. The runner validates the staged package SHA-256 again before extraction and installation.

## Installation order

Repository packages are installed in the order supplied to `Add-OSDApp`:

```powershell
Add-OSDApp VCPlusPlusRuntime,LineOfBusinessApp
```

Built-ins continue to use their dedicated Add commands.
