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

        [string]$TeamsBootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204'
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
        $teamsRequested = @($uniqueApps | Where-Object { $_ -ieq 'Teams' }).Count -gt 0
        $repositoryApps = @($uniqueApps | Where-Object { $_ -ine 'Microsoft365Apps' -and $_ -ine 'Teams' })

        $cachePath = Get-OSDAppCachePath

        if ($repositoryApps.Count -gt 0) {
            $cacheManifestPath = Join-Path $cachePath 'CacheManifest.json'
            if (-not (Test-Path -LiteralPath $cacheManifestPath -PathType Leaf)) {
                throw "OSD App cache manifest not found: $cacheManifestPath. Run Sync-OSDAppRepository first for repository-based applications."
            }
        }

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

        if ($PSCmdlet.ShouldProcess(($uniqueApps -join ', '), "Stage applications for SetupComplete on $windowsPath")) {
            if ($repositoryApps.Count -gt 0) {
                Copy-OSDAppContent -Name $repositoryApps -CachePath $cachePath -WindowsPath $windowsPath | Out-Null
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
                Add-OSDAppTeams -CachePath $cachePath -WindowsPath $windowsPath -InstallMeetingAddin $TeamsInstallMeetingAddin -TeamsBootstrapperUri $TeamsBootstrapperUri -Confirm:$false | Out-Null
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
