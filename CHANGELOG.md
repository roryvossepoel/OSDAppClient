# Changelog

## 0.29.0

### Added

- Added `Get-OSDAppCache` to inspect repository and built-in cache entries, including source, version, architecture, last sync time, size, validity, source policy and sync method.
- Added explicit `PreInstallComplete` and runner duration logging.
- Added generic per-application `ApplicationInstallComplete` timing events across repository and built-in applications.
- Added failure categories for PreInstall and Runner failures.
- Extended repository validation with duplicate references, orphaned manifests, required success codes, archive definition validation, package size and repository free-space information.

### Changed

- Built-in cache metadata now uses consistent `SourcePolicy`, `SyncMethod` and `Updated` fields.
- Built-in refresh completion events include per-application refresh duration.
- Runner success and failure events include total runtime duration.

## 0.28.1

### Changed

- `Set-OSDAppConfiguration` is now silent by default, matching normal PowerShell `Set-*` behavior.
- Added `-PassThru` to return the effective configuration when desired.
- Use `Get-OSDAppConfiguration` to display the active configuration explicitly.

## 0.28.0

### Changed

- Renamed the module and project identity from `OSDAppClient` to `OSDApps`.
- The module entry files are now `OSDApps.psd1` and `OSDApps.psm1`; public cmdlets keep the `OSDApp` noun prefix.
- Consolidated deployment, runtime, cache, and lightweight repository authoring into one module.
- A separate OSDAppRepo module is no longer part of the architecture.

### Added

- Added `New-OSDAppRepository` for creating the static repository structure and empty `catalog.json`.
- Added `New-OSDAppPackage` for building the fixed `Package/Install.ps1` archive contract.
- Added `Add-OSDAppPackage` for generating package metadata, SHA-256, repository folders, and catalog references.
- Added `Test-OSDAppPackage` and `Test-OSDAppRepository` validation helpers.
- Added repository and package source templates under `Examples`.
- Expanded repository documentation so a repository can also be built manually without helper cmdlets.

## 0.27.1

### Fixed

- Selective repository synchronization now merges synchronized packages into the existing `CacheCatalog.json` instead of replacing the catalog with only the latest selection.
- Existing cached repository applications remain registered when another application is synchronized later.
- Re-synchronizing the same application replaces only that application's cache catalog entry.
- Synchronization logging now reports both the number of packages synchronized in the current operation and the total cached package count.

## 0.27.0

### Changed

- Added `Set-OSDAppConfiguration` and `Get-OSDAppConfiguration` as the single general configuration surface.
- Removed the standalone `Set-OSDAppCatalog` configuration cmdlet.
- General configuration now includes `CatalogUri`, `CleanupMode`, `CacheVolumeLabel`, and `LogPath`.
- `CleanupMode` replaces the previous `KeepSource` runtime flag and supports `OnSuccess` or `Never`.
- Staging writes the effective runtime configuration into `DeviceManifest.json`.
- PreInstall uses the staged `CacheVolumeLabel` and `LogPath`.
- The runner uses the staged `CleanupMode` and `LogPath`.
- Repository discovery and synchronization use the configured `CatalogUri`.
- Configuration values can be updated individually; unspecified values are preserved.

## 0.26.0

### Changed

- Simplified `DeviceManifest.json` to one ordered `Apps` array.
- `Apps` contains both repository and built-in applications with a `Source` field and all metadata required by PreInstall and the runner.
- The position of an application in `Apps` is its installation order; no separate `Packages`, `BuiltInApps`, or `InstallOrder` collections are used.
- Every `Add-*` operation appends or moves its complete application entry to the end of `Apps`.
- PreInstall filters built-ins from `Apps` for acquisition/refresh while preserving queue order.
- The runner executes `Apps` from top to bottom across both repository and built-in sources.

## 0.25.0

### Changed

- Replaced fixed built-in priorities with a single global installation order.
- Every `Add-*` call appends its application to `DeviceManifest.json` under `InstallOrder`.
- Repository and built-in applications can now be interleaved in exactly the order they were added.
- Re-adding an application moves it to the end of `InstallOrder` without duplicating it.
- The runner logs the resolved global order through the `InstallOrder` event.
- Manifests without `InstallOrder` retain a compatibility fallback of repository apps first, then built-ins.

## 0.24.3

### Changed

