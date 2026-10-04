$moduleRoot = $PSScriptRoot

foreach ($folder in @('Private','Public')) {
    $path = Join-Path $moduleRoot $folder
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
            . $_.FullName
        }
    }
}

Export-ModuleMember -Function @(
    'Set-OSDAppCatalog',
    'Get-OSDAppCatalog',
    'Get-OSDApp',
    'Sync-OSDAppRepository',
    'Sync-OSDAppBuiltIn',
    'Test-OSDAppCache',
    'Copy-OSDAppContent',
    'Add-OSDAppSetupComplete',
    'Add-OSDApp'
)
