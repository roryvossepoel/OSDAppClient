function Add-OSDAppTeams {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Auto','x86','x64','arm64')][string]$Architecture = 'Auto',
        [bool]$InstallMeetingAddin = $false,
        [string]$TeamsBootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204',
        [string]$WindowsPath
    )

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Windows' -Message 'Resolving offline Windows installation' }
    $resolvedWindowsPath = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'Windows' -Message ("Windows installation found at {0}" -f $resolvedWindowsPath) }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Cache' -Message "Detecting configured cache volume" }
    $cachePath = $null
    try {
        $cachePath = Get-OSDAppCachePath
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'Cache' -Message ("OSDCloud cache found at {0}" -f $cachePath) }
    }
    catch {
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Cache' -Message 'No OSDCloud cache volume found' }
        if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Source' -Message 'Built-in content will be acquired directly to the OS disk during SetupComplete' }
    }

    $stagedRelativePath = 'Windows\Temp\OSDApps'

    if ($cachePath) {
        $existingTeamsCache = (
            (Test-Path -LiteralPath (Join-Path $cachePath 'BuiltIn\Teams\teams.msix') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $cachePath 'BuiltIn\Teams\teamsbootstrapper.exe') -PathType Leaf)
        )

        if ($existingTeamsCache) {
            if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'Teams' -Message 'Existing cache found; cached payload will be staged as fallback and refreshed during SetupComplete' }
        }
        else {
            if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Teams' -Message 'No existing cache found; cache will be created during SetupComplete' }
        }
    }

    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Teams' -Message 'Staging deployment intent to the OS disk' }
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
    $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
    $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Add-OSDAppSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Success -Component 'Teams' -Message 'Device manifest updated and SetupComplete integration verified' }
    if ($VerbosePreference -ne 'SilentlyContinue') { Write-OSDAppConsole -Level Info -Component 'Summary' -Message ("Application=Teams; Windows={0}; USB cache={1}; Acquisition=SetupComplete" -f $resolvedWindowsPath, $(if ($cachePath) { $cachePath } else { 'Not available' })) }

    if ($cachePath -and -not $script:OSDAppCacheMediaWarningShown) {
        Write-Warning 'OSDCloud cache media detected. Keep the USB device connected until OOBE is displayed.'
        $script:OSDAppCacheMediaWarningShown = $true
    }

    $result
}