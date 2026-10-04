function Add-OSDAppTeams {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [string]$WindowsPath,

        [bool]$InstallMeetingAddin = $false,

        [string]$TeamsBootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204'
    )

    $builtInRoot = Join-Path $CachePath 'BuiltIn\Teams'
    $bootstrapperPath = Join-Path $builtInRoot 'teamsbootstrapper.exe'
    $clientLogPath = Join-Path $CachePath 'Logs\Client.log'

    New-Item -ItemType Directory -Path $builtInRoot -Force | Out-Null

    if (-not (Test-Path -LiteralPath $bootstrapperPath -PathType Leaf)) {
        Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Teams' -Event 'BootstrapperAcquireStart' -Message 'Downloading the latest Microsoft Teams bootstrapper for SetupComplete.' -Data @{ Uri = $TeamsBootstrapperUri }
        Invoke-WebRequest -Uri $TeamsBootstrapperUri -OutFile $bootstrapperPath -UseBasicParsing -ErrorAction Stop
        Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Teams' -Event 'BootstrapperAcquireComplete' -Message 'Microsoft Teams bootstrapper acquired.' -Data @{ Path = $bootstrapperPath }
    }

    $destinationRoot = Join-Path $WindowsPath 'OSDApps'
    $destinationBuiltIn = Join-Path $destinationRoot 'BuiltIn\Teams'

    if ($PSCmdlet.ShouldProcess($destinationBuiltIn, 'Stage Microsoft Teams for SetupComplete')) {
        New-Item -ItemType Directory -Path (Split-Path $destinationBuiltIn -Parent) -Force | Out-Null

        if (Test-Path -LiteralPath $destinationBuiltIn) {
            Remove-Item -LiteralPath $destinationBuiltIn -Recurse -Force
        }

        Copy-Item -LiteralPath $builtInRoot -Destination $destinationBuiltIn -Recurse -Force

        $deviceManifestPath = Join-Path $destinationRoot 'DeviceManifest.json'
        if (Test-Path -LiteralPath $deviceManifestPath -PathType Leaf) {
            $deviceManifest = Get-Content -LiteralPath $deviceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        else {
            New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
            $deviceManifest = [pscustomobject]@{
                SchemaVersion = '1.0'
                StagedAt      = (Get-Date).ToUniversalTime().ToString('o')
                Packages      = @()
            }
        }

        $builtInApps = @()
        if ($deviceManifest.PSObject.Properties.Name -contains 'BuiltInApps') {
            $builtInApps = @($deviceManifest.BuiltInApps | Where-Object { $_.Id -ne 'Teams' })
        }

        $offlinePackage = $null
        $cachedMsixPath = Join-Path $builtInRoot 'teams.msix'
        if (Test-Path -LiteralPath $cachedMsixPath -PathType Leaf) {
            $offlinePackage = 'BuiltIn\Teams\teams.msix'
        }

        $builtInApps += [pscustomobject]@{
            Id                  = 'Teams'
            DisplayName         = 'Microsoft Teams'
            Type                = 'TeamsBootstrapper'
            Setup               = 'BuiltIn\Teams\teamsbootstrapper.exe'
            OfflinePackage      = $offlinePackage
            InstallMeetingAddin = $InstallMeetingAddin
        }

        if ($deviceManifest.PSObject.Properties.Name -contains 'BuiltInApps') {
            $deviceManifest.BuiltInApps = $builtInApps
        }
        else {
            $deviceManifest | Add-Member -NotePropertyName BuiltInApps -NotePropertyValue $builtInApps
        }

        $deviceManifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
        $deviceManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $deviceManifestPath -Encoding UTF8

        $moduleRoot = Split-Path $PSScriptRoot -Parent
        $runtimeSource = Join-Path $moduleRoot 'Runtime\Invoke-OSDAppRunner.ps1'
        Copy-Item -LiteralPath $runtimeSource -Destination (Join-Path $destinationRoot 'Invoke-OSDAppRunner.ps1') -Force

        Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Teams' -Event 'TeamsStageComplete' -Message 'Microsoft Teams staged for SetupComplete.' -Data @{ Destination = $destinationBuiltIn; InstallMeetingAddin = $InstallMeetingAddin; OfflinePackage = $offlinePackage }
    }

    [pscustomobject]@{
        PSTypeName  = 'OSDAppClient.StagedApp'
        Name        = 'Teams'
        CachePath   = $CachePath
        WindowsPath = $WindowsPath
        StagedPath  = $destinationBuiltIn
        Source      = 'BuiltIn'
    }
}
