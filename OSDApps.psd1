@{
    RootModule        = 'OSDApps.psm1'
    ModuleVersion     = '0.29.0'
    GUID              = 'efc06c0c-6a69-4c21-8f34-2f539a7d5409'
    Author            = 'Rory Vossepoel'
    Description       = 'PowerShell module for OSDCloud v2 application deployment, caching, standalone SetupComplete runtime, and lightweight OSD Apps repository authoring and validation.'
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
            Tags = @('PowerShell','OSDCloud','OSDCloudV2','WindowsDeployment','OOBE','SetupComplete','ApplicationPackaging','Repository')
            ProjectUri = 'https://github.com/roryvossepoel/OSDApps'
        }
    }
}
