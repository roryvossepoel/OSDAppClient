# OSDApps

OSDApps is a PowerShell module for application deployment with OSDCloud v2, combining self-maintained repository packages, vendor-native built-ins, optional USB caching, and pre-OOBE installation through SetupComplete.

It adds a simple application layer to Windows deployment:

- synchronize organization-managed repository applications in WinPE;
- acquire vendor-maintained built-in applications during first boot;
- optionally reuse and refresh an `OSDCloud` USB cache;
- stage everything locally before installation;
- install applications through SetupComplete before OOBE / Autopilot continues.

![OSDApps end-to-end architecture](docs/images/osdapps-architecture.svg)

## Deployment model

OSDApps supports two application sources.

| Source | Ownership | Acquisition / refresh | Installation |
| --- | --- | --- | --- |
| **Repository** | Organization | WinPE | SetupComplete |
| **Built-in** | Vendor / OSDApps integration | Full Windows PreInstall | SetupComplete |

Both sources are written into one ordered `Apps[]` queue in `DeviceManifest.json`.

The order in which applications are added is the order in which they are installed.

```powershell
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
Add-OSDAppGoogleChromeEnterprise
Add-OSDApp OmnissaHorizonClient
Add-OSDApp NotepadPlusPlus
Add-OSDAppAdobeAcrobatUnified
```

produces:

```text
Microsoft 365 Apps
→ Microsoft Teams
→ Google Chrome Enterprise
→ Omnissa Horizon Client
→ Notepad++
→ Adobe Acrobat Unified
```

## Quick start

Typical WinPE flow after OSDCloud has applied Windows:

```powershell
Import-Module OSDApps

Set-OSDAppConfiguration `
    -CatalogUri 'https://example.blob.core.windows.net/osdapps/catalog.json' `
    -CleanupMode OnSuccess

Get-OSDAppConfiguration
Get-OSDAppCatalog
Get-OSDApp

Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
Add-OSDAppGoogleChromeEnterprise
Add-OSDApp OmnissaHorizonClient
Add-OSDApp NotepadPlusPlus
Add-OSDAppAdobeAcrobatUnified
```

No OSDApps module installation is required in the deployed Windows installation. The required standalone runtime is staged automatically.

Default runtime log:

```text
%ProgramData%\OSDApps\Logs\Runtime.log
```

Module/cache log:

```text
<OSDCloud>:\OSDApps\Logs\Client.log
```

## Built-in applications

Current built-ins:

| Application | Vendor-native source |
| --- | --- |
| Microsoft 365 Apps | Office Deployment Tool |
| Microsoft Teams | Teams bootstrapper + official MSIX |
| Adobe Acrobat Unified | Adobe Unified installer |
| Google Chrome Enterprise | Google Enterprise MSI |
| Mozilla Firefox Enterprise | Mozilla MSI |

Built-ins are always acquired directly from the software vendor. OSDApps does not redistribute built-in application binaries.

A built-in is optional: any application can still be delivered through the self-maintained repository when organization-controlled packaging or versioning is preferred.

For Microsoft 365 Apps, for example:

```text
Built-in
→ ODT checks and refreshes Office in full Windows
→ Microsoft remains the freshness source

Repository
→ organization controls the Office package/version
→ repository sync happens in WinPE
→ full Windows only installs the staged package
```

See [Built-in applications](docs/built-in-apps.md).

## Repository applications

An OSDApps repository is static content. No repository service or separate module is required.

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

A package contains:

```text
Package.zip
└── Package/
    ├── Install.ps1
    └── payload
```

OSDApps includes optional authoring and validation helpers:

```powershell
New-OSDAppRepository
New-OSDAppPackage
Add-OSDAppPackage
Test-OSDAppPackage
Test-OSDAppRepository
```

See [Repository applications](docs/repository.md).

## Optional OSDCloud cache

A volume labeled `OSDCloud` is detected automatically.

```text
USB cache + online
→ reuse current content
→ refresh only where required
→ stage locally
→ install

USB cache + offline
→ use complete cached content
→ install

No USB + online
→ acquire built-ins directly to the local runtime
→ install
```

Repository applications synchronize in WinPE. Built-in freshness checks happen in full Windows before installation.

Inspect the current cache with:

```powershell
Get-OSDAppCache
```

## Validated performance

Cold-cache and warm-cache deployments were validated on the same hardware, USB stick and application set with OSDApps 0.29.1.

![OSDApps cold vs warm cache benchmark](docs/images/cold-warm-benchmark.svg)

| Phase | Cold | Warm |
| --- | ---: | ---: |
| PreInstall / refresh | 125.2 s | 40.6 s |
| Runner / installations | 330.7 s | 327.4 s |
| **Total measured Windows phase** | **455.9 s** | **368.0 s** |

The warm cache reduced the measured Windows phase by **87.9 seconds**. Almost all of the improvement came from acquisition and refresh; installation time remained effectively unchanged.

See [Performance](docs/performance.md).

## Development

Automated validation includes:

```text
PSScriptAnalyzer
→ Pester
→ example validation
→ distributable module build
```

Run the same validation locally with:

```powershell
./build/Test-Module.ps1
```

Every push to `main` and every pull request runs GitHub Actions CI.

PowerShell Gallery publishing uses a separate release workflow and is not performed by normal CI.

See [Releasing](docs/releasing.md).

## Documentation

- [Architecture](docs/architecture.md)
- [Built-in applications](docs/built-in-apps.md)
- [Repository applications](docs/repository.md)
- [Runtime and cleanup](docs/runtime.md)
- [Performance](docs/performance.md)
- [Validation matrix](docs/testing.md)
- [FAQ and troubleshooting](docs/faq.md)
- [Releasing](docs/releasing.md)
- [Changelog](CHANGELOG.md)

## License

OSDApps is licensed under the [MIT License](LICENSE).
