@{
    RootModule        = 'OSDAppClient.psm1'
    ModuleVersion     = '0.24.3'
    GUID              = 'efc06c0c-6a69-4c21-8f34-2f539a7d5409'
    Author            = 'Rory Vossepoel'
    Description       = 'Application acquisition, caching, staging, and pre-OOBE installation for OSDCloud v2, with optional OSDCloud USB caching and standalone SetupComplete runtime.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Set-OSDAppCatalog',
        'Get-OSDAppCatalog',
        'Get-OSDApp',
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
        'Add-OSDAppMozillaFirefoxEnterprise'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags = @('PowerShell','WinPE','OSDCloud','OSDCloudV2','WindowsDeployment','OOBE','SetupComplete')
            ProjectUri = 'https://github.com/roryvossepoel/OSDAppClient'
        }
    }
}
