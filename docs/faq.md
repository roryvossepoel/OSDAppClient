# FAQ and troubleshooting

## Does OSDApps need to be installed in Windows?

No.

OSDApps is used for discovery, cache management, and staging. `Add-OSDApp` copies the standalone PreInstall and Runner scripts plus the manifest and required payloads into the offline Windows installation.

SetupComplete does not import the OSDApps module.

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

No. `Add-OSDAppMicrosoft365Apps`, `Add-OSDAppTeams`, and `Add-OSDAppAdobeAcrobatUnified` can stage deployment intent without USB media. During SetupComplete, PreInstall downloads the required content directly to the local Windows runtime when online.

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


## What is the difference between catalog.json, CacheCatalog.json, and DeviceManifest.json?

`catalog.json` is the online repository source of truth.

`CacheCatalog.json` is the local OSDCloud USB snapshot written by repository synchronization.

`DeviceManifest.json` describes what the current device will install during SetupComplete.

The old `CacheManifest.json` filename is not used.


## Can I request another built-in application?

Yes, but built-ins are intentionally limited to broadly used applications with a stable vendor-native acquisition path.

The installer must be obtainable directly and reproducibly from the vendor without scraping pages, sniffing traffic, capturing temporary URLs, reusing session state, or bypassing CDN/anti-bot protections. A CDN itself is fine when the vendor publishes a stable supported URL or endpoint.

Customer-specific, niche, authenticated, or otherwise non-generic applications should use the repository model instead.

See [Requesting a new built-in application](built-in-apps.md#requesting-a-new-built-in-application).


## Does OSDApps distribute built-in installers?

No.

Built-in application payloads are never bundled with, mirrored by, or redistributed through OSDApps. Every built-in downloads its installation content directly from the software vendor when the cache is populated or refreshed.

An `OSDCloud` USB may cache that vendor content locally for reuse, offline deployment, bandwidth reduction, and faster installation, but OSDApps itself does not act as a software distribution source.

This restriction applies to built-ins only. Repository applications are controlled by the repository owner, who is responsible for package provenance, hosting, licensing, and redistribution rights.
