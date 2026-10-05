# Reference Flows

OSD Apps has validated both repository and built-in deployment paths.

## Built-in blank-cache bootstrap

```text
blank USB volume labeled OSDCloud
→ Add-OSDAppMicrosoft365Apps
→ Add-OSDAppTeams
→ no usable built-in cache exists in WinPE
→ SetupComplete detects OSDCloud USB
→ Office cache is populated from scratch
→ Teams cache is populated from scratch
→ payloads are staged to Windows Temp
→ Office and Teams install successfully
→ runtime cleanup is scheduled
```

## Built-in existing-cache refresh

```text
complete Office + Teams cache on OSDCloud USB
→ Add commands detect CacheAvailable=True
→ cached payload is staged as fallback
→ SetupComplete synchronizes against Microsoft endpoints
→ Office remains on the current cached build when no new build exists
→ Teams skips MSIX download when metadata is unchanged
→ both applications install successfully
```

## Repository application flow

```text
online catalog.json
→ Sync-OSDAppRepository in WinPE
→ SHA-256 validation
→ CacheCatalog.json + Package.zip on OSDCloud USB
→ Add-OSDApp
→ DeviceManifest.json
→ SetupComplete
→ runner validates SHA-256 again
→ extract Package.zip
→ run Install.ps1
```

For the maintained technical documentation, see:
- [Architecture](docs/architecture.md)
- [Built-in applications](docs/built-in-apps.md)
- [Repository applications](docs/repository.md)
- [Runtime and cleanup](docs/runtime.md)
