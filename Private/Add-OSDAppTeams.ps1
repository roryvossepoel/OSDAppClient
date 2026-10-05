function Add-OSDAppTeamsInternal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$CachePath,
        [Parameter(Mandatory)][string]$WindowsPath,
        [ValidateSet('Auto','x86','x64','arm64')][string]$Architecture = 'Auto',
        [bool]$InstallMeetingAddin = $false,
        [string]$TeamsBootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204',
        [string]$StagedRelativePath = 'Windows\Temp\OSDApps'
    )

    $destinationRoot = Join-Path $WindowsPath $StagedRelativePath
    $destinationBuiltIn = Join-Path $destinationRoot 'BuiltIn\Teams'
    $deviceManifestPath = Join-Path $destinationRoot 'DeviceManifest.json'
    $clientLogPath = if ($CachePath) { Join-Path $CachePath 'Logs\Client.log' } else { Join-Path $WindowsPath 'ProgramData\OSDApps\Logs\Client.log' }

    $resolvedArchitecture = $Architecture
    if ($resolvedArchitecture -eq 'Auto') {
        if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $resolvedArchitecture = 'arm64' }
        elseif ($env:PROCESSOR_ARCHITECTURE -eq 'x86') { $resolvedArchitecture = 'x86' }
        else { $resolvedArchitecture = 'x64' }
    }

    $msixUri = switch ($resolvedArchitecture) {
        'x86' { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196060' }
        'x64' { 'https://go.microsoft.com/fwlink/?linkid=2196106' }
        'arm64' { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196207' }
    }

    $cacheRoot = if ($CachePath) { Join-Path $CachePath 'BuiltIn\Teams' } else { $null }
    $cacheHasPayload = $false
    if ($cacheRoot) {
        $cacheHasPayload = (
            (Test-Path -LiteralPath (Join-Path $cacheRoot 'teams.msix') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $cacheRoot 'teamsbootstrapper.exe') -PathType Leaf)
        )
    }

    if (-not $PSCmdlet.ShouldProcess($destinationBuiltIn, 'Stage Microsoft Teams deployment intent and available cache')) { return }

    if (Test-Path -LiteralPath $destinationBuiltIn) {
        Remove-Item -LiteralPath $destinationBuiltIn -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destinationBuiltIn -Force | Out-Null

    if ($cacheHasPayload) {
        Copy-Item -LiteralPath (Join-Path $cacheRoot '*') -Destination $destinationBuiltIn -Recurse -Force
    }

    if (Test-Path -LiteralPath $deviceManifestPath -PathType Leaf) {
        $deviceManifest = Get-Content -LiteralPath $deviceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        $deviceManifest = [pscustomobject]@{ SchemaVersion='1.0'; StagedAt=(Get-Date).ToUniversalTime().ToString('o'); Packages=@() }
    }

    $builtInApps = @()
    if ($deviceManifest.PSObject.Properties.Name -contains 'BuiltInApps') {
        $builtInApps = @($deviceManifest.BuiltInApps | Where-Object { $_.Id -ne 'Teams' })
    }

    $builtInApps += [pscustomobject]@{
        Id = 'Teams'
        DisplayName = 'Microsoft Teams'
        Type = 'TeamsBootstrapper'
        Setup = 'BuiltIn\Teams\teamsbootstrapper.exe'
        OfflinePackage = 'BuiltIn\Teams\teams.msix'
        InstallMeetingAddin = $InstallMeetingAddin
        Architecture = $resolvedArchitecture
        BootstrapperUri = $TeamsBootstrapperUri
        MsixUri = $msixUri
        CachePreferred = [bool]$CachePath
    }

    if ($deviceManifest.PSObject.Properties.Name -contains 'BuiltInApps') {
        $deviceManifest.BuiltInApps = $builtInApps
    } else {
        $deviceManifest | Add-Member -NotePropertyName BuiltInApps -NotePropertyValue $builtInApps
    }
    $deviceManifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $deviceManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $deviceManifestPath -Encoding UTF8

    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Teams' -Event 'TeamsStageComplete' -Message 'Microsoft Teams deployment intent staged.' -Data @{ Destination=$destinationBuiltIn; CacheAvailable=$cacheHasPayload; CachePath=$CachePath; Architecture=$resolvedArchitecture }

    [pscustomobject]@{
        PSTypeName='OSDAppClient.StagedApp'
        Name='Teams'
        CachePath=$CachePath
        WindowsPath=$WindowsPath
        StagedPath=$destinationBuiltIn
        Source='BuiltIn'
        CacheAvailable=$cacheHasPayload
    }
}