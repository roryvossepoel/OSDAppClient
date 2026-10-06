function Add-OSDAppMicrosoft365AppsInternal {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$CachePath,
        [Parameter(Mandatory)][string]$WindowsPath,
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
        [bool]$UseCachedConfiguration = $true,
        [string]$OfficeDeploymentToolUri = 'https://officecdn.microsoft.com/pr/wsus/setup.exe',
        [string]$StagedRelativePath = 'Windows\Temp\OSDApps'
    )

    if ($SharedComputerLicensing -and $DeviceBasedLicensing) {
        throw 'SharedComputerLicensing and DeviceBasedLicensing cannot both be enabled.'
    }

    $destinationRoot = Join-Path $WindowsPath $StagedRelativePath
    $destinationBuiltIn = Join-Path $destinationRoot 'BuiltIn\Microsoft365Apps'
    $deviceManifestPath = Join-Path $destinationRoot 'DeviceManifest.json'
    $clientLogPath = if ($CachePath) { Join-Path $CachePath 'Logs\Client.log' } else { Join-Path $WindowsPath 'ProgramData\OSDApps\Logs\Client.log' }

    $cacheRoot = if ($CachePath) { Join-Path $CachePath 'BuiltIn\Microsoft365Apps' } else { $null }
    $cacheConfig = if ($cacheRoot) { Join-Path $cacheRoot 'configuration.xml' } else { $null }
    $cacheHasPayload = $false
    if ($cacheRoot) {
        $cacheHasPayload = (
            (Test-Path -LiteralPath (Join-Path $cacheRoot 'Office\Data') -PathType Container) -and
            (Test-Path -LiteralPath (Join-Path $cacheRoot 'setup.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath $cacheConfig -PathType Leaf)
        )
    }

    if (-not $PSCmdlet.ShouldProcess($destinationBuiltIn, 'Stage Microsoft 365 Apps deployment intent and available cache')) { return }

    if (Test-Path -LiteralPath $destinationBuiltIn) {
        Remove-Item -LiteralPath $destinationBuiltIn -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destinationBuiltIn -Force | Out-Null

    if ($cacheHasPayload) {
        Copy-Item -Path (Join-Path $cacheRoot '*') -Destination $destinationBuiltIn -Recurse -Force
    }

    $configPath = Join-Path $destinationBuiltIn 'configuration.xml'

    if ($ConfigurationXml) {
        if (-not (Test-Path -LiteralPath $ConfigurationXml -PathType Leaf)) {
            throw "Office configuration XML not found: $ConfigurationXml"
        }
        Copy-Item -LiteralPath $ConfigurationXml -Destination $configPath -Force
    }
    elseif ($UseCachedConfiguration -and $cacheHasPayload -and (Test-Path -LiteralPath $cacheConfig -PathType Leaf)) {
        Copy-Item -LiteralPath $cacheConfig -Destination $configPath -Force
    }
    else {
        if (-not $Language -or @($Language).Count -eq 0) { throw 'At least one Office language must be specified.' }
        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
        $writer = [System.Xml.XmlWriter]::Create($configPath, $settings)
        try {
            $writer.WriteStartDocument()
            $writer.WriteStartElement('Configuration')
            $writer.WriteStartElement('Add')
            $writer.WriteAttributeString('OfficeClientEdition', $Architecture)
            $writer.WriteAttributeString('Channel', $Channel)
            $writer.WriteStartElement('Product')
            $writer.WriteAttributeString('ID', $ProductId)
            foreach ($culture in $Language) {
                if ([string]::IsNullOrWhiteSpace($culture)) { continue }
                $writer.WriteStartElement('Language'); $writer.WriteAttributeString('ID', $culture); $writer.WriteEndElement()
            }
            foreach ($app in @($ExcludeApp)) {
                if ([string]::IsNullOrWhiteSpace($app)) { continue }
                $writer.WriteStartElement('ExcludeApp'); $writer.WriteAttributeString('ID', $app); $writer.WriteEndElement()
            }
            $writer.WriteEndElement()
            $writer.WriteEndElement()
            $writer.WriteStartElement('Display')
            $writer.WriteAttributeString('Level', 'None')
            $writer.WriteAttributeString('AcceptEULA', $(if ($AcceptEula) { 'TRUE' } else { 'FALSE' }))
            $writer.WriteEndElement()
            if ($SharedComputerLicensing) {
                $writer.WriteStartElement('Property'); $writer.WriteAttributeString('Name', 'SharedComputerLicensing'); $writer.WriteAttributeString('Value', '1'); $writer.WriteEndElement()
            }
            if ($DeviceBasedLicensing) {
                $writer.WriteStartElement('Property'); $writer.WriteAttributeString('Name', 'DeviceBasedLicensing'); $writer.WriteAttributeString('Value', '1'); $writer.WriteEndElement()
            }
            $writer.WriteStartElement('Updates'); $writer.WriteAttributeString('Enabled', 'TRUE'); $writer.WriteEndElement()
            $writer.WriteEndElement()
            $writer.WriteEndDocument()
        }
        finally { $writer.Dispose() }
    }

    if (Test-Path -LiteralPath $deviceManifestPath -PathType Leaf) {
        $deviceManifest = Get-Content -LiteralPath $deviceManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
        $deviceManifest = [pscustomobject]@{ SchemaVersion='1.0'; StagedAt=(Get-Date).ToUniversalTime().ToString('o'); Packages=@() }
    }

    $builtInApps = @()
    if ($deviceManifest.PSObject.Properties.Name -contains 'BuiltInApps') {
        $builtInApps = @($deviceManifest.BuiltInApps | Where-Object { $_.Id -ne 'Microsoft365Apps' })
    }

    $builtInApps += [pscustomobject]@{
        Id = 'Microsoft365Apps'
        DisplayName = 'Microsoft 365 Apps'
        Type = 'OfficeDeploymentTool'
        Configuration = 'BuiltIn\Microsoft365Apps\configuration.xml'
        Setup = 'BuiltIn\Microsoft365Apps\setup.exe'
        Offline = $true
        Architecture = $Architecture
        Channel = $Channel
        ProductId = $ProductId
        Language = @($Language)
        AcceptEula = $AcceptEula
        SharedComputerLicensing = $SharedComputerLicensing
        DeviceBasedLicensing = $DeviceBasedLicensing
        ExcludeApp = @($ExcludeApp)
        OfficeDeploymentToolUri = $OfficeDeploymentToolUri
        CachePreferred = [bool]$CachePath
    }

    if ($deviceManifest.PSObject.Properties.Name -contains 'BuiltInApps') {
        $deviceManifest.BuiltInApps = $builtInApps
    } else {
        $deviceManifest | Add-Member -NotePropertyName BuiltInApps -NotePropertyValue $builtInApps
    }
    $deviceManifest = Add-OSDAppInstallOrderEntry -Manifest $deviceManifest -Id 'Microsoft365Apps' -Source 'BuiltIn'
    $deviceManifest.StagedAt = (Get-Date).ToUniversalTime().ToString('o')
    $deviceManifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $deviceManifestPath -Encoding UTF8

    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'CacheDetection' -Message $(if ($CachePath) { 'OSDCloud USB cache detected.' } else { 'No OSDCloud USB cache detected. Direct local acquisition will be used during SetupComplete.' }) -Data @{ CachePath=$CachePath; CacheAvailable=$cacheHasPayload }
    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'StageTarget' -Message 'Microsoft 365 Apps deployment intent staged to the OS disk.' -Data @{ Destination=$destinationBuiltIn; AcquisitionPhase='SetupComplete'; CachePreferred=[bool]$CachePath }
    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'OfficeStageComplete' -Message 'Microsoft 365 Apps deployment intent staged.' -Data @{ Destination=$destinationBuiltIn; CacheAvailable=$cacheHasPayload; CachePath=$CachePath }

    [pscustomobject]@{
        PSTypeName='OSDAppClient.StagedApp'
        Name='Microsoft365Apps'
        CachePath=$CachePath
        WindowsPath=$WindowsPath
        StagedPath=$destinationBuiltIn
        Source='BuiltIn'
        CacheAvailable=$cacheHasPayload
    }
}