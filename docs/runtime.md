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
- finds the OSDCloud USB;
- detects network availability;
- refreshes cached built-ins in full Windows;
- updates the shared USB cache;
- restages current built-in content;
- never blocks installation purely because refresh failed.

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

To retain source after success:

```powershell
Add-OSDApp Microsoft365Apps,Teams -KeepSource
```

Because retained source remains under Windows Temp, Windows may still remove it later during normal temporary-file maintenance.

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
