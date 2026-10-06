# OSD App Client

OSD App Client is a PowerShell module and standalone runtime for OSDCloud v2 application caching, staging, refresh, and pre-OOBE installation.

It is designed around a simple deployment model:

```text
WinPE
→ OSDCloud applies Windows and drivers
→ repository applications are synchronized/cached in WinPE
→ Add-* stages application intent and available content to the offline OS

First boot / full Windows
→ built-in application sources are resolved automatically
→ optional OSDCloud USB cache is used and updated when present
→ otherwise content is acquired directly to the local Windows runtime
→ SetupComplete installs applications
→ temporary source is removed
→ OOBE / Autopilot continues
```

## Key concepts

OSD Apps supports two application sources:

| Source | Acquisition / sync | Installation |
| --- | --- | --- |
| Repository apps | WinPE | SetupComplete |
| Built-in applications | Full Windows pre-install phase | SetupComplete |

Repository apps use the OSD Apps package contract: `Package.zip` with a top-level `Package` folder containing `Install.ps1` and the installation payload.

Built-in apps use vendor-native acquisition and installation:
- Microsoft 365 Apps uses the Office Deployment Tool.
- Microsoft Teams uses the Teams bootstrapper and official MSIX.
- Adobe Acrobat Unified uses Adobe's official Unified installer ZIP, which is cached compressed, extracted locally, and installed through Setup.exe.
- Google Chrome Enterprise uses Google's official Enterprise MSI.
- Mozilla Firefox Enterprise uses Mozilla's official MSI for Rapid Release or ESR.

## Quick start

Typical WinPE flow after OSDCloud v2 has finished:

```powershell
Import-Module OSDAppClient

# Repository applications
Set-OSDAppCatalog 'https://example.blob.core.windows.net/osdapps/catalog.json'
Get-OSDAppCatalog

# Discover repository and built-in applications
Get-OSDApp

# Add-OSDApp automatically synchronizes the requested repository package
Add-OSDApp NotepadPlusPlus
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
Add-OSDAppAdobeAcrobatUnified
Add-OSDAppGoogleChromeEnterprise
Add-OSDAppMozillaFirefoxEnterprise
```

For built-ins only, no catalog or repository synchronization is required:

```powershell
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
Add-OSDAppAdobeAcrobatUnified
```

For built-in cache configuration and synchronization on full Windows:

```powershell
Sync-OSDAppMicrosoft365Apps `
    -Channel Current `
    -Architecture 64 `
    -ProductId O365ProPlusRetail `
    -Language nl-nl,en-us

Sync-OSDAppTeams -Architecture x64
Sync-OSDAppGoogleChromeEnterprise
Sync-OSDAppMozillaFirefoxEnterprise
```

## Optional OSDCloud USB cache

USB media is optional for built-in applications.

If a USB volume with the label `OSDCloud` is connected, OSD Apps detects it automatically and uses it as the cache source and destination. No `OSDApps` folder or pre-existing cache is required: a blank `OSDCloud` volume can be populated automatically during deployment.

```text
OSDCloud USB + online
→ use existing cache when available
→ refresh/update cache
→ stage current content locally
→ install

OSDCloud USB + offline
→ use complete cached content
→ install

No USB + online
→ acquire directly to %SystemRoot%\Temp\OSDApps
→ install
```

Repository applications synchronize/cache in WinPE. When an online catalog is configured, `Add-OSDApp` automatically refreshes only the requested repository application(s) before staging. `Sync-OSDAppRepository` remains available for explicit cache preloading or maintenance. Built-in applications synchronize/update during SetupComplete in full Windows.

> **When an OSDCloud USB cache is detected, keep it connected until OOBE is displayed.**

## Transparent source resolution

The same built-in Add commands are used regardless of how content will be acquired:

```powershell
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
```

The runtime decides the source automatically. USB cache availability changes performance and offline capability, not the deployment command.

Use `-Verbose` to see Windows target resolution, OSDCloud cache detection, cache state, staging decisions, and the selected acquisition path.

Verbose output uses a compact OSDCloud-style deployment format with timestamps, severity labels and short component names, for example:

```text
[2026-10-05T09:10:12] [INFO] Cache: OSDCloud cache found at E:\OSDApps
[2026-10-05T09:10:12] [INFO] Microsoft365Apps: No existing cache found; cache will be created during SetupComplete
```

The same decisions are also written to the CMTrace-compatible logs.

## Validated deployment scenarios

The built-in cache bootstrap flow has been validated end to end with a completely blank `OSDCloud` USB cache:

```text
blank USB with label OSDCloud
→ Add-OSDAppMicrosoft365Apps
→ Add-OSDAppTeams
→ no usable built-in cache present in WinPE
→ SetupComplete detects the OSDCloud volume
→ Microsoft 365 Apps cache is created from scratch
→ Microsoft Teams cache is created from scratch
→ both payloads are staged locally
→ both applications install successfully
→ temporary runtime cleanup is scheduled
```

This confirms that pre-populating `<OSDCloud>:\OSDApps` is not required for built-in deployment.

An existing-cache + online refresh run has also been validated: both built-in caches were detected in WinPE, Office synchronized without a version change, Teams reported no package update, and both applications installed successfully from the local staged runtime.

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

On failure, the local runtime source is retained for troubleshooting.

## Built-in applications

Currently supported:

```text
Microsoft365Apps
Teams
AdobeAcrobatUnified
GoogleChromeEnterprise
MozillaFirefoxEnterprise
```

Each built-in has its own configuration/synchronization cmdlet and its own Add cmdlet:

