# Performance

OSDApps includes explicit runtime timing so cold-cache and warm-cache deployments can be compared without manually reconstructing every phase from timestamps.

## Validated cold vs warm cache benchmark

The following benchmark was captured with OSDApps 0.29.1 using the same hardware, the same OSDCloud USB stick, the same application order, and the same deployment configuration.

![OSDApps 0.29.1 cold vs warm cache benchmark](images/cold-warm-benchmark.svg)

| Phase | Cold cache | Warm cache | Difference |
| --- | ---: | ---: | ---: |
| PreInstall / refresh | 125.2 s | 40.6 s | -84.6 s |
| Runner / installations | 330.7 s | 327.4 s | -3.3 s |
| **Total measured Windows phase** | **455.9 s** | **368.0 s** | **-87.9 s** |

That is approximately:

```text
Cold cache  7 min 36 s
Warm cache  6 min 08 s
Difference  1 min 28 s faster
```

The warm-cache run is about 19% faster across the measured PreInstall + Runner phases.

## Application set

The validated queue deliberately mixed built-in and repository applications:

| Application | Source |
| --- | --- |
| Microsoft 365 Apps | Built-in |
| Microsoft Teams | Built-in |
| Google Chrome Enterprise | Built-in |
| Omnissa Horizon Client | Self-maintained repository example |
| Notepad++ | Self-maintained repository example |
| Adobe Acrobat Unified | Built-in |

`OmnissaHorizonClient` and `NotepadPlusPlus` were packages from the test repository used for this benchmark. They are not built into OSDApps. Their repository synchronization/cache validation occurred in WinPE; the Runner measurements shown here cover the later local validation/extraction/installation phase.

The installation order was identical for both runs.

## What the benchmark shows

The important result is not only that the warm-cache deployment is faster. The location of the time saving is equally important.

```text
PreInstall
125.2 s → 40.6 s
84.6 s faster

Runner
330.7 s → 327.4 s
3.3 s faster
```

The Runner remains almost identical between both runs. The cache therefore does what it is designed to do: reduce acquisition and refresh work before installation while keeping the installation queue and install behavior stable.

## Per-application installation consistency

The complete application-processing timings were also highly consistent:

| Application | Cold cache | Warm cache | Difference |
| --- | ---: | ---: | ---: |
| Microsoft 365 Apps | 142.6 s | 141.6 s | -1.0 s |
| Microsoft Teams | 1.1 s | 1.1 s | 0.0 s |
| Google Chrome Enterprise | 18.1 s | 18.2 s | +0.1 s |
| Omnissa Horizon Client | 48.9 s | 47.7 s | -1.2 s |
| Notepad++ | 10.2 s | 9.2 s | -1.0 s |
| Adobe Acrobat Unified | 109.4 s | 109.3 s | -0.1 s |

This confirms that cache state primarily affects content acquisition and freshness validation, not the application installation itself.

For repository applications, `ApplicationInstallComplete` includes the complete processing time for that queue item, including SHA-256 validation and extraction before `Install.ps1` is started.

## Cold-cache acquisition observations

During the cold run:

| Built-in | Refresh duration | Download observation |
| --- | ---: | --- |
| Microsoft 365 Apps | 84.5 s | Office content synchronized by ODT |
| Microsoft Teams | 6.0 s | 272.9 MB MSIX downloaded in 4.3 s |
| Google Chrome Enterprise | 3.0 s | 161.8 MB MSI downloaded in 2.3 s |
| Adobe Acrobat Unified | 28.1 s | 1617.6 MB ZIP downloaded in 22.7 s |

The measured transfer rates for the large direct downloads were approximately:

```text
Teams MSIX   63.8 MB/s
Chrome MSI   70.2 MB/s
Adobe ZIP    71.4 MB/s
```

Microsoft 365 Apps is intentionally different: OSDApps delegates Office synchronization to the Office Deployment Tool rather than implementing a separate generic HTTP freshness mechanism.

## Warm-cache behavior

During the warm run:

- Microsoft 365 Apps retained build `16.0.20430.20146` and reported `VersionChanged=False`;
- Microsoft Teams reported `PackageUpdated=False`;
- Google Chrome Enterprise reported `PackageUpdated=False`;
- Adobe Acrobat Unified reported `PackageUpdated=False`;
- Omnissa Horizon Client and Notepad++ both reported `PackageCurrent` during repository synchronization.

The only intentional Teams download was the small Teams bootstrapper. The much larger Teams MSIX was reused from cache.

This is the expected OSDApps warm-cache behavior:

```text
existing cache
→ validate freshness
→ download only when required
→ stage locally
→ install in the same queue order
```

## Reproducing the benchmark

Use the same application order for cold and warm runs:

```powershell
Import-Module E:\Modules\OSDApps\OSDApps.psd1 -Force

Set-OSDAppConfiguration `
    -CatalogUri "https://example.blob.core.windows.net/osdapps/catalog.json" `
    -CleanupMode Never

# Built-ins
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
Add-OSDAppGoogleChromeEnterprise

# Example applications from the configured repository
Add-OSDApp OmnissaHorizonClient
Add-OSDApp NotepadPlusPlus

# Built-in
Add-OSDAppAdobeAcrobatUnified
```

For the cold run, start with an empty OSDApps cache. For the warm run, reuse the cache populated by the cold run.

Relevant runtime events include:

```text
BuiltInRefreshComplete
PreInstallComplete
ApplicationInstallComplete
InstallComplete
```

The runtime log is written by default to:

```text
%ProgramData%\OSDApps\Logs\Runtime.log
```

The module-side cache and staging log remains:

```text
<OSDCloud>:\OSDApps\Logs\Client.log
```

Performance depends on network, vendor CDN throughput, storage, CPU, application behavior, and hardware. These numbers are therefore a validated reference measurement, not a guaranteed deployment duration.
