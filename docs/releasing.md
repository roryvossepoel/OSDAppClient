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

## Release process

The version in `OSDApps.psd1` and the corresponding top-level section in `CHANGELOG.md` are prepared in a pull request. The release workflow reads the changelog section and uses it for the GitHub Release notes.

1. Update `ModuleVersion` and its `ReleaseNotes` field together with `CHANGELOG.md`.
2. Run and review CI on the pull request.
3. Merge into `main`. A change to `OSDApps.psd1` automatically starts **Create GitHub Release**.
4. The release workflow validates the current main commit, re-runs the test suite, and creates the immutable `v<version>` tag with version-specific release notes.
5. After successful release creation, the workflow automatically dispatches **Publish PowerShell Gallery**.
6. The publish workflow builds from the immutable tag, runs tests, publishes, downloads the Gallery package, and compares SHA256 hashes against all packaged release files.

Both workflows can also be dispatched manually when appropriate. A manually dispatched publish requires an already existing matching release tag. A Gallery version is immutable: never attempt to overwrite a published version. Pre-existing versions are treated as explicit conflicts, while a post-push 409 is reconciled only when the published files match the release.

A normal `main` push without an `OSDApps.psd1` change does not trigger a new release. Documentation-only or unreleased fixes remain pending until a later version bump.

## Release documentation checklist

- Update version, changelog, and manifest release notes before tagging
- Confirm release notes describe behavior changes and compatibility restrictions
- Confirm Pester and GitHub CI pass
- Verify GitHub Release notes and PowerShell Gallery publication
- Keep examples and public metadata aligned with the exported parameters

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
