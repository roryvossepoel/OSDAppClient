# Reference Flows

OSD Apps has validated both repository and built-in deployment paths.

## Repository application flow

```text
online catalog.json
→ resolve Apps/<AppId>/manifest.json
→ Add-OSDApp automatically synchronizes requested app in WinPE
→ resolve compatible architecture
→ download Package.zip
→ validate SHA-256
→ CacheCatalog.json + Package.zip on OSDCloud USB
→ stage DeviceManifest.json + Package.zip
→ SetupComplete
→ runner validates SHA-256 again
→ extract Package.zip
→ run Install.ps1
```

The repository flow was validated with Notepad++ 8.9.8.1 and also combined successfully in one deployment with the Microsoft Teams built-in.

## Built-in blank-cache bootstrap

```text
blank USB volume labeled OSDCloud
→ Add built-in deployment intent
→ no usable built-in cache exists in WinPE
→ SetupComplete detects OSDCloud USB
→ vendor cache is populated from scratch
→ payload is staged to Windows Temp
→ application installs successfully
→ runtime cleanup is scheduled
```

## Built-in existing-cache refresh

```text
complete built-in cache on OSDCloud USB
→ Add command detects existing cache
→ cached payload is staged as fallback
→ SetupComplete refreshes against vendor endpoint
→ unchanged content is reused
→ application installs successfully
```

For maintained technical documentation, see:
- [Architecture](docs/architecture.md)
- [Built-in applications](docs/built-in-apps.md)
- [Repository applications](docs/repository.md)
- [Runtime and cleanup](docs/runtime.md)