- Built-in applications now use an explicit installation priority independent of staging or manifest order.
- Current built-in installation order:
  1. Microsoft 365 Apps
  2. Microsoft Teams
  3. Google Chrome Enterprise
  4. Mozilla Firefox Enterprise
  5. Adobe Acrobat Unified
- Unknown future built-ins use the default middle priority until an explicit position is assigned.
- Repository applications continue to install before built-in applications.
- The runner logs the resolved built-in order through the `BuiltInInstallOrder` event.

## 0.24.2

### Changed

- Built-in installation order is now deterministic.
- Microsoft 365 Apps is installed before the other built-in applications.
- Adobe Acrobat Unified is installed last.
- Other built-in applications retain their relative order from `DeviceManifest.json`.
- Repository applications continue to run before built-in applications.

## 0.24.1

### Fixed

- Repository staging no longer replaces the entire `DeviceManifest.json`.
- Existing `BuiltInApps` and `Runtime` metadata are preserved when `Add-OSDApp` stages repository applications.
- Existing repository package entries are merged by Id instead of being discarded.
- This fixes deployments where built-in applications were staged first and then silently removed from the manifest by a later repository app stage.

## 0.24.0

### Changed

- Repository packages now use a single top-level `Package` directory inside `Package.zip`.
- The runtime resolves repository installers from `Package/Install.ps1`.
- Repository `Install.ps1` now runs with the extracted `Package` directory as its working directory.
- Root-level `Install.ps1` archives are no longer supported.

## 0.23.0

### Changed

- Simplified the repository contract again: every deployable package now keeps `manifest.json` directly beside `Package.zip`.
- Root `catalog.json` points directly to package manifests per application and architecture.
- Package manifests contain all package metadata: Id, display name, version, architecture, success codes, archive filename, and SHA-256.
- `Package.zip` is resolved relative to its sibling package manifest; no `SourcePath` field is required.
- No migration or legacy repository compatibility is provided.

## 0.22.0

### Changed

- Adopted a clean repository contract using root `catalog.json` plus one `Apps/<Id>/manifest.json` per application.
- OSDAppClient resolves only the required application manifest(s), then flattens package metadata internally for the existing cache and runtime pipeline.
- Package `SourcePath` is relative to the application manifest.
- `Get-OSDAppCatalog` now reports application count instead of package count.
- No legacy single-manifest repository compatibility is provided.

## 0.21.5

### Changed

- `Add-OSDApp` now automatically synchronizes only the requested repository application(s) when an online catalog is configured.
- Normal repository deployment no longer requires a separate `Sync-OSDAppRepository` step.
- `Sync-OSDAppRepository` remains available for explicit full or selective cache preloading/refresh.
- If no online catalog is configured, `Add-OSDApp` can still use an existing valid repository cache.

## 0.21.4

### Fixed

- Existing OSD Apps blocks in `SetupComplete.cmd` are now refreshed instead of being left untouched.
- This repairs stale runner paths from older staging runs while preserving unrelated SetupComplete content.
- Current repository and built-in staging both use `%SystemDrive%\Windows\Temp\OSDApps` for PreInstall and Runner execution.

## 0.21.3

### Fixed

- Repository packages using a relative `Archive.SourcePath` can now be synchronized from an HTTP/HTTPS catalog.
- Relative package paths are resolved against the catalog location, so a catalog such as `https://host/container/manifest.json` can reference `Packages/App/Version/Architecture/Package.zip`.
- Local filesystem repositories continue to resolve `SourcePath` relative to the local manifest directory.

## 0.21.2

### Fixed

- Removed an accidental duplicated tail from both Firefox Enterprise public cmdlet files that caused a PowerShell parser error during module import.
- No Firefox acquisition, cache, staging, or installation behavior changed.

## 0.21.1

### Changed

- Kept Firefox Enterprise defaults intentionally simple: Rapid Release, x64, and `en-US`.
- Added PowerShell tab completion for common Firefox locales on `Add-OSDAppMozillaFirefoxEnterprise` and `Sync-OSDAppMozillaFirefoxEnterprise`.
- `-Language` remains open for other valid Mozilla locale values; completion is guidance rather than a hard allow-list.

### Validation

