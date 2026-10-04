function Sync-OSDAppBuiltIn {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Microsoft365Apps','Teams')]
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

        [ValidateSet('Auto','x86','x64','arm64')]
        [string]$TeamsArchitecture = 'Auto',

        [double]$OfficeMinimumFreeSpaceGB = 8,

        [double]$TeamsMinimumFreeSpaceGB = 2,

        [string]$TeamsBootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204'
    )

    $cachePath = Get-OSDAppCachePath
    $clientLogPath = Join-Path $cachePath 'Logs\Client.log'

    foreach ($appName in @($Name | Select-Object -Unique)) {
        switch ($appName) {
            'Microsoft365Apps' {
                $root = Join-Path $cachePath 'BuiltIn\Microsoft365Apps'
                $setupPath = Join-Path $root 'setup.exe'
                $configPath = Join-Path $root 'configuration.xml'
                $cacheInfoPath = Join-Path $root 'CacheInfo.json'

                New-Item -ItemType Directory -Path $root -Force | Out-Null

                if ($OfficeSharedComputerLicensing -and $OfficeDeviceBasedLicensing) {
                    throw 'OfficeSharedComputerLicensing and OfficeDeviceBasedLicensing cannot both be enabled.'
                }

                if ($PSCmdlet.ShouldProcess($root, 'Synchronize Microsoft 365 Apps built-in cache')) {
                    Assert-OSDAppCacheFreeSpace -CachePath $cachePath -MinimumFreeSpaceGB $OfficeMinimumFreeSpaceGB -Operation 'Microsoft 365 Apps cache synchronization' -LogPath $clientLogPath | Out-Null
                    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'BuiltInSyncStart' -Message 'Synchronizing Microsoft 365 Apps built-in cache.'

                    Save-OSDAppDownload -Uri $OfficeDeploymentToolUri -DestinationPath $setupPath -Activity 'Downloading Office Deployment Tool' | Out-Null

                    if ($ConfigurationXml) {
                        if (-not (Test-Path -LiteralPath $ConfigurationXml -PathType Leaf)) {
                            throw "Office configuration XML not found: $ConfigurationXml"
                        }
                        Copy-Item -LiteralPath $ConfigurationXml -Destination $configPath -Force
                    }
                    else {
                        if (-not $OfficeLanguage -or @($OfficeLanguage).Count -eq 0) {
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
                            $writer.WriteAttributeString('OfficeClientEdition', $OfficeArchitecture)
                            $writer.WriteAttributeString('Channel', $OfficeChannel)

                            $writer.WriteStartElement('Product')
                            $writer.WriteAttributeString('ID', $OfficeProductId)

                            foreach ($culture in $OfficeLanguage) {
                                if ([string]::IsNullOrWhiteSpace($culture)) { continue }
                                $writer.WriteStartElement('Language')
                                $writer.WriteAttributeString('ID', $culture)
                                $writer.WriteEndElement()
                            }

                            foreach ($excluded in @($OfficeExcludeApp)) {
                                if ([string]::IsNullOrWhiteSpace($excluded)) { continue }
                                $writer.WriteStartElement('ExcludeApp')
                                $writer.WriteAttributeString('ID', $excluded)
                                $writer.WriteEndElement()
                            }

                            $writer.WriteEndElement()
                            $writer.WriteEndElement()

                            $writer.WriteStartElement('Display')
                            $writer.WriteAttributeString('Level', 'None')
                            $writer.WriteAttributeString('AcceptEULA', $(if ($OfficeAcceptEula) { 'TRUE' } else { 'FALSE' }))
                            $writer.WriteEndElement()

                            if ($OfficeSharedComputerLicensing) {
                                $writer.WriteStartElement('Property')
                                $writer.WriteAttributeString('Name', 'SharedComputerLicensing')
                                $writer.WriteAttributeString('Value', '1')
                                $writer.WriteEndElement()
                            }

                            if ($OfficeDeviceBasedLicensing) {
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

                    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'OfficeCacheDownloadStart' -Message 'Running Office Deployment Tool in download mode.' -Data @{ Configuration = $configPath }

                    $process = Start-Process -FilePath $setupPath -ArgumentList @('/download', $configPath) -WorkingDirectory $root -PassThru
                    try {
                        while (-not $process.HasExited) {
                            $downloadedBytes = 0L
                            $officeRoot = Join-Path $root 'Office'
                            if (Test-Path -LiteralPath $officeRoot -PathType Container) {
                                $downloadedBytes = (
                                    Get-ChildItem -LiteralPath $officeRoot -File -Recurse -ErrorAction SilentlyContinue |
                                        Measure-Object -Property Length -Sum
                                ).Sum
                            }

                            $downloadedGB = [math]::Round(([double]$downloadedBytes / 1GB), 2)
                            Write-Progress -Activity 'Downloading Microsoft 365 Apps content' -Status "$downloadedGB GB cached" -PercentComplete -1
                            Start-Sleep -Seconds 2
                            $process.Refresh()
                        }
                    }
                    finally {
                        Write-Progress -Activity 'Downloading Microsoft 365 Apps content' -Completed
                    }

                    if ($process.ExitCode -ne 0) {
                        throw "Office Deployment Tool download failed with exit code $($process.ExitCode)."
                    }

                    $officeData = Join-Path $root 'Office\Data'
                    if (-not (Test-Path -LiteralPath $officeData -PathType Container)) {
                        throw "Office Deployment Tool completed but Office\Data was not found: $officeData"
                    }

                    $versionFolders = @(
                        Get-ChildItem -LiteralPath $officeData -Directory -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
                            ForEach-Object {
                                try {
                                    [pscustomobject]@{ Name = $_.Name; Version = [version]$_.Name }
                                }
                                catch { }
                            } |
                            Sort-Object Version -Descending
                    )

                    $resolvedVersion = if ($versionFolders.Count -gt 0) { $versionFolders[0].Name } else { 'Unknown' }

                    [ordered]@{
                        Id           = 'Microsoft365Apps'
                        Cached       = $true
                        Version      = $resolvedVersion
                        Architecture = $OfficeArchitecture
                        Channel      = $OfficeChannel
                        SyncedAt     = (Get-Date).ToUniversalTime().ToString('o')
                    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

                    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Microsoft365Apps' -Event 'BuiltInSyncComplete' -Message 'Microsoft 365 Apps built-in cache synchronized.' -Data @{ Version = $resolvedVersion; Path = $root }

                    [pscustomobject]@{
                        PSTypeName   = 'OSDAppClient.BuiltInCache'
                        Id           = 'Microsoft365Apps'
                        Version      = $resolvedVersion
                        Architecture = $OfficeArchitecture
                        CachePath    = $root
                        Cached       = $true
                    }
                }
            }

            'Teams' {
                $root = Join-Path $cachePath 'BuiltIn\Teams'
                $bootstrapperPath = Join-Path $root 'teamsbootstrapper.exe'
                $msixPath = Join-Path $root 'teams.msix'
                $cacheInfoPath = Join-Path $root 'CacheInfo.json'
                $tempMsix = Join-Path $root 'teams.download.msix'

                New-Item -ItemType Directory -Path $root -Force | Out-Null

                $resolvedArchitecture = $TeamsArchitecture
                if ($resolvedArchitecture -eq 'Auto') {
                    $processorArchitecture = $env:PROCESSOR_ARCHITECTURE
                    if ($processorArchitecture -eq 'ARM64') {
                        $resolvedArchitecture = 'arm64'
                    }
                    elseif ($processorArchitecture -eq 'x86') {
                        $resolvedArchitecture = 'x86'
                    }
                    else {
                        $resolvedArchitecture = 'x64'
                    }
                }

                $teamsMsixUri = switch ($resolvedArchitecture) {
                    'x86'   { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196060' }
                    'x64'   { 'https://go.microsoft.com/fwlink/?linkid=2196106' }
                    'arm64' { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196207' }
                }

                if ($PSCmdlet.ShouldProcess($root, "Synchronize Microsoft Teams built-in cache ($resolvedArchitecture)")) {
                    Assert-OSDAppCacheFreeSpace -CachePath $cachePath -MinimumFreeSpaceGB $TeamsMinimumFreeSpaceGB -Operation 'Microsoft Teams cache synchronization' -LogPath $clientLogPath | Out-Null
                    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Teams' -Event 'BuiltInSyncStart' -Message 'Synchronizing Microsoft Teams built-in cache.' -Data @{ Architecture = $resolvedArchitecture }

                    Write-Progress -Activity 'Synchronizing Microsoft Teams cache' -Status 'Checking current Microsoft package metadata...' -PercentComplete 5

                    $remoteMetadata = Get-OSDAppRemoteFileMetadata -Uri $teamsMsixUri

                    $previousCacheInfo = $null
                    if (Test-Path -LiteralPath $cacheInfoPath -PathType Leaf) {
                        try {
                            $previousCacheInfo = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        }
                        catch { }
                    }

                    $metadataMatches = $false
                    if ((Test-Path -LiteralPath $msixPath -PathType Leaf) -and $previousCacheInfo) {
                        if ($remoteMetadata.ETag -and $previousCacheInfo.RemoteETag) {
                            $metadataMatches = $remoteMetadata.ETag -eq $previousCacheInfo.RemoteETag
                        }
                        elseif ($remoteMetadata.LastModified -and $previousCacheInfo.RemoteLastModified -and
                                $remoteMetadata.ContentLength -and $previousCacheInfo.RemoteContentLength) {
                            $metadataMatches = (
                                $remoteMetadata.LastModified -eq $previousCacheInfo.RemoteLastModified -and
                                [int64]$remoteMetadata.ContentLength -eq [int64]$previousCacheInfo.RemoteContentLength
                            )
                        }
                    }

                    Write-Progress -Activity 'Synchronizing Microsoft Teams cache' -Status 'Downloading bootstrapper...' -PercentComplete 10
                    Save-OSDAppDownload -Uri $TeamsBootstrapperUri -DestinationPath $bootstrapperPath -Activity 'Downloading Microsoft Teams bootstrapper' | Out-Null

                    if ($metadataMatches) {
                        $resolvedVersion = [string]$previousCacheInfo.Version
                        $updated = $false
                        Write-Progress -Activity 'Synchronizing Microsoft Teams cache' -Status "Cached Teams $resolvedVersion is current. No MSIX download required." -PercentComplete 90
                    }
                    else {
                        Write-Progress -Activity 'Synchronizing Microsoft Teams cache' -Status 'Downloading Teams MSIX...' -PercentComplete 15
                        Save-OSDAppDownload -Uri $teamsMsixUri -DestinationPath $tempMsix -Activity "Downloading Microsoft Teams $resolvedArchitecture MSIX" | Out-Null

                        Write-Progress -Activity 'Synchronizing Microsoft Teams cache' -Status 'Reading MSIX package metadata...' -PercentComplete 85
                        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
                        $archive = [System.IO.Compression.ZipFile]::OpenRead($tempMsix)
                        try {
                            $manifestEntry = $archive.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' } | Select-Object -First 1
                            if (-not $manifestEntry) {
                                throw 'AppxManifest.xml was not found in the downloaded Teams MSIX.'
                            }

                            $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
                            try {
                                [xml]$appxManifest = $reader.ReadToEnd()
                            }
                            finally {
                                $reader.Dispose()
                            }

                            $resolvedVersion = [string]$appxManifest.Package.Identity.Version
                        }
                        finally {
                            $archive.Dispose()
                        }

                        Move-Item -LiteralPath $tempMsix -Destination $msixPath -Force
                        $updated = $true
                    }

                    Write-Progress -Activity 'Synchronizing Microsoft Teams cache' -Status 'Updating cache metadata...' -PercentComplete 95

                    [ordered]@{
                        Id                    = 'Teams'
                        Cached                = $true
                        Version               = $resolvedVersion
                        Architecture          = $resolvedArchitecture
                        RemoteETag            = $remoteMetadata.ETag
                        RemoteLastModified    = $remoteMetadata.LastModified
                        RemoteContentLength   = $remoteMetadata.ContentLength
                        RemoteFinalUri        = $remoteMetadata.FinalUri
                        SyncedAt              = (Get-Date).ToUniversalTime().ToString('o')
                    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

                    Write-OSDAppClientLog -LogPath $clientLogPath -Component 'Teams' -Event 'BuiltInSyncComplete' -Message 'Microsoft Teams built-in cache synchronized.' -Data @{ Version = $resolvedVersion; Architecture = $resolvedArchitecture; Updated = $updated; Path = $root }

                    Write-Progress -Activity 'Synchronizing Microsoft Teams cache' -Status 'Completed.' -PercentComplete 100
                    Start-Sleep -Milliseconds 350
                    Write-Progress -Activity 'Synchronizing Microsoft Teams cache' -Completed

                    [pscustomobject]@{
                        PSTypeName   = 'OSDAppClient.BuiltInCache'
                        Id           = 'Teams'
                        Version      = $resolvedVersion
                        Architecture = $resolvedArchitecture
                        CachePath    = $root
                        Cached       = $true
                        Updated      = $updated
                    }
                }
            }
        }
    }
}
