# Changelog

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
