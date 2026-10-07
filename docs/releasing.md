# Releasing OSDApps

OSDApps uses GitHub Actions for validation and PowerShell Gallery publishing.

## Continuous integration

Every push to `main`, pull request, or manual CI run validates:

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

## PowerShell Gallery publish flow

Publishing a GitHub Release triggers:

```text
checkout
→ install Pester + PSScriptAnalyzer
→ run all validation
→ build dist/OSDApps
→ compare release tag to ModuleVersion
→ Publish-Module to PSGallery
```

If validation fails, the package is not published.

The workflow can also be started manually with `workflow_dispatch`. Manual publishing still runs all tests and builds the module first, but there is no release-tag version check because no release event exists.

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

Only the dedicated `Publish PowerShell Gallery` workflow has a publishing step, and the API key is only exposed to that step through the GitHub Actions secret.
