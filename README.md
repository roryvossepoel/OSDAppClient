# OSDApps

[![PowerShell Gallery Version](https://img.shields.io/powershellgallery/v/OSDApps?label=PowerShell%20Gallery)](https://www.powershellgallery.com/packages/OSDApps)
[![PowerShell Gallery Downloads (latest version)](https://img.shields.io/badge/dynamic/xml?url=https%3A%2F%2Fwww.powershellgallery.com%2Fapi%2Fv2%2FPackages%3F%2524filter%3DId%2Beq%2B%2527OSDApps%2527%2Band%2BIsAbsoluteLatestVersion%2Beq%2Btrue%26%2524select%3DVersion%252CVersionDownloadCount&query=%2F%2F*%5Blocal-name()%3D'VersionDownloadCount'%5D&label=downloads%20(latest)&color=blue&cacheSeconds=3600)](https://www.powershellgallery.com/packages/OSDApps)
[![Module CI](https://github.com/roryvossepoel/OSDApps/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/roryvossepoel/OSDApps/actions/workflows/ci.yml)
[![Windows PowerShell 5.1](https://img.shields.io/badge/Windows%20PowerShell-5.1-blue)](#install-from-powershell-gallery)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

OSDApps is a PowerShell module for application deployment with OSDCloud v2, combining self-maintained repository packages, vendor-native built-ins, optional USB caching, and pre-OOBE installation through SetupComplete.

It adds a simple application layer to Windows deployment:

- synchronize organization-managed repository applications in WinPE;
- acquire vendor-maintained built-in applications during first boot;
- optionally reuse and refresh an `OSDCloud` USB cache;
- stage everything locally before installation;
- install applications through SetupComplete before OOBE / Autopilot continues.

![OSDApps end-to-end architecture](docs/images/osdapps-architecture.svg)

## Install from PowerShell Gallery

For **WinPE and Windows PowerShell 5.1**, use PowerShellGet:

```powershell
Install-Module OSDApps -SkipPublisherCheck
Import-Module OSDApps
```

To install a specific version:

```powershell
Install-Module OSDApps -SkipPublisherCheck
```

`Install-PSResource` is the newer PSResourceGet equivalent, but PSResourceGet is not normally available by default in Windows PowerShell 5.1 / WinPE. For OSDCloud and WinPE scenarios, `Install-Module` is therefore the recommended installation method.

On systems where Microsoft.PowerShell.PSResourceGet is available, the equivalent command is:

```powershell
Install-PSResource OSDApps
```

## Deployment model

OSDApps supports two application sources.

| Source | Ownership | Acquisition / refresh | Installation |
| --- | --- | --- | --- |
| **Repository** | Organization | WinPE sync/cache + staging | SetupComplete |
| **Built-in** | Vendor / OSDApps integration | Full Windows PreInstall | SetupComplete |

Both sources are written into one ordered `Apps[]` queue in `DeviceManifest.json`.

The order in which applications are added is the order in which they are installed.

The example below deliberately mixes both source types. Microsoft 365 Apps, Teams, Chrome, and Adobe are **built-in applications**. `OmnissaHorizonClient` and `NotepadPlusPlus` are **example repository applications** that come from the organization's configured OSDApps repository; they are not built into OSDApps.

```powershell
# Built-in
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
Add-OSDAppGoogleChromeEnterprise

# Self-maintained repository examples
Add-OSDApp OmnissaHorizonClient
Add-OSDApp NotepadPlusPlus

# Built-in
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

# Built-ins
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
Add-OSDAppGoogleChromeEnterprise

# Examples resolved from your configured repository
Add-OSDApp OmnissaHorizonClient
Add-OSDApp NotepadPlusPlus

# Built-in
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

Machine-readable built-in metadata is published in [`metadata/builtins.json`](metadata/builtins.json). This provides a stable public source for tooling such as repository browsers and dashboards without having to parse PowerShell source files.

## Repository applications

An OSDApps repository is static content owned and maintained by the organization. No repository service or separate module is required.

Names such as `OmnissaHorizonClient` and `NotepadPlusPlus` used elsewhere in this documentation are examples of applications published in such a self-maintained repository. OSDApps itself does not ship or maintain those packages.

For repository applications, synchronization and cache population happen in **WinPE**. When `Add-OSDApp` is called, OSDApps resolves the requested package from the configured repository, updates/reuses the optional OSDCloud USB cache, validates the package hash, and stages the package to the offline Windows installation. SetupComplete later installs that already-staged local content; it does not re-synchronize repository applications.

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

Repository applications synchronize/cache in **WinPE** and are staged to the offline OS before reboot. Built-in freshness checks happen later in full Windows during PreInstall before installation.

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
