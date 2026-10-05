# Runtime and cleanup

OSD Apps uses standalone runtime scripts during SetupComplete.

The OSDAppClient module itself does **not** need to be installed in deployed Windows.

## Runtime content

`Add-OSDApp` stages everything required under:

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
- detects an optional USB volume labeled `OSDCloud`;
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
- stops on unrecoverable installation failure;
- schedules cleanup after full success.

## Cleanup policy

Default behavior:

```text
successful run
→ write final log events
→ start cleanup helper
→ runner exits
→ cleanup helper removes %SystemRoot%\Temp\OSDApps
→ cleanup helper removes itself
```

This allows the runner to remove its own source directory safely after PowerShell releases the script.

On failure, source is retained automatically.

Runtime source is retained automatically when installation fails so the staged manifest, payload and work directory remain available for troubleshooting.

## Logging

Persistent runtime logs are written to:

```text
%ProgramData%\OSDApps\Logs\Install.log
```

Logs are CMTrace-compatible and remain after source cleanup.

The log is rotated automatically:
- active `Install.log`
- `Install.log.1`
- `Install.log.2`
- `Install.log.3`

Important events include:

```text
RefreshStart
CacheVolumeFound
CacheVolumeNotFound
BuiltInCacheRestaged
BuiltInRefreshStart
BuiltInRefreshComplete
BuiltInRefreshFailed
RefreshComplete
InstallStart
PackageIntegrityValidated
PackageInstallStart
PackageInstallComplete
BuiltInInstallStart
BuiltInInstallComplete
InstallFailed
InstallComplete
CleanupScheduled
CleanupSkipped
```
