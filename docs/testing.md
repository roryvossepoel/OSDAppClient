# Validation matrix

This page tracks real OSDCloud v2 / OSDApps deployment scenarios. **Staging success alone is not an installation success**: the Windows `SetupComplete.cmd` phases must finish and the individual app results must be checked.

## Scenario coverage

| Scenario | Status | Evidence / expected behavior |
| --- | --- | --- |
| Empty OSDCloud USB cache, online | **Validated — 0.30.0 test 2** | USB cache populated during SetupComplete; six queued apps installed |
| Existing OSDCloud USB cache, online | **Validated — 0.30.0 tests 3 and 4** | Reuse/freshness checking; altered Office configuration tested separately |
| No USB cache, online | **Validated — 0.30.0 test 1** | Built-ins acquired on Windows volume; repository apps staged in WinPE |
| Existing OSDCloud USB cache, offline | **Validated — 0.30.0 test 5** | Network disconnected; warm USB cache recognized; six apps installed, each exit code 0 |
| No USB, offline | **Not yet validated** | Without a complete staged fallback, PreInstall is expected to stop before Runner |

## Real-world end-to-end validation — OSDApps 0.30.0

**Executed:** 9 October 2026, on freshly deployed Windows installations via OSDCloud v2. All four scenarios used OSDApps **0.30.0** from PowerShell Gallery, `CleanupMode=Never`, the same six application IDs, and the same installation order. These are four deployment executions, not repeated statistical benchmark samples.

The application queue, in order:

1. `Microsoft365Apps` (built-in; x64)
2. `Teams` (built-in; x64)
3. `GoogleChromeEnterprise` (built-in; x64)
4. `AdobeAcrobatUnified` (built-in; x64)
5. `OmnissaHorizonClient` (organization-managed repository; x64)
6. `NotepadPlusPlus` (organization-managed repository; x64)

Omnissa Horizon Client and Notepad++ were **test repository packages**, not OSDApps built-ins.

### Measured Windows phases

Durations below are from the `PreInstallComplete` / `InstallComplete` events in `Runtime.log`. **Total = PreInstall + Runner**, excluding WinPE/OSDCloud installation, module installation, repository staging and small gaps between phases.

| Test | USB cache state | PreInstall | Runner | Measured total | Runner outcome |
| --- | --- | ---: | ---: | ---: | --- |
| **1** | No USB connected | 217.3 s | 329.3 s | **546.6 s (9:07)** | **6/6**, success |
| **2** | USB connected, initially empty | 114.2 s | 328.4 s | **442.6 s (7:23)** | **6/6**, success |
| **3** | Same USB, populated (warm) | 41.7 s | 330.4 s | **372.1 s (6:12)** | **6/6**, success |
| **4** | Warm USB, changed Office configuration | 104.1 s | 346.0 s | **450.1 s (7:30)** | **6/6**, success |

**24 of 24 queued application executions reported successful completion** across the four `Runtime.log` files (each application installer returned exit code `0`). This is an installer/runtime result, not proof of every app's later activation or interactive launch.

### Per-test observations

**Test 1 — USB removed after OSDCloud, before OSDApps staging.** The USB remained disconnected through SetupComplete. Four built-ins acquired content on the local OS disk; both repository packages were staged locally in WinPE and their SHA-256 hashes validated by Runner. PreInstall and Runner completed successfully. This validates the USB-optional path and the Office PreInstall self-copy fix.

**Test 2 — cold USB cache.** The `OSDCloud` volume was present at `E:\OSDApps`. Both repository package cache entries passed the WinPE cache check; built-ins were acquired/synchronized to USB in full Windows. `CacheUsed=True`; PreInstall and Runner completed with six successful installs. The same USB was retained for the next scenarios.

**Test 3 — warm USB cache.** PreInstall reported `CacheUsed=True`. Office build `16.0.20430.20146` was unchanged (`VersionChanged=False`). Teams, Chrome and Adobe reported `PackageUpdated=False`; Teams downloaded only the small bootstrapper, not the large MSIX again. PreInstall fell from 114.2 s (cold USB) to 41.7 s (warm USB). Runner times remained close.

**Test 4 — warm USB with changed Microsoft 365 Apps configuration.** The staged XML was checked before reboot: x64 / ODT `OfficeClientEdition=64`, `MonthlyEnterprise`, `nl-nl`, updates enabled, plus `O365ProPlusRetail`, `VisioProRetail` and `ProjectProRetail`. Office PreInstall took 93.5 s; the detected Office build remained `16.0.20430.20146` (`VersionChanged=False`). Runner reported exit code `0` for all six queue entries. **Word, Excel, Visio and Project executables were separately confirmed present in Windows** after installation.

The unchanged build number in test 4 does **not** mean the Office configuration was unchanged: the extra products and language can use the same build. Separately checking installed executables was therefore important.

### Interpretation and remaining checks

