# Built-in applications

Built-in applications use vendor-native acquisition and installation instead of the repository package contract.

Currently supported:

```text
Microsoft365Apps
Teams
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

## Cached mode

Cached mode is the default:

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

## Online mode

```powershell
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams -BuiltInInstallMode Online
```

Online mode skips the cached payload model. The vendor bootstrapper/configuration is staged and installation downloads required content during SetupComplete.

## Fallback behavior

A refresh failure must not block deployment when a usable staged or USB-cached fallback exists. If there is no usable local/USB source and online acquisition also fails, PreInstall returns a fatal error and the runner is not started.

If an `OSDCloud` USB is not present, that is not an error: PreInstall acquires built-in content directly to the local Windows runtime.

When a refresh/acquisition problem occurs, PreInstall uses a complete local or USB-cached payload as fallback when one is available. If no usable source exists and online acquisition also fails, PreInstall returns a fatal error and the runner is not started.

Office refresh has a 20-minute timeout by default.

## USB requirement

Keep the OSDCloud USB connected until OOBE is displayed.

The built-in refresh/update phase runs in full Windows before installation. If cache functionality is being used, keep the `OSDCloud` USB connected until OOBE so the cache can be checked and updated. Without an `OSDCloud` USB cache, built-ins can be acquired directly to the local Windows runtime instead.
