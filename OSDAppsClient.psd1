@{
    RootModule        = 'OSDAppsClient.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'efc06c0c-6a69-4c21-8f34-2f539a7d5409'
    Author            = 'Rory Vossepoel'
    Description       = 'WinPE PowerShell module for consuming OSD Apps repositories after OSDCloud v2 and preparing pre-OOBE application installation.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-OSDApp',
        'Sync-OSDAppCache',
        'Test-OSDAppCache',
        'Copy-OSDAppContent',
        'Add-OSDAppSetupComplete',
        'Install-OSDApp'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags = @('PowerShell','WinPE','OSDCloud','OSDCloudV2','WindowsDeployment','OOBE','SetupComplete')
            ProjectUri = 'https://github.com/roryvossepoel/OSDAppsClient'
        }
    }
}
