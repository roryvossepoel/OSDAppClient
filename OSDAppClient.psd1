@{
    RootModule        = 'OSDAppClient.psm1'
    ModuleVersion     = '0.18.2'
    GUID              = 'efc06c0c-6a69-4c21-8f34-2f539a7d5409'
    Author            = 'Rory Vossepoel'
    Description       = 'PowerShell module for OSDCloud v2 application caching and staging, with temporary runtime source, persistent logs, full-Windows refresh and pre-OOBE installation.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Set-OSDAppCatalog',
        'Get-OSDAppCatalog',
        'Get-OSDApp',
        'Sync-OSDAppRepository',
        'Sync-OSDAppMicrosoft365Apps',
        'Sync-OSDAppTeams',
        'Clear-OSDAppCache',
        'Test-OSDAppCache',
        'Copy-OSDAppContent',
        'Add-OSDAppSetupComplete',
        'Add-OSDApp',
        'Add-OSDAppMicrosoft365Apps',
        'Add-OSDAppTeams'
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
