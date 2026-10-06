# Repository applications

Repository applications use a static two-layer repository contract.

## Online repository layout

```text
Repository/
├── catalog.json
└── Apps/
    └── <AppId>/
        └── <Version>/
            └── <Architecture>/
                ├── manifest.json
                └── Package.zip
```

The rule is simple:

- `catalog.json` tells OSDAppClient which package manifest represents each application/architecture.
- Every `manifest.json` describes exactly one sibling `Package.zip`.

Example catalog entry:

```json
{
  "Id": "NotepadPlusPlus",
  "Packages": [
    {
      "Architecture": "x64",
      "Manifest": "Apps/NotepadPlusPlus/8.9.8.1/x64/manifest.json"
    }
  ]
}
```

Example package manifest:

```json
{
  "SchemaVersion": 1,
  "Id": "NotepadPlusPlus",
  "DisplayName": "Notepad++",
  "Version": "8.9.8.1",
  "Architecture": "x64",
  "SuccessCodes": [0, 3010],
  "Archive": {
    "FileName": "Package.zip",
    "Sha256": "<SHA256>"
  }
}
```

No package path is required inside the manifest because `Package.zip` is in the same directory.

Supported architectures are `x64`, `arm64`, and `any`. OSDAppClient prefers an exact architecture match and falls back to `any`.

## Package contract

`Package.zip` must contain `Install.ps1` at the archive root. The package author is responsible for a fully unattended install.

## WinPE flow

```powershell
Set-OSDAppCatalog 'https://example.blob.core.windows.net/osdapps/catalog.json'

Get-OSDAppCatalog
Get-OSDApp

Add-OSDApp NotepadPlusPlus
```

`Add-OSDApp` resolves the package manifest, synchronizes only the requested app, validates SHA-256, caches it, and stages it for SetupComplete.

`Sync-OSDAppRepository` remains available for explicit cache preloading or maintenance.
