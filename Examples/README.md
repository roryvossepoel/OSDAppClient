# Examples

This directory contains starting points for building an OSD Apps repository.

## Repository template

`Repository/catalog.json` is an empty valid repository catalog. Copy the directory or create the same structure with:

```powershell
New-OSDAppRepository -Path C:\OSDApps\Repository
```

## Package source template

`PackageSource/ExampleApp/Install.ps1` demonstrates the required package source layout:

```text
ExampleApp/
├── Install.ps1
└── <installer payload>
```

Build it into the required archive:

```powershell
New-OSDAppPackage `
    -Id ExampleApp `
    -Version 1.0.0 `
    -SourcePath .\Examples\PackageSource\ExampleApp `
    -OutputPath C:\OSDApps\Build\ExampleApp
```

Publish the package into a repository:

```powershell
Add-OSDAppPackage `
    -Id ExampleApp `
    -DisplayName 'Example App' `
    -Version 1.0.0 `
    -Architecture x64 `
    -PackagePath C:\OSDApps\Build\ExampleApp\Package.zip `
    -RepositoryPath C:\OSDApps\Repository
```

Validate before publishing the repository:

```powershell
Test-OSDAppRepository -RepositoryPath C:\OSDApps\Repository
```
