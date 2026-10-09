# Validation matrix

This page distinguishes automated tests from observed end-to-end OSDCloud v2 / Windows Setup deployments.

## Scenario coverage

| Scenario | Status | Scope |
| --- | --- | --- |
| No OSDCloud USB + online | **Validated in 0.30.0** | Acquire built-ins to local Windows staging, stage repository apps in WinPE, install six apps |
| Empty OSDCloud USB cache + online | **Validated in 0.30.0** | Populate USB cache, stage locally, install six apps |
| Existing OSDCloud USB cache + online | **Validated in 0.30.0** | Reuse/refresh USB cache and install six apps |
| Warm USB + modified Office configuration + online | **Validated in 0.30.0** | Add Visio, Project, Dutch and Monthly Enterprise configuration; install six apps |
| Existing USB cache + offline | Not yet validated in 0.30.0 | Requires a complete pre-existing payload |
| No USB + offline | Not validated | Expected to fail without complete locally staged payloads |

## OSDApps 0.30.0 field validation — 9 October 2026

Four full deployments were run using OSDCloud v2, **OSDApps 0.30.0 from PowerShell Gallery**, and `CleanupMode=Never`. Each staged four built-in and two organization-managed repository applications in WinPE and installed them via SetupComplete before OOBE.

### Validated application queue

| Install order | Application | Source | Runtime result |
| ---: | --- | --- | --- |
| 1 | Microsoft 365 Apps | Built-in / ODT | Exit code 0 in all four |
| 2 | Microsoft Teams | Built-in | Exit code 0 in all four |
| 3 | Google Chrome Enterprise x64 | Built-in | Exit code 0 in all four |
| 4 | Adobe Acrobat Unified x64 | Built-in | Exit code 0 in all four |
| 5 | Omnissa Horizon Client x64 | Self-managed repository | Exit code 0; SHA-256 validated |
| 6 | Notepad++ x64 | Self-managed repository | Exit code 0; SHA-256 validated |

**24 of 24 application installation processes reported success in the runtime logs (6 per deployment).** This is deployment evidence; it does not by itself establish app functionality, licensing or every device setting.

### Test setup and timing

| Test | USB state | Office configuration | PreInstall | Runner | Combined measured phases | Outcome |
| --- | --- | --- | ---: | ---: | ---: | --- |
| 1 — no USB | USB removed after OSDCloud deployment, before OSDApps staging | x64, Current, en-us | 217.3 s | 329.3 s | **546.6 s (9:07)** | 6/6 |
| 2 — cold USB | Connected; initially empty OSDApps cache | Same as test 1 | 114.2 s | 328.4 s | **442.6 s (7:23)** | 6/6 |
| 3 — warm USB | Reused populated USB from test 2 | Same as test 1 | 41.7 s | 330.4 s | **372.1 s (6:12)** | 6/6 |
| 4 — changed Office | Reused warm USB from test 3 | x64, MonthlyEnterprise, nl-nl, VisioProRetail, ProjectProRetail, updates on | 104.1 s | 346.0 s | **450.1 s (7:30)** | 6/6 |

Reported totals sum the `PreInstall` and `Runner` stopwatch durations; handoff overhead, OSDCloud image deployment and OOBE are excluded. The runs were single observations, not a statistically controlled comparison. Hardware and network conditions were not held constant or independently documented for every run.

### Cache and runtime findings

- **No USB (test 1):** `CacheVolumeNotFound`, successful `PreInstallComplete` and `InstallComplete` with `ApplicationCount=6`. The previous Office configuration.xml self-copy failure did not recur.
- **Cold USB (test 2):** `CacheVolumeFound` at `E:\OSDApps`, `CacheUsed=True` and `CacheSynchronized=True`. All six installations succeeded; repository packages passed integrity checks.
- **Warm USB (test 3):** `CacheUsed=True`. Office retained `16.0.20430.20146` (`VersionChanged=False`); Teams, Chrome and Adobe reported `PackageUpdated=False`. Teams still fetched its small bootstrapper, not the large cached MSIX.
- **Changed Office (test 4):** Office refresh took 93.5 s versus 31.8 s in test 3, and its detected build stayed unchanged (`VersionChanged=False`). Teams, Chrome and Adobe again reported `PackageUpdated=False`. The user had checked before reboot that the Office XML included `O365ProPlusRetail`, `VisioProRetail`, `ProjectProRetail`, `MonthlyEnterprise`, `nl-nl` and enabled updates.

