# Repository applications

OSD Apps repositories are static content. A separate repository service or PowerShell module is not required.

OSDApps defines the repository contract, provides examples, and includes optional authoring helpers to create and validate the required folders and JSON.

## Repository layout

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

Supported repository architectures:

```text
x64
arm64
any
```

## Root catalog

`catalog.json` is an index. It points to the current package manifest for each application and architecture.

Example:

```json
{
  "SchemaVersion": 1,
  "GeneratedAt": "2026-10-06T00:00:00Z",
  "Applications": [
    {
      "Id": "ExampleApp",
      "Packages": [
        {
          "Architecture": "x64",
          "Manifest": "Apps/ExampleApp/1.0.0/x64/manifest.json"
        }
      ]
    }
  ]
}
```

## Package manifest

Each deployable package keeps its metadata directly beside `Package.zip`.

```json
{
  "SchemaVersion": 1,
  "Id": "ExampleApp",
  "DisplayName": "Example App",
  "Version": "1.0.0",
  "Architecture": "x64",
  "SuccessCodes": [
    0,
    3010
  ],
  "Archive": {
    "FileName": "Package.zip",
    "Sha256": "<SHA256>"
  }
}
```

The package URL is derived from the manifest location. A separate `SourcePath` property is not used.

## Package archive contract

Authoring source:

```text
ExampleApp/
├── Install.ps1
└── <payload>
```

Published archive:

```text
Package.zip
└── Package/
    ├── Install.ps1
    └── <payload>
```

`Install.ps1` must be unattended and suitable for execution during SetupComplete. The runner starts it with the extracted `Package` directory as its working directory.

## Creating a repository

The complete structure may be created manually. OSDApps also includes convenience helpers.

Create an empty repository:

```powershell
New-OSDAppRepository -Path C:\OSDApps\Repository
```

Build a package:

```powershell
New-OSDAppPackage `
    -Id ExampleApp `
    -Version 1.0.0 `
    -SourcePath C:\OSDApps\Packages\ExampleApp `
    -OutputPath C:\OSDApps\Build\ExampleApp
```

Publish it into the repository:

```powershell
Add-OSDAppPackage `
    -Id ExampleApp `
    -DisplayName 'Example App' `
    -Version 1.0.0 `
    -Architecture x64 `
    -PackagePath C:\OSDApps\Build\ExampleApp\Package.zip `
    -RepositoryPath C:\OSDApps\Repository
```

The helper:

1. validates the fixed `Package/Install.ps1` archive layout;
2. creates `Apps/<Id>/<Version>/<Architecture>`;
3. copies `Package.zip`;
4. calculates SHA-256;
5. writes `manifest.json`;
6. adds or replaces the architecture reference in `catalog.json`.

## Validation

Validate an individual archive:

```powershell
Test-OSDAppPackage C:\OSDApps\Build\ExampleApp\Package.zip
```

Validate the complete repository:

```powershell
Test-OSDAppRepository C:\OSDApps\Repository
```

Repository validation checks:

- referenced package manifest exists;
- `Package.zip` exists;
- SHA-256 matches;
- archive contains `Package/Install.ps1`;
- architecture is `x64`, `arm64`, or `any`;
- package manifest Id matches the catalog application Id.

## Publishing

The resulting repository is ordinary static content. Publish the contents of `Repository` to an HTTP/HTTPS location while preserving paths.

For example:

```text
https://example.blob.core.windows.net/osdapps/catalog.json
https://example.blob.core.windows.net/osdapps/Apps/ExampleApp/1.0.0/x64/manifest.json
https://example.blob.core.windows.net/osdapps/Apps/ExampleApp/1.0.0/x64/Package.zip
```

Configure a deployment session with:

```powershell
Set-OSDAppConfiguration -CatalogUri 'https://example.blob.core.windows.net/osdapps/catalog.json'
```

## Examples

A starter repository and package source template are included under [Examples](../Examples/README.md).

The examples are intentionally simple: the repository contract is designed to remain understandable and maintainable without proprietary tooling.
