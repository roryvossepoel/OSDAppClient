function Add-OSDApp {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string[]]$Name,

        [ValidateSet('Current','MonthlyEnterprise','SemiAnnual','CurrentPreview','SemiAnnualPreview','BetaChannel')]
        [string]$OfficeChannel = 'Current',

        [ValidateSet('64','32')]
        [string]$OfficeArchitecture = '64',

        [ValidateSet('O365ProPlusRetail','O365BusinessRetail')]
        [string]$OfficeProductId = 'O365ProPlusRetail',

        [string[]]$OfficeLanguage = @('en-us'),

        [bool]$OfficeAcceptEula = $true,

        [bool]$OfficeSharedComputerLicensing = $false,

        [bool]$OfficeDeviceBasedLicensing = $false,

        [ValidateSet('Access','Excel','Groove','Lync','OneDrive','OneNote','Outlook','OutlookForWindows','PowerPoint','Publisher','Teams','Word')]
        [string[]]$OfficeExcludeApp,

        [string]$ConfigurationXml,

        [string]$OfficeDeploymentToolUri = 'https://officecdn.microsoft.com/pr/wsus/setup.exe',

        [bool]$TeamsInstallMeetingAddin = $false,

        [ValidateSet('Cached','Online')]
        [string]$BuiltInInstallMode = 'Cached',

        [double]$OfficeMinimumFreeSpaceGB = 8,

        [double]$TeamsMinimumFreeSpaceGB = 2,

        [string]$TeamsBootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204',

        [switch]$SkipCacheRefresh,

        [string]$WindowsPath
    )

    begin {
        $requestedApps = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($item in $Name) {
            if (-not [string]::IsNullOrWhiteSpace($item)) {
                $requestedApps.Add($item)
            }
        }
    }

    end {
        $uniqueApps = @($requestedApps | Select-Object -Unique)
        if ($uniqueApps.Count -eq 0) {
            throw 'No applications were supplied.'
        }

        $officeRequested = @($uniqueApps | Where-Object { $_ -ieq 'Microsoft365Apps' }).Count -gt 0

        $officeOverrideNames = @(
            'OfficeChannel',
            'OfficeArchitecture',
            'OfficeProductId',
            'OfficeLanguage',
            'OfficeAcceptEula',
            'OfficeSharedComputerLicensing',
            'OfficeDeviceBasedLicensing',
            'OfficeExcludeApp',
            'ConfigurationXml'
        )
        $officeConfigurationOverridden = @($officeOverrideNames | Where-Object { $PSBoundParameters.ContainsKey($_) }).Count -gt 0

        $teamsRequested = @($uniqueApps | Where-Object { $_ -ieq 'Teams' }).Count -gt 0
        $repositoryApps = @($uniqueApps | Where-Object { $_ -ine 'Microsoft365Apps' -and $_ -ine 'Teams' })

        $cachePath = Get-OSDAppCachePath

        if ($repositoryApps.Count -gt 0) {
            $cacheManifestPath = Join-Path $cachePath 'CacheManifest.json'
            if (-not (Test-Path -LiteralPath $cacheManifestPath -PathType Leaf)) {
                throw "OSD App cache manifest not found: $cacheManifestPath. Run Sync-OSDAppRepository first for repository-based applications."
            }
        }

        if ($PSBoundParameters.ContainsKey('WindowsPath')) {
            $windowsPath = [System.IO.Path]::GetFullPath($WindowsPath)

            if (-not (Test-Path -LiteralPath $windowsPath -PathType Container)) {
                throw "WindowsPath does not exist or is not a directory: $windowsPath"
            }
        }
        else {
            $windowsCandidates = @(
                Get-Volume -ErrorAction SilentlyContinue |
                    Where-Object { $_.DriveLetter -and $_.DriveLetter -ne 'X' } |
                    ForEach-Object {
                        $root = "$($_.DriveLetter):\"
                        $systemHive = Join-Path $root 'Windows\System32\Config\SYSTEM'

                        if (Test-Path -LiteralPath $systemHive -PathType Leaf) {
                            $root
                        }
                    }
            )

            if ($windowsCandidates.Count -eq 0) {
                throw 'No offline Windows installation was found.'
            }

            if ($windowsCandidates.Count -gt 1) {
                throw "Multiple Windows installations were found: $($windowsCandidates -join ', ')."
            }

            $windowsPath = $windowsCandidates[0]
        }

        if ($PSCmdlet.ShouldProcess(($uniqueApps -join ', '), "Stage applications for SetupComplete on $windowsPath")) {
            if ($repositoryApps.Count -gt 0) {
                Copy-OSDAppContent -Name $repositoryApps -CachePath $cachePath -WindowsPath $windowsPath | Out-Null
            }

            $useBuiltInCache = $BuiltInInstallMode -eq 'Cached'

            if ($useBuiltInCache -and ($officeRequested -or $teamsRequested)) {
                $builtInNames = @()
                if ($officeRequested) { $builtInNames += 'Microsoft365Apps' }
                if ($teamsRequested) { $builtInNames += 'Teams' }

                $clientLogPath = Join-Path $cachePath 'Logs\Client.log'
                $networkAvailable = [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()
                $isWinPE = Test-OSDAppWinPE

                if ($SkipCacheRefresh) {
                    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Stage' -Event 'BuiltInCacheRefreshSkipped' -Message 'Built-in cache refresh was skipped by request.' -Data @{ Names = $builtInNames; Reason = 'SkipCacheRefresh' }
                }
                elseif (-not $networkAvailable) {
                    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Stage' -Event 'BuiltInCacheRefreshSkipped' -Message 'No active network connection was detected. Existing built-in cache will be used without an online refresh attempt.' -Data @{ Names = $builtInNames; Reason = 'Offline' }
                }
                else {
                    if ($officeRequested) {
                        if ($isWinPE) {
                            Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'BuiltInCacheRefreshSkipped' -Message 'Microsoft 365 Apps cache refresh is skipped in WinPE. Existing cached Office content will be used.' -Data @{ Reason = 'WinPE'; Tool = 'OfficeDeploymentTool' }
                        }
                        else {
                            $officeSyncParameters = @{
                                Name                            = 'Microsoft365Apps'
                                OfficeChannel                   = $OfficeChannel
                                OfficeArchitecture              = $OfficeArchitecture
                                OfficeProductId                 = $OfficeProductId
                                OfficeLanguage                  = $OfficeLanguage
                                OfficeAcceptEula                = $OfficeAcceptEula
                                OfficeSharedComputerLicensing   = $OfficeSharedComputerLicensing
                                OfficeDeviceBasedLicensing      = $OfficeDeviceBasedLicensing
                                OfficeDeploymentToolUri         = $OfficeDeploymentToolUri
                                OfficeMinimumFreeSpaceGB        = $OfficeMinimumFreeSpaceGB
                                Confirm                         = $false
                            }

                            if ($OfficeExcludeApp) {
                                $officeSyncParameters.OfficeExcludeApp = $OfficeExcludeApp
                            }

                            if ($ConfigurationXml) {
                                $officeSyncParameters.ConfigurationXml = $ConfigurationXml
                            }

                            try {
                                Sync-OSDAppBuiltIn @officeSyncParameters | Out-Null
                            }
                            catch {
                                Write-Warning "Microsoft 365 Apps cache refresh failed. Existing cached payload will be used when available. $($_.Exception.Message)"
                            }
                        }
                    }

                    if ($teamsRequested) {
                        $teamsSyncParameters = @{
                            Name                     = 'Teams'
                            TeamsBootstrapperUri     = $TeamsBootstrapperUri
                            TeamsMinimumFreeSpaceGB  = $TeamsMinimumFreeSpaceGB
                            Confirm                  = $false
                        }

                        try {
                            Sync-OSDAppBuiltIn @teamsSyncParameters | Out-Null
                        }
                        catch {
                            Write-Warning "Microsoft Teams cache refresh failed. Existing cached payload will be used when available. $($_.Exception.Message)"
                        }
                    }
                }

                $missingBuiltInCache = [System.Collections.Generic.List[string]]::new()

                if ($officeRequested) {
                    $officeCacheRoot = Join-Path $cachePath 'BuiltIn\Microsoft365Apps'
                    if (
                        -not (Test-Path -LiteralPath (Join-Path $officeCacheRoot 'Office\Data') -PathType Container) -or
                        -not (Test-Path -LiteralPath (Join-Path $officeCacheRoot 'setup.exe') -PathType Leaf) -or
                        -not (Test-Path -LiteralPath (Join-Path $officeCacheRoot 'configuration.xml') -PathType Leaf)
                    ) {
                        $missingBuiltInCache.Add('Microsoft365Apps')
                    }
                }

                if ($teamsRequested) {
                    $teamsCacheRoot = Join-Path $cachePath 'BuiltIn\Teams'
                    if (
                        -not (Test-Path -LiteralPath (Join-Path $teamsCacheRoot 'teams.msix') -PathType Leaf) -or
                        -not (Test-Path -LiteralPath (Join-Path $teamsCacheRoot 'teamsbootstrapper.exe') -PathType Leaf)
                    ) {
                        $missingBuiltInCache.Add('Teams')
                    }
                }

                if ($missingBuiltInCache.Count -gt 0) {
                    throw "Required built-in cache is not available for: $($missingBuiltInCache -join ', '). Run Sync-OSDAppBuiltIn on a supported online Windows environment, or use -BuiltInInstallMode Online."
                }
            }

            if ($officeRequested) {
                $officeParameters = @{
                    CachePath               = $cachePath
                    WindowsPath             = $windowsPath
                    Channel                 = $OfficeChannel
                    Architecture            = $OfficeArchitecture
                    ProductId               = $OfficeProductId
                    Language                = $OfficeLanguage
                    AcceptEula              = $OfficeAcceptEula
                    SharedComputerLicensing = $OfficeSharedComputerLicensing
                    DeviceBasedLicensing    = $OfficeDeviceBasedLicensing
                    UseCachedConfiguration   = ($useBuiltInCache -and (-not $officeConfigurationOverridden))
                    UseCachedPayload         = $useBuiltInCache
                    OfficeDeploymentToolUri = $OfficeDeploymentToolUri
                    Confirm                 = $false
                }

                if ($OfficeExcludeApp) {
                    $officeParameters.ExcludeApp = $OfficeExcludeApp
                }

                if ($ConfigurationXml) {
                    $officeParameters.ConfigurationXml = $ConfigurationXml
                }

                Add-OSDAppMicrosoft365Apps @officeParameters | Out-Null
            }

            if ($teamsRequested) {
                Add-OSDAppTeams -CachePath $cachePath -WindowsPath $windowsPath -InstallMeetingAddin $TeamsInstallMeetingAddin -UseCachedPayload $useBuiltInCache -TeamsBootstrapperUri $TeamsBootstrapperUri -Confirm:$false | Out-Null
            }

            Add-OSDAppSetupComplete -WindowsPath $windowsPath | Out-Null
        }

        foreach ($app in $uniqueApps) {
            [pscustomobject]@{
                PSTypeName  = 'OSDAppClient.StagedApp'
                Name        = $app
                CachePath   = $cachePath
                WindowsPath = $windowsPath
                StagedPath  = Join-Path $windowsPath 'OSDApps'
                Source      = if ($app -ieq 'Microsoft365Apps' -or $app -ieq 'Teams') { 'BuiltIn' } else { 'Repository' }
            }
        }
    }
}
