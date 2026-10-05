function Add-OSDAppTeams {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Auto','x86','x64','arm64')][string]$Architecture = 'Auto',
        [bool]$InstallMeetingAddin = $false,
        [string]$TeamsBootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204',
        [string]$WindowsPath
    )

    Write-Verbose 'Resolving offline Windows installation...'
    $resolvedWindowsPath = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    Write-Verbose ("Windows installation found at {0}" -f $resolvedWindowsPath)

    Write-Verbose "Looking for an OSD Apps cache volume with label 'OSDCloud'..."
    $cachePath = $null
    try {
        $cachePath = Get-OSDAppCachePath
        Write-Verbose ("OSDCloud cache volume found. Cache root: {0}" -f $cachePath)
    }
    catch {
        Write-Verbose 'No OSDCloud cache volume was found.'
        Write-Verbose 'Built-in content will be acquired directly to the OS disk during SetupComplete.'
    }

    $stagedRelativePath = 'Windows\Temp\OSDApps'

    if ($cachePath) {
        $existingTeamsCache = (
            (Test-Path -LiteralPath (Join-Path $cachePath 'BuiltIn\Teams\teams.msix') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $cachePath 'BuiltIn\Teams\teamsbootstrapper.exe') -PathType Leaf)
        )

        if ($existingTeamsCache) {
            Write-Verbose 'Existing Microsoft Teams cache found. Cached payload will be staged as fallback and refreshed during SetupComplete.'
        }
        else {
            Write-Verbose 'No existing Microsoft Teams cache was found. The cache will be created during SetupComplete.'
        }
    }

    Write-Verbose 'Staging Microsoft Teams deployment intent to the OS disk...'
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
    Write-Verbose 'Device manifest updated and SetupComplete integration verified.'
    Write-Verbose ("Staging summary: Application=Teams; Windows={0}; USB cache={1}; Acquisition=SetupComplete" -f $resolvedWindowsPath, $(if ($cachePath) { $cachePath } else { 'Not available' }))

    if ($cachePath -and -not $script:OSDAppCacheMediaWarningShown) {
        Write-Warning 'OSDCloud cache media detected. Keep the USB device connected until OOBE is displayed.'
        $script:OSDAppCacheMediaWarningShown = $true
    }

    $result
}