- Warm USB versus cold USB reduced the **measured Windows phase** by **70.5 s**, largely in PreInstall (114.2 s to 41.7 s).
- Warm USB versus no USB reduced the measured Windows phase by **174.5 s**, but the no-USB and cold-USB runs had different observed Adobe download speeds. Do **not** attribute the entire difference to cache state; these are single real-world runs, not controlled or statistical benchmarks.
- The four execution paths and six installer exit codes were confirmed; **Office activation and the effective installed update channel were not independently verified**. The requested `MonthlyEnterprise` channel was checked in the staged XML, not confirmed in the installed Office update configuration.
- Other offline conditions (such as no USB with fully staged source), alternate x86/arm64 variants, failure/recovery paths and repeated timed samples remain separate tests.
- Source `Runtime.log` and WinPE staging checks were supplied during testing; raw environment logs were not added to the public repository.

## Offline end-to-end validation — OSDApps 0.30.0 test 5 (9 October 2026)

Test 5 started with a fully populated `OSDCloud` USB cache. All expected built-in source files were checked on the USB stick before reboot, and the two repository packages had already been staged. The network connection was physically disconnected before boot and remained unavailable throughout SetupComplete.

The `Runtime.log` confirmed `CacheVolumeFound`, `CacheUsed=True`, `BuiltInRefreshSkipped` for Office, Teams, Chrome and Adobe, and no online refresh. PreInstall completed in **7.6 s**; Runner completed in **380.7 s**. All six entries had successful install/provisioning exit codes (`0`), with a measured total of **388.3 s (6:28)**, excluding WinPE preparation.

The same run exposed an **Adobe staging path mismatch**: `BuiltInCacheRestaged` for Adobe showed the cache was copied from USB during PreInstall because the local archive was not at the manifest's architecture-specific path. The 0.30.1 change fixes that mismatch and adds file-copy regression tests. **Test 5 remains a valid successful fully offline deployment**; the additional path fix removes an unnecessary restage and aligns WinPE staging with runtime expectations.

## MicrosoftTeams rename — 0.31.0

The five completed real-world deployment scenarios above used **0.30.0** and therefore its original built-in ID `Teams`. In **0.31.0**, the canonical built-in ID, cache folder, WinPE staging, runtime manifest type and public cmdlets change to **`MicrosoftTeams`** with no automatic legacy compatibility or USB cache migration. New file-backed Pester tests validate the updated staging and runtime contracts. A fresh 0.31.0 SetupComplete deployment has not yet been field-verified; keep the original 0.30.0 test results as historical evidence rather than relabeling them.

## Cisco Webex built-in — 0.32.0

Cisco Webex was added with x64 and ARM64 non-localized MSI sources, an architecture-specific optional USB cache, validated MSI parameters and the shared `VendorMsi` SetupComplete runner. File-backed unit tests verify that WinPE cache staging and `DeviceManifest.json` resolve to the identical local MSI path.

**Not yet field-validated:** actual Cisco MSI retrieval and HTTP freshness metadata, offline installation and Webex application behavior on a deployed Windows device. The earlier six-app deployment results do not include Cisco Webex.

## Validated built-ins and remaining variants

The 0.30.0 end-to-end tests above cover Microsoft 365 Apps, Microsoft Teams, Adobe Acrobat Unified **x64**, and Google Chrome Enterprise **x64**. The earlier validation matrix also listed Mozilla Firefox Enterprise Rapid x64 as validated; it was **not** part of these four 0.30.0 runs.

Still requiring separate end-to-end checks:

- Google Chrome Enterprise x86
- Mozilla Firefox Enterprise Rapid x86
- Mozilla Firefox Enterprise ESR x64/x86
- Adobe Acrobat Unified x86
- Microsoft Teams x86 / arm64 and Microsoft 365 Apps x86 (new public architecture contract)

## Success criteria and logs

1. WinPE stages the intended `DeviceManifest.json` queue and any available repository payload.
2. USB cache is detected only when connected, or a local no-USB path is selected.
3. Repository `Package.zip` files validate against their SHA-256 metadata.
4. `SetupComplete.cmd` starts `Invoke-OSDAppPreInstall.ps1`; `PreInstallComplete` reports success.
5. `Invoke-OSDAppRunner.ps1` installs the six queued applications; each expected `*InstallComplete` has an accepted exit code.
6. The final `InstallComplete` reports the expected application count.
7. The configured `CleanupMode` is honored; for these tests `Never` retained the staged runtime.

Windows runtime log:

```text
%ProgramData%\OSDApps\Logs\Runtime.log
```

Module/cache log when USB is attached:

```text
<OSDCloud>:\OSDApps\Logs\Client.log
```

For a no-USB run, module-side logging may be on the Windows volume, while the standalone runner still uses the configured Windows runtime log.

## Historical cold/warm benchmark — OSDApps 0.29.1

The earlier 0.29.1 benchmark is retained separately, using the same hardware, USB stick, application set and install order for its cold/warm pair.

| Phase | Cold USB | Warm USB |
| --- | ---: | ---: |
| PreInstall | 125.2 s | 40.6 s |
| Runner | 330.7 s | 327.4 s |
| Measured Windows total | 455.9 s | 368.0 s |

See [Performance](performance.md) for the historical benchmark details and the updated 0.30.0 comparison.