```powershell
Sync-OSDAppMicrosoft365Apps
Sync-OSDAppTeams
Sync-OSDAppAdobeAcrobatUnified
Sync-OSDAppGoogleChromeEnterprise
Sync-OSDAppMozillaFirefoxEnterprise

Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
Add-OSDAppAdobeAcrobatUnified
```

There is intentionally no generic `Sync-OSDAppBuiltIn` command. Each built-in owns its own parameter set and configuration.

See [Built-in applications](docs/built-in-apps.md).

## Built-in source policy

OSDAppClient never ships built-in application binaries, installers, archives, or repackaged vendor content.

For every built-in application, deployment content is always acquired directly from the software vendor at deployment/cache time. The module contains only the logic and vendor source definitions required to locate, cache, stage, and install that content.

```text
Built-in application
→ source is always the vendor
→ OSDAppClient may cache/stage the vendor content
→ OSDAppClient never redistributes the installer itself
```

This policy applies only to built-in applications. Repository applications are organization-controlled packages; their content, hosting, licensing, and provenance are the repository owner's responsibility.

## Requesting a built-in application

Built-in applications are intentionally limited to broadly used products with a clean, vendor-supported acquisition path. Requests are welcome, but a built-in should meet all of these requirements:

- the application is broadly used across organizations, not a customer-specific or niche line-of-business app;
- the installer can be downloaded directly and reproducibly from the software vendor;
- the built-in content will always be acquired from the vendor at runtime/cache time; no installer may be bundled with or redistributed through OSDAppClient;
- the vendor provides a stable URL, documented endpoint, or another deterministic download mechanism;
- acquisition does not require scraping a website, sniffing browser traffic, extracting temporary URLs, session cookies, access tokens, or other brittle workarounds;
- a CDN is fine when the vendor exposes a stable supported download URL, but not when CDN protection requires bypassing or reverse-engineering the download flow;
- the installer supports a reliable unattended enterprise installation;
- the acquisition and install flow can be maintained without depending on undocumented tricks.

If an application does not meet these criteria, package it as a normal repository application instead. The repository model is the intended path for niche, customer-specific, internally hosted, authenticated, or otherwise non-generic applications.

See [Built-in applications](docs/built-in-apps.md#requesting-a-new-built-in-application) for the full policy.

## Repository metadata model

Online repository metadata is deliberately simple:

```text
catalog.json
└── Apps/<AppId>/<Version>/<Architecture>/
    ├── manifest.json
    └── Package.zip
```

`catalog.json` is only the root index. Every deployable package is self-contained: its `manifest.json` sits directly beside `Package.zip` and contains the Id, display name, version, architecture, success codes, archive filename, and SHA-256.

Local deployment metadata remains separate:

```text
CacheCatalog.json    local OSDCloud USB snapshot of selected repository packages
DeviceManifest.json  per-device staged installation manifest
```

`Get-OSDAppCatalog` reports catalog status. `Get-OSDApp` resolves application manifests and combines online repository state, local cache state, and built-in applications.

## Repository applications

Repository packages remain compressed while cached and staged.

```text
Package.zip
└── Package/
    ├── Install.ps1
    ├── setup.exe / setup.msi / other payload
    ├── Config/
    └── Files/
```

The package author is responsible for making `Install.ps1` completely unattended and suitable for SetupComplete.

See [Repository applications](docs/repository.md).

## Installation order

Application installation order follows the order in which the `Add-*` commands are called, across both repository and built-in applications.

```powershell
Add-OSDAppTeams
Add-OSDAppMicrosoft365Apps
Add-OSDApp OmnissaHorizonClient
Add-OSDAppAdobeAcrobatUnified
```

produces:

```text
Teams
→ Microsoft 365 Apps
→ Omnissa Horizon Client
→ Adobe Acrobat Unified
```

The order is persisted in `DeviceManifest.json` as `InstallOrder`. Re-adding an application moves it to the end of the list instead of creating a duplicate.

## Runtime behavior

The standalone runtime does not require the OSDAppClient module to be installed in Windows.

The Add cmdlets stage everything needed for the first boot:
- `DeviceManifest.json`
- `Invoke-OSDAppPreInstall.ps1`
- `Invoke-OSDAppRunner.ps1`
- repository packages when applicable
- built-in deployment intent
- available built-in cache content when present

SetupComplete runs the standalone pre-install phase first and the installer second.

See [Runtime and cleanup](docs/runtime.md).

## Public commands

```text
Set-OSDAppCatalog
Get-OSDAppCatalog
Get-OSDApp

Sync-OSDAppRepository
Sync-OSDAppMicrosoft365Apps
Sync-OSDAppTeams
Sync-OSDAppAdobeAcrobatUnified
Sync-OSDAppGoogleChromeEnterprise
Sync-OSDAppMozillaFirefoxEnterprise

Add-OSDApp
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
Add-OSDAppAdobeAcrobatUnified
Add-OSDAppGoogleChromeEnterprise
Add-OSDAppMozillaFirefoxEnterprise

Clear-OSDAppCache
```

Low-level cache validation, content staging, repository synchronization internals, and SetupComplete integration are private implementation details.

## Documentation

- [Architecture](docs/architecture.md)
- [Built-in applications](docs/built-in-apps.md)
- [Repository applications](docs/repository.md)
- [Runtime and cleanup](docs/runtime.md)
- [FAQ and troubleshooting](docs/faq.md)
- [Validation matrix](docs/testing.md)
- [Changelog](CHANGELOG.md)

## Related project

[OSDAppRepo](https://github.com/roryvossepoel/OSDAppRepo) is the companion authoring and repository-management module. It builds and validates packages and maintains the central `catalog.json`.
