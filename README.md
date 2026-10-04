# OSD App Client

OSD App Client is a PowerShell module for Windows PE, designed specifically to complement OSDCloud v2.

It runs after OSDCloud v2 has applied Windows and drivers. The module consumes a prepared OSD Apps repository, synchronizes and validates application packages, stages selected packages to the offline Windows volume, and appends a SetupComplete hook so the applications are installed before OOBE.


## Architecture overview

```mermaid
flowchart TB
    subgraph CATALOG["1. Central catalog"]
        A[Azure Blob Storage<br/>catalog.json]
        B[Set-OSDAppCatalog]
        C[Get-OSDAppCatalog]
        A --> B
        B --> C
    end

    subgraph CACHE["2. Local OSDCloud cache"]
        D[Sync-OSDAppRepository]
        E[OSDCloud volume<br/>\\OSDApps]
        F[Get-OSDApp]
        D --> E
        E --> F
    end

    subgraph STAGE["3. Stage for installed Windows"]
        G[Add-OSDApp]
        H[Offline Windows<br/>C:\\OSDApps]
        I[SetupComplete.cmd]
        G --> H
        H --> I
    end

    subgraph RUNTIME["4. SetupComplete runtime"]
        J[OSD App Runner]
        K{App source}
        L[Repository app<br/>Expand Package.zip<br/>Run Install.ps1]
        M[Built-in app<br/>Run vendor bootstrapper]
        N[OOBE / Autopilot]

        J --> K
        K -->|Repository| L
        K -->|BuiltIn| M
        L --> N
        M --> N
    end

    C --> D
    F --> G
    I --> J

    O[Built-ins<br/>Microsoft365Apps<br/>Teams] --> F
    P[x64 / arm64 / any<br/>SHA-256 validation] --> D
```

Typical WinPE usage after OSDCloud v2 has finished applying Windows and drivers:

```powershell
Set-OSDAppCatalog 'https://example.org/osdapps/catalog.json'

Get-OSDAppCatalog

Sync-OSDAppRepository

Get-OSDApp

Get-OSDApp NotepadPlusPlus | Add-OSDApp
```

OSDAppClient uses a cloud-hosted catalog for repository discovery and a local cache on the volume labeled `OSDCloud`. Built-in apps such as Microsoft 365 Apps and Teams do not require a catalog or repository sync. The client does not authenticate to Intune or Microsoft Graph during WinPE runtime.

## Scope

OSD App Client does not build application packages and does not authenticate to Intune or Microsoft Graph.

It consumes repositories that follow the OSD Apps repository contract.

The OSD App Catalog is cloud-native and referenced by an HTTP/HTTPS URL. Azure Blob Storage is the primary design target for hosting `catalog.json` and package content.

## Package author responsibility

Repository packages are executed during SetupComplete, before the interactive OOBE / Autopilot experience is available.

The package author is responsible for making sure the root-level `Install.ps1` performs a fully unattended installation. The script must not depend on interactive prompts, visible installer windows, user input, or UI-driven configuration.

Because this runs in a non-interactive deployment phase, `Install.ps1` should be designed to be stable and fault-tolerant. It should handle expected installer exit codes, validate prerequisites where appropriate, fail clearly on unrecoverable errors, and avoid leaving the device in an indeterminate state.

OSDAppClient provides the staging and execution framework, but it does not make a vendor installer unattended automatically. Packaging logic, silent switches, configuration files, prerequisite handling, and application-specific error handling remain the responsibility of the package author.

A good `Install.ps1` should therefore:

- use silent or unattended vendor-supported installation switches;
- avoid any dependency on visible UI;
- wait for installation processes to finish before exiting;
- return meaningful exit codes;
- handle common success codes such as reboot-required outcomes where applicable;
- validate required files and prerequisites before starting;
- write useful application-specific logs when troubleshooting value justifies it;
- be safe to run during SetupComplete before OOBE.



## First-phase runtime guarantees

The first implementation intentionally favors predictable behavior over automatic recovery.

### Installation order

Repository applications are written to `DeviceManifest.json` in the same order in which they are supplied to `Add-OSDApp`. The OSD App Runner processes those repository packages sequentially in that order.

Built-in applications are processed after repository packages.

Example:

```powershell
Add-OSDApp VCPlusPlusRuntime,LineOfBusinessApp,Microsoft365Apps,Teams
```

The repository packages are processed first in the requested order, followed by the built-in applications.

### Fail-fast behavior

The runner stops on the first unrecoverable installation failure. It does not continue silently with the remaining applications.

This is intentional for the pre-OOBE deployment phase: a failed prerequisite or incomplete baseline should be visible in the runner log instead of producing a partially configured device.

### Package integrity

Repository package SHA-256 is validated when content is synchronized and validated again from the staged Windows copy immediately before extraction and installation.

