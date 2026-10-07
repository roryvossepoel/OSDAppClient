# Validation matrix

This page tracks end-to-end deployment paths that have been exercised with OSDCloud v2.

| Scenario | Status | Expected source path |
| --- | --- | --- |
| Blank OSDCloud USB + online | Validated | Populate USB cache during SetupComplete, then install locally |
| Existing OSDCloud USB cache + online | Validated | Reuse/refresh USB cache, then install locally |
| Existing OSDCloud USB cache + offline | Next validation | Use staged/cached fallback without online refresh |
| No USB + online | Next validation | Acquire built-ins directly to Windows Temp |
| No USB + offline | Expected failure without staged fallback | PreInstall stops before Runner |

## Validated built-in applications

- Microsoft 365 Apps
- Microsoft Teams
- Adobe Acrobat Unified x64
- Google Chrome Enterprise x64
- Mozilla Firefox Enterprise Rapid x64

## Built-ins awaiting end-to-end validation

- Google Chrome Enterprise x86
- Mozilla Firefox Enterprise Rapid x86
- Mozilla Firefox Enterprise ESR x64/x86
- Adobe Acrobat Unified x86

## Success criteria

A built-in test is considered successful when:

1. WinPE stages the intended application metadata and any available fallback payload.
2. SetupComplete starts PreInstall in full Windows.
3. Source resolution selects USB cache or local acquisition as expected.
4. A complete payload exists under `%SystemRoot%\Temp\OSDApps` before installation.
5. The Runner completes each application with an accepted exit code.
6. `InstallComplete` is logged.
7. Runtime cleanup is scheduled after success.

Runtime evidence is written to:

```text
%ProgramData%\OSDApps\Logs\Runtime.log
```

WinPE/cache operations are logged to:

```text
<OSDCloud>:\OSDApps\Logs\Client.log
```

## Performance baselines

For performance validation, use the same application order for both runs and compare:

1. **Cold cache** — blank OSDCloud cache; all built-in content must be acquired.
2. **Warm cache** — reuse the populated cache from the cold-cache run.

Record at least:
- PreInstall duration;
- per-built-in acquisition/refresh duration;
- Runner duration;
- per-application installation duration;
- total SetupComplete duration.

For troubleshooting runs, use:

```powershell
Set-OSDAppConfiguration -CleanupMode Never
```

so the staged runtime, payloads, and `Work` directory remain available after success.
