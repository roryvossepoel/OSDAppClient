# Performance

OSDApps includes explicit runtime timing so cold-cache and warm-cache deployments can be compared without manually reconstructing every phase from timestamps.

## 0.30.0 — four field-validated deployments (9 October 2026)

The OSDApps **0.30.0** deployments covered no USB, a cold USB cache, a warm USB cache, and the same warm cache with a modified Office configuration (Monthly Enterprise, Dutch, Visio and Project). All six applications returned successful installation exit codes in each deployment.

| Measured phase | No USB | Cold USB | Warm USB | Changed Office, warm USB |
| --- | ---: | ---: | ---: | ---: |
| PreInstall | 217.3 s | 114.2 s | **41.7 s** | 104.1 s |
| Runner | 329.3 s | 328.4 s | 330.4 s | 346.0 s |
| **Total** | **546.6 s (9:07)** | **442.6 s (7:23)** | **372.1 s (6:12)** | **450.1 s (7:30)** |

**Warm vs cold USB saved 70.5 s (15.9%)** in the reported Windows phases. The warm USB run also took 174.5 s (31.9%) less than the no-USB run. These are `PreInstall + Runner` stopwatch durations, not end-to-end OSDCloud/OOBE elapsed times.

### Built-in acquisition/refresh duration

| Built-in | No USB | Cold USB | Warm USB | Modified Office |
| --- | ---: | ---: | ---: | ---: |
| Microsoft 365 Apps | 69.4 s | 74.5 s | 31.8 s | 93.5 s |
| Teams | 4.3 s | 5.4 s | 1.2 s | 1.5 s |
| Chrome Enterprise | 2.4 s | 3.0 s | 0.5 s | 0.5 s |
| Adobe Acrobat Unified | 138.0 s | 27.6 s | 4.7 s | 4.9 s |

Office kept the same detected build (`16.0.20430.20146`) in the warm and changed-configuration runs. The unchanged versions do **not** mean that requested languages or additional products were ignored. Test 4's staged XML contained three products; after SetupComplete, Word, Excel, Visio and Project executable files were reported present by the tester. Product activation and Office UI update-channel state were not independently checked.

In the warm and modified-Office runs, Teams, Chrome and Adobe reported `PackageUpdated=False`. The Teams bootstrapper was still refreshed. Both organization-managed repository packages passed SHA-256 checks and installed successfully.

### Application-processing times

| Application | No USB | Cold USB | Warm USB | Modified Office |
| --- | ---: | ---: | ---: | ---: |
| Microsoft 365 Apps | 136.4 s | 136.5 s | 138.5 s | 150.8 s |
| Teams | 1.1 s | 1.1 s | 1.1 s | 1.1 s |
| Chrome Enterprise | 18.1 s | 18.1 s | 18.2 s | 18.1 s |
| Adobe Acrobat Unified | 107.8 s | 107.7 s | 107.8 s | 109.8 s |
| Omnissa Horizon Client | 55.2 s | 55.4 s | 55.2 s | 55.5 s |
| Notepad++ | 10.2 s | 9.2 s | 9.2 s | 10.2 s |

**Interpretation:** Most warm-cache savings occur during acquisition, while actual application installation is nearly unchanged. One particularly important confounder is the cold-run Adobe download: it took 137 s without USB but only 21.9 s in the cold-USB run, despite downloading the same 1,617.6 MB package. This is likely related to variable network/CDN throughput, not cache reuse in the initially empty USB run. These are single field observations, not controlled comparative benchmarks.

Full scenarios, success criteria and test limitations: [Validation matrix](testing.md).

## Historical 0.29.1 cold vs warm cache benchmark


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
