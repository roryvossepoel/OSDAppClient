@{
    RootModule        = 'OSDApps.psm1'
    ModuleVersion     = '0.30.1'
    GUID              = 'efc06c0c-6a69-4c21-8f34-2f539a7d5409'
    Author            = 'Rory Vossepoel'
    Copyright         = '(c) 2026 Rory Vossepoel. Licensed under the MIT License.'
    Description       = 'PowerShell module for OSDCloud v2 application deployment with repository and vendor-native built-in apps, optional USB caching, pre-OOBE SetupComplete installation, and repository authoring/validation.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Set-OSDAppConfiguration',
        'Get-OSDAppConfiguration',
        'Get-OSDAppCatalog',
        'Get-OSDApp',
        'Get-OSDAppCache',
        'Sync-OSDAppRepository',
        'Sync-OSDAppMicrosoft365Apps',
        'Sync-OSDAppTeams',
        'Sync-OSDAppAdobeAcrobatUnified',
        'Sync-OSDAppGoogleChromeEnterprise',
        'Sync-OSDAppMozillaFirefoxEnterprise',
        'Clear-OSDAppCache',
        'Add-OSDApp',
        'Add-OSDAppMicrosoft365Apps',
        'Add-OSDAppTeams',
        'Add-OSDAppAdobeAcrobatUnified',
        'Add-OSDAppGoogleChromeEnterprise',
        'Add-OSDAppMozillaFirefoxEnterprise',
        'New-OSDAppRepository',
        'New-OSDAppPackage',
        'Add-OSDAppPackage',
        'Test-OSDAppPackage',
        'Test-OSDAppRepository'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags = @('PowerShell','OSDCloud','OSDCloudV2','WinPE','WindowsDeployment','ApplicationDeployment','AppDeployment','OOBE','Autopilot','SetupComplete','OfflineCache','ApplicationCache','ApplicationPackaging','Repository')
            ProjectUri = 'https://github.com/roryvossepoel/OSDApps'
            LicenseUri = 'https://github.com/roryvossepoel/OSDApps/blob/main/LICENSE'
            ReleaseNotes = '0.30.1: Fix Adobe Unified USB-cache staging to its architecture-specific manifest path and verify copied payload; validate custom Office XML syntax; add file-copy regression tests.'
            RequireLicenseAcceptance = $false
        }
    }
}
