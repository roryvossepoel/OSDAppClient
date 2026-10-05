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

PreInstall skips built-in refresh and installs from the previously staged payload.

## What happens if Office refresh hangs?

The Office refresh has a 20-minute timeout by default. After the timeout, PreInstall falls back to staged Office content and installation continues.

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

Use `-KeepSource` while troubleshooting.

## Does a failed installation remove the source?

No.

Runtime source is retained automatically on failure so the staged payload, manifest, and work directory remain available for investigation.
