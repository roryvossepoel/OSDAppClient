# Built-in applications

Built-in applications use vendor-native acquisition and installation instead of the repository package contract.

Currently supported:

```text
Microsoft365Apps
Teams
AdobeAcrobatUnified
```

## Configuration and synchronization

Each built-in has its own cmdlet and parameter set.

### Microsoft 365 Apps

```powershell
Sync-OSDAppMicrosoft365Apps `
    -Channel Current `
    -Architecture 64 `
    -ProductId O365ProPlusRetail `
    -Language nl-nl,en-us `
    -SharedComputerLicensing $true
```

A sync is also a configuration action. Changing parameters rewrites the desired Office configuration and refreshes the cache.

Supported channels:

```text
Current
MonthlyEnterprise
SemiAnnual
CurrentPreview
SemiAnnualPreview
BetaChannel
```

Supported product IDs:

```text
O365ProPlusRetail
O365BusinessRetail
```

Supported architectures:

```text
64
32
```

The Office cache contains the Office Deployment Tool, `configuration.xml`, and `Office\Data`.

### Microsoft Teams

```powershell
Sync-OSDAppTeams -Architecture x64
```

Supported architectures:

```text
Auto
x86
x64
arm64
```

The Teams cache contains:
- `teamsbootstrapper.exe`
- `teams.msix`
- `CacheInfo.json`

Teams freshness is checked using HTTP metadata. ETag is preferred; Last-Modified plus Content-Length is the fallback.

### Adobe Acrobat Unified

Adobe Acrobat Unified uses the official Adobe 64-bit unified Acrobat/Reader package.

```powershell
Sync-OSDAppAdobeAcrobatUnified
Add-OSDAppAdobeAcrobatUnified
```

The cache contains:

```text
BuiltIn\AdobeAcrobatUnified\
├── Package.zip
└── CacheInfo.json
```

The ZIP remains compressed while cached and staged. During installation the standalone runner extracts it to the local work directory, locates `Setup.exe`, and runs the Adobe-supported silent installation command:

```text
Setup.exe /sAll /msi ADDLOCAL=ALL
```

Only the x64 Unified installer is supported by this built-in.

## Deployment flow

The same commands are used with or without USB cache:

```powershell
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
```

In WinPE, `Add-OSDAppMicrosoft365Apps` and `Add-OSDAppTeams` stage deployment intent and any already-available cached payload into Windows Temp. A USB cache is not required.

In full Windows, PreInstall resolves the source automatically:
- if an `OSDCloud` USB cache is present, it is used and updated;
- if no `OSDCloud` USB cache is present, content is acquired directly to the local Windows runtime;
- current content is staged locally before the runner starts;
- the runner installs from local content.

## No-USB mode

No alternate parameter or command is required.

When no `OSDCloud` volume is connected, PreInstall downloads the current Microsoft 365 Apps and Teams content directly into the local Windows runtime under `%SystemRoot%\Temp\OSDApps`. The runner then installs from that local source.

When an `OSDCloud` volume is connected, it is detected automatically. Existing cache content is used when available and the cache is refreshed/updated during SetupComplete.

A completely blank `OSDCloud` volume is supported. OSD Apps creates the cache structure and populates it during the full-Windows pre-install phase.

## Fallback behavior

A refresh failure must not block deployment when a usable staged or USB-cached fallback exists. If there is no usable local/USB source and online acquisition also fails, PreInstall returns a fatal error and the runner is not started.

If an `OSDCloud` USB is not present, that is not an error: PreInstall acquires built-in content directly to the local Windows runtime.

When a refresh/acquisition problem occurs, PreInstall uses a complete local or USB-cached payload as fallback when one is available. If no usable source exists and online acquisition also fails, PreInstall returns a fatal error and the runner is not started.

Office refresh has a 20-minute timeout by default.

## USB cache behavior

USB is not required for built-in deployment.

If an `OSDCloud` USB volume is detected, cache functionality is enabled automatically. Keep that media connected until OOBE is displayed so SetupComplete can use and update the cache.

If no `OSDCloud` volume is present, built-ins are acquired directly to the local Windows runtime.


## Verbose staging diagnostics

Use:

```powershell
Add-OSDAppMicrosoft365Apps -Verbose
Add-OSDAppTeams -Verbose
```

Verbose output shows:
- offline Windows target detection;
- OSDCloud cache-volume detection;
- whether an existing built-in cache is complete;
- local staging decisions;
- SetupComplete integration;
- the selected acquisition path.

When OSDCloud cache media is detected, the Add cmdlet also emits a warning to keep the USB connected until OOBE is displayed.

The same decisions are written to the CMTrace-compatible logs.


## Validated cache bootstrap

A blank-cache deployment has been validated successfully with only a connected USB volume labeled `OSDCloud`.

Before reboot, both Add cmdlets reported that the OSDCloud cache volume was available but no usable built-in cache existed. During SetupComplete:

- Microsoft 365 Apps was synchronized from no previous cached version to a current Office build;
- Microsoft Teams downloaded and created a new cached MSIX;
- both payloads were staged to the local Windows runtime;
- Microsoft 365 Apps installation completed with exit code `0`;
- Microsoft Teams provisioning completed with exit code `0`;
- the runner completed successfully and scheduled runtime cleanup.

No pre-created `OSDApps` directory or built-in payload was required.


## Validated existing-cache refresh

The existing-cache + online path has also been validated successfully:

```text
complete Office and Teams cache present on OSDCloud USB
→ WinPE detects CacheAvailable=True for both built-ins
→ cached payload is staged as fallback
→ SetupComplete synchronizes Office against the existing cache
→ Office remains on the same current build
→ Teams metadata check reports no package update
→ both applications install successfully
```

This confirms that the same Add commands support both cache bootstrap and cache reuse without changing deployment syntax.
