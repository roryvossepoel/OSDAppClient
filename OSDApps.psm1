$moduleRoot = $PSScriptRoot

foreach ($folder in @('Private','Public')) {
    $path = Join-Path $moduleRoot $folder
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter '*.ps1' -File |
            Sort-Object Name |
            ForEach-Object { . $_.FullName }
    }
}

Export-ModuleMember -Function @(
    'Set-OSDAppConfiguration',
    'Get-OSDAppConfiguration',
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
    'Add-OSDAppMozillaFirefoxEnterprise',
    'New-OSDAppRepository',
    'New-OSDAppPackage',
    'Add-OSDAppPackage',
    'Test-OSDAppPackage',
    'Test-OSDAppRepository'
)