A staged package with a hash mismatch is not executed.

### Exit codes

Repository packages use `0` and `3010` as success codes by default. A package can define its own `SuccessCodes` metadata when other vendor-specific success codes are required.

### Cleanup

OSDAppClient does not automatically remove `%SystemDrive%\OSDApps` after installation in the first phase. Keeping staged content and logs available makes troubleshooting much easier while the runtime model is being validated.

Cleanup can be added later as an explicit, opt-in behavior.

### Logging contract

The runner uses structured JSON-lines logging. Important runtime events include:

```text
InstallStart
PackageIntegrityValidated
PackageIntegrityFailed
PackageExtractStart
PackageInstallStart
PackageInstallComplete
BuiltInInstallStart
BuiltInInstallComplete
InstallFailed
InstallComplete
```


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



## Reference Install.ps1 pattern

A repository package should keep vendor-specific installation behavior inside its own `Install.ps1`.

A minimal reference pattern:

```powershell
$ErrorActionPreference = 'Stop'

$installer = Get-ChildItem -Path $PSScriptRoot -Filter '*.exe' -File |
    Select-Object -First 1

if (-not $installer) {
    throw 'Installer not found.'
}

$process = Start-Process `
    -FilePath $installer.FullName `
    -ArgumentList '/S' `
    -WorkingDirectory $PSScriptRoot `
    -Wait `
    -PassThru

$successCodes = @(0,3010)

if ($process.ExitCode -notin $successCodes) {
    throw "Installer failed with exit code $($process.ExitCode)."
}

exit $process.ExitCode
```

This is only a pattern. The package author remains responsible for using the vendor-supported unattended switches, configuration, prerequisites, detection and error handling required by that application.


## Runtime flow

```text
OSDCloud v2 in WinPE
        ↓
Windows + drivers applied
        ↓
OSDAppClient
        ↓
Read central catalog
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
Set-OSDAppCatalog
Get-OSDAppCatalog
Sync-OSDAppRepository
Get-OSDApp
Add-OSDApp
```

The lower-level cache, staging, and SetupComplete commands remain implementation details of the client workflow.

## Example

After OSDCloud v2 has finished applying Windows and drivers:

```powershell
Import-Module OSDAppClient

Add-OSDApp NotepadPlusPlus
```

OSD App Client automatically finds the volume labeled `OSDCloud`, uses `\OSDApps` on that volume as the cache, detects the offline Windows installation, stages the requested app, writes the device manifest, and appends the OSD App Runner to `SetupComplete.cmd`.

## Relationship with OSDAppRepo

OSDAppRepo is the recommended authoring and repository-management module. It builds and validates packages and maintains the central `catalog.json`. OSDAppClient consumes that catalog and the resulting repository contract.


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


## Typical WinPE workflow

After OSDCloud v2 has finished applying Windows and drivers:

```powershell
Set-OSDAppCatalog 'https://example.org/osdapps/catalog.json'

Get-OSDAppCatalog

Sync-OSDAppRepository

Get-OSDApp

Get-OSDApp NotepadPlusPlus | Add-OSDApp
```

`Set-OSDAppCatalog` configures the central cloud catalog for the current PowerShell session. `Get-OSDAppCatalog` reads that online catalog only; it does not download package content.

`Sync-OSDAppRepository` synchronizes repository content from the configured catalog to the `\OSDApps` cache on the USB volume labeled `OSDCloud`. The cache location is detected automatically.

`Get-OSDApp` shows what is locally available for deployment: cached repository apps plus built-in apps such as Microsoft 365 Apps and Teams. Repository entries report `Availability = Cached`; built-ins report `Availability = Available`.

Objects returned by `Get-OSDApp` can be piped directly to `Add-OSDApp`. Multiple apps are collected and staged together so the device manifest contains the complete requested application set.




## Built-in applications without a repository

OSDAppClient also supports a small set of built-in application flows that do **not** require an OSD App repository, `manifest.json`, or `Sync-OSDAppRepository`.

Currently supported:

```text
Microsoft365Apps
Teams
```

These built-in applications are prepared directly by OSDAppClient and staged for installation during SetupComplete. By default, only the vendor bootstrapper and configuration are staged and the application payload is downloaded during SetupComplete. Optional local caching is available through `Sync-OSDAppBuiltIn` for deployments that should install Microsoft 365 Apps or Teams from staged local content.

Examples:

```powershell
Add-OSDApp Microsoft365Apps
```

```powershell
Add-OSDApp Teams
```

They can also be staged together:

```powershell
Add-OSDApp Microsoft365Apps,Teams
```

For built-in applications, OSDAppClient still uses the same runtime model:

```text
WinPE
  ↓
Add-OSDApp
  ↓
stage installer/bootstrapper and metadata
  ↓
SetupComplete
  ↓
