# FAQ and troubleshooting

## Does OSDAppClient need to be installed in Windows?

No.

OSDAppClient is used for discovery, cache management, and staging. `Add-OSDApp` copies the standalone PreInstall and Runner scripts plus the manifest and required payloads into the offline Windows installation.

SetupComplete does not import the OSDAppClient module.

## Why does Microsoft 365 Apps not refresh in WinPE?

The Office Deployment Tool bootstrapper cannot run in the x64 WinPE environment used during OSD Apps testing because required x86 Windows runtime / side-by-side components are not available there.

Built-in Office refresh therefore runs in full Windows.

## Teams sync works in WinPE. Why is it also deferred?

Consistency.

Teams can technically synchronize in WinPE, but all built-ins intentionally share one full-Windows refresh lifecycle. That keeps update, fallback, logging, and troubleshooting behavior predictable.

## What if I need Office or Teams fully managed in WinPE?

Package them as normal repository applications.

Repository acquisition does not depend on a vendor bootstrapper and is designed to run in WinPE.

## What happens if the USB is removed too early?

If cache functionality is being used, removing the `OSDCloud` USB early prevents the full-Windows built-in refresh from checking and updating that cache. OSD Apps itself does not require USB media; without an `OSDCloud` USB cache, content can be acquired directly to the local Windows runtime when online.

Keep the USB connected until OOBE is displayed.

## What happens if there is no network?

If a complete staged or OSDCloud USB-cached payload is available, PreInstall uses it and installation continues.

If there is no usable local or USB-cached payload, PreInstall exits with an error before the runner starts.

## What happens if Office refresh hangs?

The Office refresh has a 20-minute timeout by default. After the timeout, PreInstall falls back to a complete staged or USB-cached Office payload when one exists. If no usable fallback exists, PreInstall exits with an error before the runner starts.

## Where are the logs?

WinPE / client:

```text
<OSDCloud USB>\OSDApps\Logs\Client.log
```

Installed Windows:

```text
%ProgramData%\OSDApps\Logs\Install.log
```

## Why did my runtime source disappear?

That is the default behavior after a successful run.

Temporary source is stored under:

```text
%SystemRoot%\Temp\OSDApps
```

and is removed after successful installation.

On failure, source is retained automatically for troubleshooting.

## Does a failed installation remove the source?

No.

Runtime source is retained automatically on failure so the staged payload, manifest, and work directory remain available for investigation.


## Do built-in apps require an OSDCloud USB stick?

No. `Add-OSDAppMicrosoft365Apps` and `Add-OSDAppTeams` can stage deployment intent without USB media. During SetupComplete, PreInstall downloads the required content directly to the local Windows runtime when online.

If a USB volume labeled `OSDCloud` is connected, OSD Apps automatically uses it as the cache source and destination and updates it during the built-in refresh phase.

## What does a blank OSDCloud USB stick need?

Only the volume label `OSDCloud` is required for built-in cache use. The `OSDApps` directory and built-in cache structure can be created automatically during the full-Windows pre-install phase.


## How do I see which source path was selected?

Use the built-in Add cmdlets with `-Verbose`:

```powershell
Add-OSDAppMicrosoft365Apps -Verbose
Add-OSDAppTeams -Verbose
```

The output shows whether an `OSDCloud` cache volume was detected, whether a usable cache already exists, the offline Windows target and whether content will be acquired through the USB cache or directly to the OS disk.

The same decisions are logged for later troubleshooting.

## Can the OSDCloud USB be completely blank?

Yes. This flow has been validated end to end.

For built-in caching, only the volume label `OSDCloud` is required. The `OSDApps` directory does not need to exist beforehand. During SetupComplete, OSD Apps creates the required structure, populates the Microsoft 365 Apps and Teams caches, stages the payload locally, installs both applications, and cleans up the temporary runtime after success.
