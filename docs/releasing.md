# Releasing OSDApps

OSDApps uses GitHub Actions for validation and PowerShell Gallery publishing.

## Continuous integration

Every push to `main`, pull request, or manually started CI run validates:

```text
module manifest
→ PSScriptAnalyzer
→ Pester
→ example repository metadata
→ distributable module build
```

The resulting module package is uploaded as a workflow artifact named `OSDApps`.

## Required GitHub secret

PowerShell Gallery publishing uses the repository secret:

```text
PSGALLERY_API_KEY
```

The value must be a valid PowerShell Gallery API key with permission to publish the `OSDApps` package.

## Release versioning

Before publishing a GitHub Release:

1. update `ModuleVersion` in `OSDApps.psd1`;
2. add the release notes to `CHANGELOG.md`;
3. ensure CI is green;
4. create a Git tag matching the module version.

Use a version tag such as:

```text
v0.29.1
```

The publish workflow removes the optional leading `v` and requires the remaining tag version to exactly match `ModuleVersion`.

For example:

```text
Git tag        v0.29.1
ModuleVersion  0.29.1
```

## Recommended release flow

OSDApps uses two separate manual workflows, matching the WindowsDeviceLink release model.

### 1. Create GitHub Release

Run **Create GitHub Release** from GitHub Actions.

Enter a version such as:

```text
0.29.1
```

or leave the field empty to use the current `ModuleVersion`.

This workflow:

```text
verifies main
→ validates ModuleVersion
→ checks existing tag/release
→ runs PSScriptAnalyzer + Pester
→ creates tag v<version>
→ creates GitHub Release
```

It does **not** publish to PowerShell Gallery.

### 2. Publish PowerShell Gallery

After the GitHub Release exists, run **Publish PowerShell Gallery** separately and enter the exact version, for example:

```text
0.29.1
```

This workflow:

```text
checks out immutable tag v<version>
→ verifies exact tag
→ runs validation again
→ builds dist/OSDApps
→ validates built module version
→ publishes to PowerShell Gallery
```

Keeping these actions separate makes the Gallery push an explicit decision and ensures PSGallery is always published from the immutable Git release tag.

## Local validation

The same validation used by CI can be run locally:

```powershell
./build/Test-Module.ps1
```

Requirements:

```powershell
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Install-Module PSScriptAnalyzer -Scope CurrentUser
```

Build the distributable module without publishing it:

```powershell
./build/Build-Module.ps1
```

The default output is:

```text
dist/OSDApps
```

That directory is the exact module directory supplied to `Publish-Module`.

## Safety

The CI workflow never publishes a package.

The PowerShell Gallery API key is only exposed to the publish job through the GitHub Actions secret. Normal CI never has access to the Gallery publishing step.
