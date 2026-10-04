function Add-OSDAppMicrosoft365Apps {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$CachePath,

        [Parameter(Mandatory)]
        [string]$WindowsPath,

        [ValidateSet('Current','MonthlyEnterprise','SemiAnnual','CurrentPreview','SemiAnnualPreview','BetaChannel')]
        [string]$Channel = 'Current',

        [ValidateSet('64','32')]
        [string]$Architecture = '64',

        [ValidateSet('O365ProPlusRetail','O365BusinessRetail')]
        [string]$ProductId = 'O365ProPlusRetail',

        [string[]]$Language = @('en-us'),

        [bool]$AcceptEula = $true,

        [bool]$SharedComputerLicensing = $false,

        [bool]$DeviceBasedLicensing = $false,

        [ValidateSet('Access','Excel','Groove','Lync','OneDrive','OneNote','Outlook','OutlookForWindows','PowerPoint','Publisher','Teams','Word')]
        [string[]]$ExcludeApp,

        [string]$ConfigurationXml,

        [bool]$UseCachedConfiguration = $false,

        [bool]$UseCachedPayload = $true,

        [string]$OfficeDeploymentToolUri = 'https://officecdn.microsoft.com/pr/wsus/setup.exe',

        [string]$StagedRelativePath = 'Windows\Temp\OSDApps'
    )

    $builtInRoot = Join-Path $CachePath 'BuiltIn\Microsoft365Apps'
    $setupPath = Join-Path $builtInRoot 'setup.exe'
    $configPath = Join-Path $builtInRoot 'configuration.xml'
    $clientLogPath = Join-Path $CachePath 'Logs\Client.log'

    New-Item -ItemType Directory -Path $builtInRoot -Force | Out-Null

    if (-not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
        Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'ODTAcquireStart' -Message 'Downloading Office Deployment Tool bootstrapper for SetupComplete.' -Data @{ Uri = $OfficeDeploymentToolUri }
        Invoke-WebRequest -Uri $OfficeDeploymentToolUri -OutFile $setupPath -UseBasicParsing -ErrorAction Stop
        Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'ODTAcquireComplete' -Message 'Office Deployment Tool bootstrapper acquired.' -Data @{ Path = $setupPath }
    }

    $officeDataCached = Test-Path -LiteralPath (Join-Path $builtInRoot 'Office\Data') -PathType Container

    if ($UseCachedConfiguration -and $officeDataCached -and (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'CachedConfigurationSelected' -Message 'Using the Office configuration stored with the built-in cache.'
    }
    elseif ($ConfigurationXml) {
        if (-not (Test-Path -LiteralPath $ConfigurationXml -PathType Leaf)) {
            throw "Office configuration XML not found: $ConfigurationXml"
        }

        Copy-Item -LiteralPath $ConfigurationXml -Destination $configPath -Force
    }
    else {
        if (-not $Language -or @($Language).Count -eq 0) {
            throw 'At least one Office language must be specified.'
        }

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
                $writer.WriteStartElement('Language')
                $writer.WriteAttributeString('ID', $culture)
                $writer.WriteEndElement()
            }

            foreach ($app in @($ExcludeApp)) {
                if ([string]::IsNullOrWhiteSpace($app)) { continue }
                $writer.WriteStartElement('ExcludeApp')
                $writer.WriteAttributeString('ID', $app)
                $writer.WriteEndElement()
            }

            $writer.WriteEndElement()
            $writer.WriteEndElement()

            $writer.WriteStartElement('Display')
            $writer.WriteAttributeString('Level', 'None')
            $writer.WriteAttributeString('AcceptEULA', $(if ($AcceptEula) { 'TRUE' } else { 'FALSE' }))
            $writer.WriteEndElement()

            if ($SharedComputerLicensing) {
                $writer.WriteStartElement('Property')
                $writer.WriteAttributeString('Name', 'SharedComputerLicensing')
                $writer.WriteAttributeString('Value', '1')
                $writer.WriteEndElement()
            }

            if ($DeviceBasedLicensing) {
                $writer.WriteStartElement('Property')
                $writer.WriteAttributeString('Name', 'DeviceBasedLicensing')
                $writer.WriteAttributeString('Value', '1')
                $writer.WriteEndElement()
            }

            $writer.WriteStartElement('Updates')
            $writer.WriteAttributeString('Enabled', 'TRUE')
            $writer.WriteEndElement()

            $writer.WriteEndElement()
            $writer.WriteEndDocument()
        }
        finally {
            $writer.Dispose()
        }
    }

    $destinationRoot = Join-Path $WindowsPath $StagedRelativePath
    $destinationBuiltIn = Join-Path $destinationRoot 'BuiltIn\Microsoft365Apps'

    if ($PSCmdlet.ShouldProcess($destinationBuiltIn, 'Stage Microsoft 365 Apps for SetupComplete')) {
        New-Item -ItemType Directory -Path (Split-Path $destinationBuiltIn -Parent) -Force | Out-Null
        if (Test-Path -LiteralPath $destinationBuiltIn) {
            Remove-Item -LiteralPath $destinationBuiltIn -Recurse -Force
        }
        if ($UseCachedPayload) {
            Copy-Item -LiteralPath $builtInRoot -Destination $destinationBuiltIn -Recurse -Force
        }
        else {
            New-Item -ItemType Directory -Path $destinationBuiltIn -Force | Out-Null
            Copy-Item -LiteralPath $setupPath -Destination (Join-Path $destinationBuiltIn 'setup.exe') -Force
            Copy-Item -LiteralPath $configPath -Destination (Join-Path $destinationBuiltIn 'configuration.xml') -Force
        }

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
            $builtInApps = @($deviceManifest.BuiltInApps | Where-Object { $_.Id -ne 'Microsoft365Apps' })
        }

        $officePayloadCached = $UseCachedPayload -and (Test-Path -LiteralPath (Join-Path $builtInRoot 'Office\Data') -PathType Container)

        $builtInApps += [pscustomobject]@{
            Id            = 'Microsoft365Apps'
            DisplayName   = 'Microsoft 365 Apps'
            Type          = 'OfficeDeploymentTool'
            Configuration = 'BuiltIn\Microsoft365Apps\configuration.xml'
            Setup         = 'BuiltIn\Microsoft365Apps\setup.exe'
            Offline       = $officePayloadCached
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

        Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'OfficeStageComplete' -Message 'Microsoft 365 Apps staged for SetupComplete.' -Data @{ Destination = $destinationBuiltIn; Offline = $officePayloadCached }
    }

    [pscustomobject]@{
        PSTypeName   = 'OSDAppClient.StagedApp'
        Name         = 'Microsoft365Apps'
        CachePath    = $CachePath
        WindowsPath  = $WindowsPath
        StagedPath   = $destinationBuiltIn
        Source       = 'BuiltIn'
    }
}