In test 4, the tester additionally verified presence of `WINWORD.EXE`, `EXCEL.EXE`, `VISIO.EXE` and `WINPROJ.EXE` in the expected Office installation folder (all four `True`). **Office activation and the effective update channel shown in the Office UI were not independently confirmed.**

### Interpretation and limits

- Warm USB vs cold USB: **70.5 s faster (15.9%)** in combined logged phases, predominantly due to PreInstall.
- Warm USB vs no USB: **174.5 s faster (31.9%)** in these observations.
- The runner stayed close to **328–330 s** for tests 1–3; the expanded Office configuration in test 4 had a **346.0 s** runner.
- The cold-USB run downloaded Adobe much faster than the no-USB run, so its shorter total cannot be attributed solely to having a USB cache. Network and CDN throughput varied.

### Reproduction checklist

For each test, start a fresh OSDCloud Windows deployment, keep WinPE running before the first reboot, install/import **OSDApps 0.30.0**, configure the source catalog and `CleanupMode Never`, then stage the six apps. Use a real catalog containing the two repository examples.

```powershell
Install-Module OSDApps -RequiredVersion 0.30.0 -Force -SkipPublisherCheck
Import-Module OSDApps -RequiredVersion 0.30.0 -Force
Set-OSDAppConfiguration -CatalogUri 'https://example.blob.core.windows.net/osdapps/catalog.json' -CacheVolumeLabel OSDCloud -CleanupMode Never

# Tests 1-3
Add-OSDAppMicrosoft365Apps
Add-OSDAppTeams
Add-OSDAppGoogleChromeEnterprise
Add-OSDAppAdobeAcrobatUnified
Add-OSDApp OmnissaHorizonClient
Add-OSDApp NotepadPlusPlus

# Test 4: instead of the default Office command above, use:
# Add-OSDAppMicrosoft365Apps -Channel MonthlyEnterprise -Language nl-nl -IncludeVisio -IncludeProject -UpdatesEnabled $true
```

For test 1, remove the USB after OSDCloud has applied Windows but before staging OSDApps. Test 2 uses the connected USB with a blank OSDApps cache. Tests 3–4 use the same USB without wiping its cache. Do not remove it while SetupComplete runs.

Before reboot, verify exactly six entries in `DeviceManifest.json`, the two repository ZIPs with SHA-256, both standalone runtime scripts and their references in `SetupComplete.cmd`. After reboot, verify `PreInstallComplete`, six successful installations and `InstallComplete`.

Runtime evidence: `%ProgramData%\OSDApps\Logs\Runtime.log`. WinPE/cache operations are logged under the USB `OSDApps\Logs` directory, or locally where applicable.

## Additional feature coverage

Mozilla Firefox Enterprise Rapid x64 had been tested previously but **was not included in this six-app 0.30.0 matrix**. Variants still needing dedicated end-to-end verification include Chrome x86, Firefox Rapid x86, Firefox ESR x64/x86, Adobe x86, Teams x86/ARM64 and Office x86.

## General success criteria

1. WinPE stages metadata and any required local/repository content.
2. SetupComplete starts PreInstall in full Windows and selects the intended source.
3. Full payloads exist under `%SystemRoot%\Temp\OSDApps` before installation.
4. Runner processes each app with an accepted exit code.
5. `PreInstallComplete` and `InstallComplete` are recorded.
6. Cleanup policy is honored (e.g., `Never` retains the staged runtime).
7. Independently verify app binaries, relevant settings and licensing where the test requires them.

## Historical 0.29.1 cold/warm benchmark

A previous benchmark with the same hardware, USB stick, application set and order compared:

| Phase | Cold cache | Warm cache |
| --- | ---: | ---: |
| PreInstall / refresh | 125.2 s | 40.6 s |
| Runner / installations | 330.7 s | 327.4 s |
| Total measured Windows phase | 455.9 s | 368.0 s |

Warm cache saved 87.9 seconds in the measured phases in that earlier run. See [Performance](performance.md) for both historical and 0.30.0 results.
