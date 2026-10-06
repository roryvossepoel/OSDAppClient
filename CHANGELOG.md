# Changelog

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
