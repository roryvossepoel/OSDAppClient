# Architecture

OSD Apps separates application acquisition, staging, refresh, installation, and cleanup.

## End-to-end flow

```mermaid
flowchart TB
    A[OSDCloud v2 in WinPE]
    B[Repository sync]
    C[Stage selected apps]
    D[Windows Temp runtime]
    E[First boot / full Windows]
    F[Built-in pre-install refresh]
    G[OSD App Runner]
    H[Cleanup runtime source]
    I[OOBE / Autopilot]

    A --> B --> C --> D --> E --> F --> G --> H --> I
```

## Repository lifecycle

```text
Azure Blob / repository
→ catalog.json
→ Sync-OSDAppRepository in WinPE
→ validate SHA-256
→ cache Package.zip on OSDCloud USB
→ Add-OSDApp
→ stage Package.zip to Windows Temp
→ runner validates SHA-256 again
→ extract
→ run Install.ps1
```

Repository acquisition stays in WinPE because it does not depend on a vendor installer.

## Built-in lifecycle

```text
Existing USB cache
→ stage in WinPE
→ first boot into full Windows
→ pre-install refresh/update
→ update shared USB cache
→ restage current local payload
→ install
```

Microsoft 365 Apps and Teams intentionally share this lifecycle.

## Why built-ins refresh in full Windows

The Office Deployment Tool cannot run in the x64 WinPE environment used during OSD Apps testing because the current ODT bootstrapper requires x86 Windows runtime / side-by-side components that are not available there.

Microsoft Teams synchronization can technically run in WinPE. OSD Apps still performs Teams refresh in the same full-Windows pre-install phase so built-in acquisition, update, fallback, logging, and troubleshooting follow one consistent model.

If Microsoft 365 Apps or Teams must be managed entirely from WinPE, package them as normal repository applications instead of using the built-in flow.

## Runtime locations

Temporary runtime:

```text
%SystemRoot%\Temp\OSDApps
```

Persistent logs:

```text
%ProgramData%\OSDApps\Logs
```

The runtime directory can contain:

```text
DeviceManifest.json
Invoke-OSDAppPreInstall.ps1
Invoke-OSDAppRunner.ps1
Packages\
BuiltIn\
Work\
```

After a successful installation the runtime directory is removed automatically unless `-KeepSource` was specified.
