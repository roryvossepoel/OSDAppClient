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
DeviceManifest.json                               per-device staged installation manifest
```

See [docs/architecture.md](docs/architecture.md) for source resolution, fallback behavior, validated cache scenarios, and runtime details.
