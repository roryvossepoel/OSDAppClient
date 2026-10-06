# OSD Apps Architecture

The maintained architecture documentation lives in [docs/architecture.md](docs/architecture.md).

OSD Apps consists of two complementary PowerShell modules:

- **OSDAppClient** — deployment-time discovery, caching, staging, SetupComplete integration, and the standalone pre-OOBE runtime.
- **OSDAppRepo** — package authoring and repository management for `catalog.json` and `Package.zip`.

The current deployment model is:

```text
WinPE / OSDCloud v2
→ repository apps synchronize/cache in WinPE
→ Add commands stage app intent and available content

First boot / full Windows
→ optional OSDCloud USB cache is detected automatically
→ built-in Office / Teams content is synchronized or acquired
→ current payload is staged locally
→ SetupComplete installs applications
→ runtime source is cleaned up
→ OOBE / Autopilot
```

Metadata terminology:

```text
catalog.json                                      online application/package index
Apps/<AppId>/<Version>/<Architecture>/manifest.json  package metadata beside Package.zip
CacheCatalog.json                                 local OSDCloud USB repository snapshot
DeviceManifest.json                               per-device ordered Apps queue
```

See [docs/architecture.md](docs/architecture.md) for source resolution, fallback behavior, validated cache scenarios, and runtime details.

## Device manifest

`DeviceManifest.json` uses one ordered `Apps` array for all staged applications. Repository and built-in entries are kept in the exact order in which their `Add-*` commands were called. `Source` identifies the execution path (`Repository` or `BuiltIn`). PreInstall filters the built-in entries for acquisition, while the runner executes the complete array from top to bottom.