OSD App Runner
  ↓
install application before OOBE / Autopilot
```

Repository-based applications remain available alongside built-ins and use `Get-OSDAppCatalog` to inspect the central catalog, `Sync-OSDAppRepository` to populate the local cache, and `Get-OSDApp` to discover what is locally deployment-ready.

## Optional built-in caching

Microsoft 365 Apps and Teams can be used in two modes:

```text
Default
→ stage only the vendor bootstrapper/configuration
→ download application payload during SetupComplete

Cached
→ Sync-OSDAppBuiltIn downloads the vendor payload to the OSDCloud media first
→ Add-OSDApp stages that cached payload to offline Windows
→ SetupComplete installs from the staged local content
```

Caching is optional and does not use the OSD App repository or central `catalog.json`.

Synchronize one or both built-ins:

```powershell
Sync-OSDAppBuiltIn Microsoft365Apps
Sync-OSDAppBuiltIn Teams
Sync-OSDAppBuiltIn Microsoft365Apps,Teams
```

The cache is stored below:

```text
<OSDCloud volume>:\OSDApps\BuiltIn
```

After synchronization, `Get-OSDApp` reports the built-in as `Availability = Cached` and shows the detected cached version.

When a Microsoft 365 Apps cache already exists, a plain `Add-OSDApp Microsoft365Apps` reuses the `configuration.xml` stored with that cache. Supplying Office parameters to `Add-OSDApp` explicitly overrides the cached configuration.

### Microsoft 365 Apps cache behavior

For Microsoft 365 Apps, OSDAppClient runs the Office Deployment Tool in `/download` mode using the selected Office configuration. ODT maintains the `Office\Data` content under the built-in cache.

Running `Sync-OSDAppBuiltIn Microsoft365Apps` again asks ODT to synchronize the same cache. ODT downloads required or missing content and the module records the newest detected Office data version in `CacheInfo.json`.

The same Office configuration options used by `Add-OSDApp Microsoft365Apps` are available on `Sync-OSDAppBuiltIn`.

Example:

```powershell
Sync-OSDAppBuiltIn Microsoft365Apps `
    -OfficeChannel Current `
    -OfficeArchitecture 64 `
    -OfficeProductId O365ProPlusRetail `
    -OfficeLanguage nl-nl,en-us `
    -OfficeSharedComputerLicensing $true
```

When cached Office content is staged, SetupComplete still runs:

```text
setup.exe /configure configuration.xml
```

Because the `Office\Data` payload is present beside the Office Deployment Tool, ODT can install from the local staged content.

### Microsoft Teams cache behavior

For Teams, OSDAppClient downloads the latest Microsoft Teams bootstrapper and the official Teams MSIX for the selected architecture.

```powershell
Sync-OSDAppBuiltIn Teams
```

Architecture defaults to the current host architecture and can be overridden:

```powershell
Sync-OSDAppBuiltIn Teams -TeamsArchitecture x64
Sync-OSDAppBuiltIn Teams -TeamsArchitecture arm64
```

The module reads the version from the downloaded MSIX and stores it in `CacheInfo.json`. When the downloaded version matches the already cached version, the existing cached MSIX is retained.

When a Teams MSIX is cached, `Add-OSDApp Teams` records the offline package in `DeviceManifest.json`. During SetupComplete the runner uses the Microsoft-supported offline provisioning form:

```text
teamsbootstrapper.exe -p -o <local teams.msix>
```

Without a cached MSIX, the existing online `teamsbootstrapper.exe -p` behavior remains unchanged.

> The current Teams version check requires downloading the current Microsoft MSIX before its embedded package version can be compared with the local cache. This can be optimized later if Microsoft exposes suitable lightweight version metadata.

## Built-in Microsoft 365 Apps support

Microsoft 365 Apps can be staged without an OSD App repository, repository manifest, or prior repository synchronization:

```powershell
Add-OSDApp Microsoft365Apps
```

OSDAppClient downloads only the Office Deployment Tool bootstrapper and prepares the Office configuration in WinPE. It then stages those files to the offline Windows installation.

No Microsoft 365 Apps payload is downloaded or cached in WinPE at this stage. During SetupComplete, the Office Deployment Tool downloads the required installation content from the Microsoft CDN and installs it. An active internet connection is therefore required during the Microsoft 365 Apps installation.

During SetupComplete, the OSD App Runner starts:

```text
setup.exe /configure configuration.xml
```

At that point the Office Deployment Tool acquires the required Microsoft 365 Apps content and installs it before OOBE / Autopilot continues. The generated configuration intentionally omits `SourcePath`, so ODT uses the normal Microsoft CDN during `/configure`.

Optional offline caching is available through `Sync-OSDAppBuiltIn Microsoft365Apps`. Without that prior sync, the existing online SetupComplete behavior remains unchanged.

