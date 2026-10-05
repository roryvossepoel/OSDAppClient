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

    $resolvedWindowsPath = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $cachePath = $null
    try { $cachePath = Get-OSDAppCachePath } catch { }
    $stagedRelativePath = 'Windows\Temp\OSDApps'

    $params = @{
        CachePath=$cachePath; WindowsPath=$resolvedWindowsPath; Channel=$Channel; Architecture=$Architecture;
        ProductId=$ProductId; Language=$Language; AcceptEula=$AcceptEula;
        SharedComputerLicensing=$SharedComputerLicensing; DeviceBasedLicensing=$DeviceBasedLicensing;
        OfficeDeploymentToolUri=$OfficeDeploymentToolUri; StagedRelativePath=$stagedRelativePath; Confirm=$false
    }
    if ($ExcludeApp) { $params.ExcludeApp = $ExcludeApp }
    if ($ConfigurationXml) { $params.ConfigurationXml = $ConfigurationXml }

    $result = Add-OSDAppMicrosoft365AppsInternal @params

    $manifestPath = Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not ($manifest.PSObject.Properties.Name -contains 'Runtime')) {
        $manifest | Add-Member -NotePropertyName Runtime -NotePropertyValue ([pscustomobject]@{ KeepSource=$false; LogPath='%ProgramData%\OSDApps\Logs\Install.log' })
        $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    }

    Add-OSDAppSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null
    $result
}