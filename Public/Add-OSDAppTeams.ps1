function Add-OSDAppTeams {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Auto','x86','x64','arm64')][string]$Architecture = 'Auto',
        [bool]$InstallMeetingAddin = $false,
        [string]$TeamsBootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204',
        [string]$WindowsPath
    )

    $resolvedWindowsPath = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $cachePath = $null
    try { $cachePath = Get-OSDAppCachePath } catch { }
    $stagedRelativePath = 'Windows\Temp\OSDApps'

    $result = Add-OSDAppTeamsInternal `
        -CachePath $cachePath `
        -WindowsPath $resolvedWindowsPath `
        -Architecture $Architecture `
        -InstallMeetingAddin $InstallMeetingAddin `
        -TeamsBootstrapperUri $TeamsBootstrapperUri `
        -StagedRelativePath $stagedRelativePath `
        -Confirm:$false

    $manifestPath = Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ($manifest.PSObject.Properties.Name -contains 'Runtime')) {
        $manifest | Add-Member -NotePropertyName Runtime -NotePropertyValue ([pscustomobject]@{ KeepSource=$false; LogPath='%ProgramData%\OSDApps\Logs\Install.log' })
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    }

    Add-OSDAppSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null
    $result
}