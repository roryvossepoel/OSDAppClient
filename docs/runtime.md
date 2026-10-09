# Runtime and cleanup

![Application queue and install order](images/application-queue.svg)


OSD Apps uses standalone runtime scripts during SetupComplete.

The OSDApps module itself does **not** need to be installed in deployed Windows.

## Runtime content

The public Add cmdlets stage their runtime content under:

```text
%SystemRoot%\Temp\OSDApps
```

Typical content:

```text
DeviceManifest.json
Invoke-OSDAppPreInstall.ps1
Invoke-OSDAppRunner.ps1
Packages\
BuiltIn\
Work\
```

## SetupComplete order

```text
SetupComplete.cmd
→ Invoke-OSDAppPreInstall.ps1
→ Invoke-OSDAppRunner.ps1
```

### PreInstall

PreInstall:
- detects the optional USB cache volume using the configured `CacheVolumeLabel` (default `OSDCloud`);
- detects network availability;
- uses/updates the USB cache when present;
- acquires built-ins directly to the local runtime when no USB cache is present;
- restages current built-in content locally before installation;
- falls back to a complete staged or USB-cached payload when refresh fails;
- returns a fatal error only when no usable source exists.

### Runner

Runner:
- reads `DeviceManifest.json`;
- validates repository package integrity;
- extracts repository packages;
- executes `Install.ps1`;
- installs built-ins;
- extracts Adobe Acrobat Unified's cached ZIP locally before invoking Adobe Setup.exe;
- installs vendor MSI built-ins such as Google Chrome Enterprise and Mozilla Firefox Enterprise through `msiexec.exe /i ... /qn /norestart`;
- stops on unrecoverable installation failure;
- schedules cleanup after full success.

## Runtime configuration

Runtime behavior is controlled through the general module configuration:

```powershell
Set-OSDAppConfiguration `
    -CatalogUri 'https://example.blob.core.windows.net/osdapps/catalog.json' `
    -CleanupMode OnSuccess `
    -CacheVolumeLabel 'OSDCloud' `
    -LogPath '%ProgramData%\OSDApps\Logs\Runtime.log'
```

The effective values are written into `DeviceManifest.json` when applications are staged, so SetupComplete does not depend on the PowerShell module being present in full Windows.

`CleanupMode` supports:

```text
OnSuccess  remove %SystemRoot%\Temp\OSDApps after a successful run
Never      retain the staged runtime, payloads, and Work directory
```

On failure, source is retained automatically.

## Cleanup policy

With `CleanupMode OnSuccess`:

```text
successful run
→ write final log events
→ start cleanup helper
→ runner exits
→ cleanup helper removes %SystemRoot%\Temp\OSDApps
→ cleanup helper removes itself
```

With `CleanupMode Never`, cleanup is skipped and `CleanupSkipped` is logged.

## Logging

Persistent runtime logs are written to the configured `LogPath`. The default is:

```text
%ProgramData%\OSDApps\Logs\Runtime.log
```

Logs are CMTrace-compatible and remain after source cleanup.

The log is rotated automatically:
- active `Runtime.log`
- `Runtime.log.1`
- `Runtime.log.2`
- `Runtime.log.3`

Important events include:

```text
RefreshStart
DownloadStart
DownloadComplete
CacheVolumeFound
CacheVolumeNotFound
BuiltInCacheRestaged
BuiltInRefreshStart
BuiltInRefreshComplete
BuiltInRefreshFailed
RefreshComplete
PreInstallComplete
InstallStart
PackageIntegrityValidated
PackageInstallStart
PackageInstallComplete
BuiltInInstallStart
BuiltInInstallWaiting
BuiltInInstallTimeout
BuiltInInstallComplete
ApplicationInstallComplete
ApplicationInstallFailed
InstallFailed
InstallComplete
CleanupScheduled
CleanupSkipped
```


For built-in synchronization, completion data distinguishes synchronization from actual content changes:

```text
Microsoft 365 Apps: CacheSynchronized, VersionChanged
Microsoft Teams:    CacheSynchronized, PackageUpdated
```

This prevents a successful cache synchronization from being misread as a new application version download.


Adobe Acrobat Unified uses a 15-minute installation timeout by default. The runner writes a heartbeat every 60 seconds while Adobe Setup is still running. If the timeout is reached, the Adobe setup process tree is terminated, `BuiltInInstallTimeout` is logged, the deployment fails, and the runtime source is retained for troubleshooting.

The timeout can be overridden when staging:

```powershell
Add-OSDAppAdobeAcrobatUnified -InstallTimeoutMinutes 20
```


Large built-in payloads are downloaded with the same streaming HttpClient approach used by the module cache downloader. Downloads are written to a temporary `.download` file and atomically moved into place only after success.

Runtime download logging includes:

```text
DownloadStart
DownloadComplete
Bytes
SizeMB
DurationSeconds
AverageMBps
```

This avoids the significant performance overhead observed with `Invoke-WebRequest -OutFile` for large payloads such as Adobe Acrobat Unified.


## Vendor MSI built-ins

MSI-based built-ins (Google Chrome Enterprise, Mozilla Firefox Enterprise and Cisco Webex) use the generic `VendorMsi` runtime type. The MSI is always acquired directly from the vendor, staged locally, and installed with Windows Installer.

```text
vendor MSI
→ optional OSDCloud USB cache
→ local Package.msi
→ msiexec.exe /i Package.msi /qn /norestart
```

The generic MSI runner appends any validated built-in `MsiProperties` (for example, Cisco Webex per-machine, autostart and update settings) to the silent `msiexec` command. It uses a 10-minute default timeout, writes 60-second `BuiltInInstallWaiting` heartbeat events, accepts exit codes `0` and `3010`, and retains the runtime source if installation fails.


## Timing and failure diagnostics

OSDApps writes explicit duration values so performance reporting does not need to infer every phase from timestamps.

Key duration fields include:

```text
PreInstallComplete       DurationSeconds
BuiltInRefreshComplete   DurationSeconds
ApplicationInstallComplete DurationSeconds
InstallComplete          DurationSeconds
```

`ApplicationInstallComplete` is written for both repository and built-in applications and measures the complete processing time for that queue item, including validation/extraction where applicable.

Failures are also categorized for reporting and troubleshooting.

PreInstall categories include:

```text
NetworkUnavailable
Timeout
CacheOrSourceMissing
RemoteAcquisition
PreInstallError
```

Runner categories include:

```text
HashMismatch
SourceMissing
Timeout
InstallerFailed
RuntimeError
```

The original error text remains in the log alongside the category.