A common customized deployment:

```powershell
Add-OSDApp Microsoft365Apps `
    -OfficeChannel MonthlyEnterprise `
    -OfficeArchitecture 64 `
    -OfficeProductId O365ProPlusRetail `
    -OfficeLanguage nl-nl,en-us `
    -OfficeExcludeApp Access,Publisher
```

Supported `-OfficeChannel` values follow the current Office Deployment Tool channel values:

```text
Current
MonthlyEnterprise
SemiAnnual
CurrentPreview
SemiAnnualPreview
BetaChannel
```

`BetaChannel` is available in ODT but Microsoft classifies Beta Channel as unsupported for production use.

Supported `-OfficeArchitecture` values are `64` and `32`. On Windows 11 Arm devices, Microsoft 365 Apps uses the 64-bit Office deployment and automatically installs Arm-optimized components.

Built-in Microsoft 365 Apps currently supports these product IDs:

```text
O365ProPlusRetail
O365BusinessRetail
```

Supported `-OfficeExcludeApp` values:

```text
Access
Excel
Groove
Lync
OneDrive
OneNote
Outlook
OutlookForWindows
PowerPoint
Publisher
Teams
Word
```

Multiple languages can be supplied:

```powershell
Add-OSDApp Microsoft365Apps -OfficeLanguage nl-nl,en-us
```

For advanced Office Deployment Tool scenarios, a complete custom XML file can be supplied instead:

```powershell
Add-OSDApp Microsoft365Apps -ConfigurationXml .\configuration.xml
```

When a custom XML file is supplied, OSDAppClient copies it unchanged. For a fully offline SetupComplete installation, the custom configuration should either omit `SourcePath` or reference content that will still be available after the reboot.

Repository-based apps and Microsoft 365 Apps can also be staged in one call:

```powershell
Add-OSDApp NotepadPlusPlus,Microsoft365Apps
```

Microsoft 365 Apps is the first built-in installer path. It is intentionally implemented separately from the repository package contract. In the current implementation only the ODT bootstrapper and configuration are staged in WinPE; Office payload caching is reserved for a future enhancement.


## Built-in Microsoft Teams support

Microsoft Teams can also be staged without an OSD App repository, repository manifest, or prior repository synchronization:

```powershell
Add-OSDApp Teams
```

In WinPE, OSDAppClient downloads only the latest Microsoft `teamsbootstrapper.exe` and stages it to the offline Windows installation. Teams itself is not installed in WinPE.

During SetupComplete, the OSD App Runner executes:

```text
teamsbootstrapper.exe -p
```

The Teams bootstrapper then downloads and provisions the latest Teams MSIX for all users on the device.

The optional Teams Meeting Add-in can be installed machine-wide with:

```powershell
Add-OSDApp Teams -TeamsInstallMeetingAddin $true
```

This causes SetupComplete to run:

```text
teamsbootstrapper.exe -p --installTMA
```

By default, the built-in Teams flow stages only `teamsbootstrapper.exe`, so SetupComplete downloads the Teams payload from Microsoft and requires internet access. When `Sync-OSDAppBuiltIn Teams` has populated the local built-in cache first, `Add-OSDApp Teams` stages the cached MSIX and SetupComplete provisions Teams from that local package instead.




## Catalog configuration and discovery

The central OSD App Catalog is configured once per PowerShell session:

```powershell
Set-OSDAppCatalog -Uri 'https://example.blob.core.windows.net/osdapps/catalog.json'
```

The configuration is session-scoped. Nothing has to exist on the deployment USB before the module is loaded.

Use `Get-OSDAppCatalog` to inspect what the central catalog currently offers:

```powershell
Get-OSDAppCatalog
```

This command reads the online catalog only. It does not synchronize or download package content.

An explicit catalog URL can also be supplied for one-off inspection:

```powershell
Get-OSDAppCatalog -Uri 'https://example.blob.core.windows.net/osdapps/catalog.json'
```

Synchronize repository packages to the local OSDCloud media with:

```powershell
Sync-OSDAppRepository
```

After synchronization, use `Get-OSDApp` to see what is locally deployment-ready:

```powershell
Get-OSDApp
```

Typical output conceptually distinguishes the source and availability:

```text
Id                  Source       Availability
--                  ------       ------------
NotepadPlusPlus     Repository   Cached
Microsoft365Apps    BuiltIn      Available
Teams               BuiltIn      Available
```

Built-in applications are part of OSDAppClient and therefore do not appear in the online catalog. They are returned by `Get-OSDApp` even when no repository has been synchronized.

The intended cloud-native layout is:

```text
Azure Blob Storage
└── osdapps/
    ├── catalog.json
    └── Packages/
        └── <AppId>/
            └── <Version>/
                └── <Architecture>/
                    └── Package.zip
```