- Validated blank-cache bootstrap for Google Chrome Enterprise x64 and Mozilla Firefox Enterprise Rapid x64.
- Both vendor MSI packages were downloaded during SetupComplete, persisted to the OSDCloud USB cache, staged locally, and installed successfully with exit code `0`.

## 0.21.0

### Added

- Added `GoogleChromeEnterprise` built-in support using Google's vendor-hosted Enterprise MSI.
- Added x64 and x86 Chrome cache variants; x64 is the default.
- Added `MozillaFirefoxEnterprise` built-in support using Mozilla's official MSI download endpoint.
- Added Firefox Rapid Release and ESR channels, x64/x86 architectures, and configurable Mozilla language.
- Added generic `VendorMsi` SetupComplete runtime support using `msiexec.exe /i ... /qn /norestart`.
- Added MSI installation heartbeat, timeout protection, and success handling for exit codes `0` and `3010`.

### Validation

- Chrome and Firefox integrations are implemented but still require end-to-end OSD validation.


## 0.20.3

### Changed

- Replaced large SetupComplete `Invoke-WebRequest` downloads with streaming `HttpClient` transfers.
- Uses temporary `.download` files and only replaces the destination after a successful transfer.
- Added runtime transfer metrics: bytes, size, duration, and average MB/s.
- Improved module download progress with transferred/total size, percentage, average speed, elapsed time, and estimated remaining time.
- Applied the streaming path to Adobe Acrobat Unified, Teams MSIX/bootstrapper, and Office Deployment Tool bootstrapper downloads.


## 0.20.2

### Changed

- Added a 15-minute default timeout for Adobe Acrobat Unified installation during SetupComplete.
- Added 60-second `BuiltInInstallWaiting` heartbeat events while Adobe Setup is still running.
- Added `BuiltInInstallTimeout` logging and process-tree termination on timeout.
- Added `-InstallTimeoutMinutes` to `Add-OSDAppAdobeAcrobatUnified` for controlled overrides.


## 0.20.1

### Added

- Added `AdobeAcrobatUnified` as a third built-in application.
- Adobe Acrobat Unified now supports both x64 and x86 packages; x64 is the default and cache variants are stored separately.
- Added `Sync-OSDAppAdobeAcrobatUnified` and `Add-OSDAppAdobeAcrobatUnified`.
- Uses Adobe's official x64 Unified Acrobat/Reader ZIP as the vendor source.
- Supports the same optional OSDCloud USB cache model as Microsoft 365 Apps and Teams.
- Cached Adobe content remains compressed as `Package.zip`; the runner extracts it locally during SetupComplete and launches `Setup.exe /sAll /msi ADDLOCAL=ALL`.
- Supports blank-cache bootstrap, cache reuse, no-USB online acquisition, and offline fallback when a complete cached payload has already been staged.


## 0.19.0

### Changed

- Simplified the public command surface. Low-level cache validation, content staging, repository synchronization internals, and SetupComplete integration are now private helpers.
- Renamed local repository cache metadata from `CacheManifest.json` to `CacheCatalog.json`.
- `Get-OSDAppCatalog` now reports compact catalog status instead of listing applications.
- `Get-OSDApp` is now the unified application discovery command for online repository state, USB cache state, and built-in applications.
- `Add-OSDApp` remains repository-only; Microsoft 365 Apps and Teams use dedicated Add commands.
- Built-in completion logging now distinguishes synchronization from an actual content/version change:
  - Microsoft 365 Apps: `CacheSynchronized`, `VersionChanged`
  - Microsoft Teams: `CacheSynchronized`, `PackageUpdated`

### Built-in acquisition

- Built-in deployment no longer requires pre-populated USB media.
- A connected volume labeled `OSDCloud` is detected automatically and used as cache source and destination.
- A blank `OSDCloud` volume can be populated during SetupComplete.
- Without USB media, built-ins can be acquired directly to the local Windows runtime when online.
- Existing cached content is staged as fallback before the full-Windows refresh phase.

### Validated

- Blank `OSDCloud` USB cache bootstrap for Microsoft 365 Apps and Teams.
- Existing-cache + online refresh for Microsoft 365 Apps and Teams.
- Successful local staging, installation, and runtime cleanup scheduling for both built-ins.

## 0.18.x

Introduced optional USB built-in acquisition, dedicated built-in Add commands, OSDCloud-style verbose console output, and the standalone full-Windows PreInstall refresh phase.
