function Add-OSDAppMicrosoft365Apps {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [ValidateSet('Current','MonthlyEnterprise','SemiAnnual','CurrentPreview','SemiAnnualPreview','BetaChannel')]
        [string]$Channel = 'Current',
        [ValidateSet('64','32')][string]$Architecture = '64',
        [ValidateSet('O365ProPlusRetail','O365BusinessRetail')][string]$ProductId = 'O365ProPlusRetail',
        [string[]]$Language = @('en-us'),
        [bool]$AcceptEula = $true,
        [bool]$SharedComputerLicensing = $false,
        [bool]$DeviceBasedLicensing = $false,
        [ValidateSet('Access','Excel','Groove','Lync','OneDrive','OneNote','Outlook','OutlookForWindows','PowerPoint','Publisher','Teams','Word')]
        [string[]]$ExcludeApp,
        [string]$ConfigurationXml,
        [string]$OfficeDeploymentToolUri = 'https://officecdn.microsoft.com/pr/wsus/setup.exe',
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
    $configurationParameters = @('Channel','Architecture','ProductId','Language','AcceptEula','SharedComputerLicensing','DeviceBasedLicensing','ExcludeApp','ConfigurationXml')
    $configurationOverridden = @($configurationParameters | Where-Object { $PSBoundParameters.ContainsKey($_) }).Count -gt 0

    $params = @{
        CachePath=$cachePath; WindowsPath=$resolvedWindowsPath; Channel=$Channel; Architecture=$Architecture;
        ProductId=$ProductId; Language=$Language; AcceptEula=$AcceptEula;
        SharedComputerLicensing=$SharedComputerLicensing; DeviceBasedLicensing=$DeviceBasedLicensing;
        OfficeDeploymentToolUri=$OfficeDeploymentToolUri; UseCachedConfiguration=(-not $configurationOverridden); StagedRelativePath=$stagedRelativePath; Confirm=$false
    }
    if ($ExcludeApp) { $params.ExcludeApp = $ExcludeApp }
    if ($ConfigurationXml) { $params.ConfigurationXml = $ConfigurationXml }

    if ($cachePath) {
        $existingOfficeCache = (
            (Test-Path -LiteralPath (Join-Path $cachePath 'BuiltIn\Microsoft365Apps\Office\Data') -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $cachePath 'BuiltIn\Microsoft365Apps\setup.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $cachePath 'BuiltIn\Microsoft365Apps\configuration.xml') -PathType Leaf)
        )

        if ($existingOfficeCache) {
            Write-Verbose 'Existing Microsoft 365 Apps cache found. Cached payload will be staged as fallback and refreshed during SetupComplete.'
        }
        else {
            Write-Verbose 'No existing Microsoft 365 Apps cache was found. The cache will be created during SetupComplete.'
        }
    }

    Write-Verbose 'Staging Microsoft 365 Apps deployment intent to the OS disk...'
    $result = Add-OSDAppMicrosoft365AppsInternal @params

    $manifestPath = Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ($manifest.PSObject.Properties.Name -contains 'Runtime')) {
        $manifest | Add-Member -NotePropertyName Runtime -NotePropertyValue ([pscustomobject]@{ KeepSource=$false; LogPath='%ProgramData%\OSDApps\Logs\Install.log' })
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    }

    Add-OSDAppSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null
    Write-Verbose 'Device manifest updated and SetupComplete integration verified.'
    Write-Verbose ("Staging summary: Application=Microsoft365Apps; Windows={0}; USB cache={1}; Acquisition=SetupComplete" -f $resolvedWindowsPath, $(if ($cachePath) { $cachePath } else { 'Not available' }))

    if ($cachePath -and -not $script:OSDAppCacheMediaWarningShown) {
        Write-Warning 'OSDCloud cache media detected. Keep the USB device connected until OOBE is displayed.'
        $script:OSDAppCacheMediaWarningShown = $true
    }

    $result
}