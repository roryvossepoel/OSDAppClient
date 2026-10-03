# Reference Flow

The first validated end-to-end OSD Apps Client flow uses Notepad++ 8.9.8.1.

## Proven runtime flow

```text
OSD Apps repository
        ↓
OSDAppsClient
        ↓
sync Package.zip to OSDCloud USB
        ↓
SHA-256 validation
        ↓
stage to offline Windows volume
        ↓
DeviceManifest.json
        ↓
OSD Apps Runner
        ↓
expand Package.zip
        ↓
run Install.ps1
        ↓
Notepad++ installed successfully
```

The validated runtime log was:

```text
Extracting NotepadPlusPlus 8.9.8.1
Installing NotepadPlusPlus 8.9.8.1
Installed NotepadPlusPlus successfully (exit code 0).
OSD Apps runtime completed successfully.
```

The next acceptance step is to execute the same staged package through the generated `SetupComplete.cmd` path, matching the intended OSDCloud v2 post-deployment workflow.
