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
Add-OSDApp Microsoft365Apps,Teams
```

In WinPE:
- no built-in refresh is performed;
- the existing USB cache is staged to Windows Temp.

In full Windows:
- PreInstall refreshes Office and Teams when possible;
- the shared USB cache is updated;
- current content is restaged locally;
- the runner installs from local content.

## Online mode

```powershell
Add-OSDApp Microsoft365Apps,Teams -BuiltInInstallMode Online
```

Online mode skips the cached payload model. The vendor bootstrapper/configuration is staged and installation downloads required content during SetupComplete.

## Fallback behavior

Built-in refresh must never become a deployment dependency.

If any of these occur:
- USB is missing;
- no active network is detected;
- Office CDN is unavailable;
- Office refresh times out;
- Teams refresh fails;

PreInstall logs a warning and continues with the payload already staged during WinPE.

Office refresh has a 20-minute timeout by default.

## USB requirement

Keep the OSDCloud USB connected until OOBE is displayed.

The built-in refresh/update phase runs in full Windows before installation, so removing the USB early prevents the shared cache from being checked and updated.
