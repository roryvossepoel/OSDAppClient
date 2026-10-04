[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$StagedPath,

    [string]$CacheVolumeLabel = 'OSDCloud'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
$manifestPath = Join-Path $StagedPath 'DeviceManifest.json'
$logDirectory = Join-Path $StagedPath 'Logs'
$logPath = Join-Path $logDirectory 'Install.log'

function Write-PreInstallLog {
    param(
        [Parameter(Mandatory)][string]$Event,
        [ValidateSet('Info','Warning','Error')][string]$Level = 'Info',
        [string]$Message,
        [hashtable]$Data
    )

    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

    $type = switch ($Level) {
        'Warning' { 2 }
        'Error'   { 3 }
        default   { 1 }
    }

    $details = @()
    if ($Data) {
        foreach ($key in @($Data.Keys | Sort-Object)) {
            $value = $Data[$key]
            if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                $value = @($value) -join ','
            }
            $details += ('{0}={1}' -f $key, $value)
        }
    }

    $logMessage = if ($Message) { "[$Event] $Message" } else { "[$Event]" }
    if ($details.Count -gt 0) {
        $logMessage += ' | ' + ($details -join '; ')
    }

    $logMessage = $logMessage -replace '\]LOG\]!>', ']LOG]! >'

    $now = (Get-Date).ToUniversalTime()
    $time = $now.ToString('HH:mm:ss.fff') + '+000'
    $date = $now.ToString('MM-dd-yyyy')
    $thread = [System.Threading.Thread]::CurrentThread.ManagedThreadId

    $line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="PreInstall" context="" type="{3}" thread="{4}" file="">' -f $logMessage, $time, $date, $type, $thread
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Test-InternetEndpoint {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [int]$TimeoutSec = 10
    )

    try {
        Invoke-WebRequest -Uri $Uri -Method Head -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Get-OfficeCacheVersion {
    param([Parameter(Mandatory)][string]$OfficeRoot)

    $dataPath = Join-Path $OfficeRoot 'Office\Data'
    if (-not (Test-Path -LiteralPath $dataPath -PathType Container)) {
        return $null
    }

    $versions = @(
        Get-ChildItem -LiteralPath $dataPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } |
            ForEach-Object {
                try {
                    [pscustomobject]@{
                        Name = $_.Name
                        Version = [version]$_.Name
                    }
                }
                catch { }
            } |
            Sort-Object Version -Descending
    )

    if ($versions.Count -gt 0) {
        return $versions[0].Name
    }

    return $null
}

function Get-TeamsPackageVersion {
    param([Parameter(Mandatory)][string]$Path)

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)

    try {
        $entry = $archive.Entries |
            Where-Object { $_.FullName -eq 'AppxManifest.xml' } |
            Select-Object -First 1

        if (-not $entry) {
            throw 'AppxManifest.xml was not found in the Teams MSIX.'
        }

        $reader = New-Object System.IO.StreamReader($entry.Open())
        try {
            [xml]$manifest = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }

        return [string]$manifest.Package.Identity.Version
    }
    finally {
        $archive.Dispose()
    }
}

function Get-RemoteMetadata {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [int]$TimeoutSec = 15
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $true
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSec)

    try {
        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Head, $Uri)
        $response = $client.SendAsync($request).GetAwaiter().GetResult()

        try {
            $response.EnsureSuccessStatusCode() | Out-Null

            [pscustomobject]@{
                ETag          = if ($response.Headers.ETag) { [string]$response.Headers.ETag.Tag } else { $null }
                LastModified  = if ($response.Content.Headers.LastModified) { $response.Content.Headers.LastModified.UtcDateTime.ToString('o') } else { $null }
                ContentLength = if ($response.Content.Headers.ContentLength) { [int64]$response.Content.Headers.ContentLength } else { $null }
                FinalUri      = [string]$response.RequestMessage.RequestUri.AbsoluteUri
            }
        }
        finally {
            $response.Dispose()
            $request.Dispose()
        }
    }
    finally {
        $client.Dispose()
        $handler.Dispose()
    }
}

function Copy-DirectoryReplace {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $parent = Split-Path $Destination -Parent
    New-Item -ItemType Directory -Path $parent -Force | Out-Null

    $temp = "$Destination.refresh"
    if (Test-Path -LiteralPath $temp) {
        Remove-Item -LiteralPath $temp -Recurse -Force
    }

    Copy-Item -LiteralPath $Source -Destination $temp -Recurse -Force

    if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }

    Move-Item -LiteralPath $temp -Destination $Destination -Force
}

try {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        Write-PreInstallLog -Event 'RefreshSkipped' -Level 'Warning' -Message 'Device manifest was not found. Built-in refresh was skipped.' -Data @{ Manifest = $manifestPath }
        exit 0
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builtInApps = @()
    if ($manifest.PSObject.Properties.Name -contains 'BuiltInApps') {
        $builtInApps = @($manifest.BuiltInApps)
    }

    if ($builtInApps.Count -eq 0) {
        Write-PreInstallLog -Event 'RefreshSkipped' -Message 'No built-in applications are staged. Nothing to refresh.'
        exit 0
    }

    Write-PreInstallLog -Event 'RefreshStart' -Message 'Starting built-in application cache refresh before installation.' -Data @{ StagedPath = $StagedPath; BuiltInApps = @($builtInApps.Id) }

    $cacheVolume = Get-Volume -ErrorAction SilentlyContinue |
        Where-Object { $_.FileSystemLabel -eq $CacheVolumeLabel -and $_.DriveLetter } |
        Select-Object -First 1

    if (-not $cacheVolume) {
        Write-PreInstallLog -Event 'RefreshSkipped' -Level 'Warning' -Message 'OSDCloud cache volume is not available. Existing staged built-in payloads will be used.' -Data @{ VolumeLabel = $CacheVolumeLabel }
        exit 0
    }

    $usbRoot = "$($cacheVolume.DriveLetter):\OSDApps"
    Write-PreInstallLog -Event 'CacheVolumeFound' -Message 'OSDCloud cache volume found.' -Data @{ CacheRoot = $usbRoot }

    if (-not [System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()) {
        Write-PreInstallLog -Event 'RefreshSkipped' -Level 'Warning' -Message 'No active network connection was detected. Existing staged built-in payloads will be used.'
        exit 0
    }

    foreach ($app in $builtInApps) {
        switch ($app.Id) {
            'Microsoft365Apps' {
                if ($app.Offline -ne $true) {
                    Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Message 'Microsoft 365 Apps is staged in online mode. USB cache refresh is not required.' -Data @{ Id = 'Microsoft365Apps'; Reason = 'OnlineMode' }
                    continue
                }

                $usbOfficeRoot = Join-Path $usbRoot 'BuiltIn\Microsoft365Apps'
                $localOfficeRoot = Join-Path $StagedPath 'BuiltIn\Microsoft365Apps'
                $setupPath = Join-Path $usbOfficeRoot 'setup.exe'
                $configurationPath = Join-Path $usbOfficeRoot 'configuration.xml'
                $cacheInfoPath = Join-Path $usbOfficeRoot 'CacheInfo.json'

                if (
                    -not (Test-Path -LiteralPath $setupPath -PathType Leaf) -or
                    -not (Test-Path -LiteralPath $configurationPath -PathType Leaf) -or
                    -not (Test-Path -LiteralPath (Join-Path $usbOfficeRoot 'Office\Data') -PathType Container)
                ) {
                    Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Level 'Warning' -Message 'Microsoft 365 Apps USB cache is incomplete. Existing staged payload will be used.' -Data @{ Id = 'Microsoft365Apps'; CachePath = $usbOfficeRoot }
                    continue
                }

                if (-not (Test-InternetEndpoint -Uri 'https://officecdn.microsoft.com/pr/wsus/setup.exe')) {
                    Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Level 'Warning' -Message 'Microsoft 365 Apps CDN is not reachable. Existing staged payload will be used.' -Data @{ Id = 'Microsoft365Apps' }
                    continue
                }

                try {
                    $previousVersion = Get-OfficeCacheVersion -OfficeRoot $usbOfficeRoot
                    Write-PreInstallLog -Event 'BuiltInRefreshStart' -Message 'Refreshing Microsoft 365 Apps cache with Office Deployment Tool.' -Data @{ Id = 'Microsoft365Apps'; PreviousVersion = $previousVersion }

                    $process = Start-Process -FilePath $setupPath -ArgumentList @('/download', $configurationPath) -WorkingDirectory $usbOfficeRoot -Wait -PassThru
                    if ($process.ExitCode -ne 0) {
                        throw "Office Deployment Tool exited with code $($process.ExitCode)."
                    }

                    $currentVersion = Get-OfficeCacheVersion -OfficeRoot $usbOfficeRoot
                    if (-not $currentVersion) {
                        throw 'Office cache refresh completed but no Office version folder could be resolved.'
                    }

                    $oldCacheInfo = $null
                    if (Test-Path -LiteralPath $cacheInfoPath -PathType Leaf) {
                        try {
                            $oldCacheInfo = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        }
                        catch { }
                    }

                    [ordered]@{
                        Id           = 'Microsoft365Apps'
                        Cached       = $true
                        Version      = $currentVersion
                        Architecture = if ($oldCacheInfo -and $oldCacheInfo.Architecture) { [string]$oldCacheInfo.Architecture } else { '64' }
                        Channel      = if ($oldCacheInfo -and $oldCacheInfo.Channel) { [string]$oldCacheInfo.Channel } else { 'Current' }
                        SyncedAt     = (Get-Date).ToUniversalTime().ToString('o')
                    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

                    $localVersion = Get-OfficeCacheVersion -OfficeRoot $localOfficeRoot
                    $updated = ($currentVersion -ne $localVersion)

                    Copy-Item -LiteralPath $setupPath -Destination (Join-Path $localOfficeRoot 'setup.exe') -Force
                    Copy-Item -LiteralPath $configurationPath -Destination (Join-Path $localOfficeRoot 'configuration.xml') -Force
                    Copy-Item -LiteralPath $cacheInfoPath -Destination (Join-Path $localOfficeRoot 'CacheInfo.json') -Force

                    if ($updated -or -not (Test-Path -LiteralPath (Join-Path $localOfficeRoot 'Office\Data') -PathType Container)) {
                        $usbOfficePayload = Join-Path $usbOfficeRoot 'Office'
                        $localOfficePayload = Join-Path $localOfficeRoot 'Office'
                        Copy-DirectoryReplace -Source $usbOfficePayload -Destination $localOfficePayload
                    }

                    Write-PreInstallLog -Event 'BuiltInRefreshComplete' -Message 'Microsoft 365 Apps cache refresh completed.' -Data @{ Id = 'Microsoft365Apps'; Version = $currentVersion; UpdatedLocalPayload = $updated }
                }
                catch {
                    Write-PreInstallLog -Event 'BuiltInRefreshFailed' -Level 'Warning' -Message $_.Exception.Message -Data @{ Id = 'Microsoft365Apps'; Fallback = 'ExistingStagedPayload' }
                }
            }

            'Teams' {
                if (-not $app.OfflinePackage) {
                    Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Message 'Microsoft Teams is staged in online mode. USB cache refresh is not required.' -Data @{ Id = 'Teams'; Reason = 'OnlineMode' }
                    continue
                }

                $usbTeamsRoot = Join-Path $usbRoot 'BuiltIn\Teams'
                $localTeamsRoot = Join-Path $StagedPath 'BuiltIn\Teams'
                $usbMsixPath = Join-Path $usbTeamsRoot 'teams.msix'
                $usbBootstrapperPath = Join-Path $usbTeamsRoot 'teamsbootstrapper.exe'
                $cacheInfoPath = Join-Path $usbTeamsRoot 'CacheInfo.json'

                if (
                    -not (Test-Path -LiteralPath $usbMsixPath -PathType Leaf) -or
                    -not (Test-Path -LiteralPath $usbBootstrapperPath -PathType Leaf)
                ) {
                    Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Level 'Warning' -Message 'Microsoft Teams USB cache is incomplete. Existing staged payload will be used.' -Data @{ Id = 'Teams'; CachePath = $usbTeamsRoot }
                    continue
                }

                try {
                    $cacheInfo = $null
                    if (Test-Path -LiteralPath $cacheInfoPath -PathType Leaf) {
                        try {
                            $cacheInfo = Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json
                        }
                        catch { }
                    }

                    $architecture = if ($cacheInfo -and $cacheInfo.Architecture) {
                        [string]$cacheInfo.Architecture
                    }
                    elseif ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
                        'arm64'
                    }
                    elseif ($env:PROCESSOR_ARCHITECTURE -eq 'x86') {
                        'x86'
                    }
                    else {
                        'x64'
                    }

                    $msixUri = switch ($architecture) {
                        'x86'   { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196060' }
                        'x64'   { 'https://go.microsoft.com/fwlink/?linkid=2196106' }
                        'arm64' { 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196207' }
                        default { throw "Unsupported Teams architecture '$architecture'." }
                    }

                    $bootstrapperUri = 'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204'

                    Write-PreInstallLog -Event 'BuiltInRefreshStart' -Message 'Checking Microsoft Teams cache for updates.' -Data @{ Id = 'Teams'; Architecture = $architecture }

                    $remoteMetadata = Get-RemoteMetadata -Uri $msixUri
                    $metadataMatches = $false

                    if ($cacheInfo) {
                        if ($remoteMetadata.ETag -and $cacheInfo.RemoteETag) {
                            $metadataMatches = $remoteMetadata.ETag -eq [string]$cacheInfo.RemoteETag
                        }
                        elseif (
                            $remoteMetadata.LastModified -and $cacheInfo.RemoteLastModified -and
                            $remoteMetadata.ContentLength -and $cacheInfo.RemoteContentLength
                        ) {
                            $metadataMatches = (
                                $remoteMetadata.LastModified -eq [string]$cacheInfo.RemoteLastModified -and
                                [int64]$remoteMetadata.ContentLength -eq [int64]$cacheInfo.RemoteContentLength
                            )
                        }
                    }

                    $tempRoot = Join-Path $StagedPath 'Work\Refresh\Teams'
                    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

                    $tempBootstrapper = Join-Path $tempRoot 'teamsbootstrapper.exe'
                    Invoke-WebRequest -Uri $bootstrapperUri -OutFile $tempBootstrapper -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
                    Copy-Item -LiteralPath $tempBootstrapper -Destination $usbBootstrapperPath -Force

                    $updated = $false
                    if (-not $metadataMatches) {
                        $tempMsix = Join-Path $tempRoot 'teams.msix'
                        Invoke-WebRequest -Uri $msixUri -OutFile $tempMsix -UseBasicParsing -TimeoutSec 900 -ErrorAction Stop

                        $resolvedVersion = Get-TeamsPackageVersion -Path $tempMsix
                        Copy-Item -LiteralPath $tempMsix -Destination $usbMsixPath -Force
                        $updated = $true
                    }
                    else {
                        $resolvedVersion = if ($cacheInfo -and $cacheInfo.Version) {
                            [string]$cacheInfo.Version
                        }
                        else {
                            Get-TeamsPackageVersion -Path $usbMsixPath
                        }
                    }

                    [ordered]@{
                        Id                  = 'Teams'
                        Cached              = $true
                        Version             = $resolvedVersion
                        Architecture        = $architecture
                        RemoteETag          = $remoteMetadata.ETag
                        RemoteLastModified  = $remoteMetadata.LastModified
                        RemoteContentLength = $remoteMetadata.ContentLength
                        RemoteFinalUri      = $remoteMetadata.FinalUri
                        SyncedAt            = (Get-Date).ToUniversalTime().ToString('o')
                    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8

                    New-Item -ItemType Directory -Path $localTeamsRoot -Force | Out-Null
                    Copy-Item -LiteralPath $usbBootstrapperPath -Destination (Join-Path $localTeamsRoot 'teamsbootstrapper.exe') -Force
                    Copy-Item -LiteralPath $cacheInfoPath -Destination (Join-Path $localTeamsRoot 'CacheInfo.json') -Force

                    $localVersion = $null
                    $localMsix = Join-Path $localTeamsRoot 'teams.msix'
                    if (Test-Path -LiteralPath $localMsix -PathType Leaf) {
                        try {
                            $localVersion = Get-TeamsPackageVersion -Path $localMsix
                        }
                        catch { }
                    }

                    if ($updated -or $localVersion -ne $resolvedVersion) {
                        Copy-Item -LiteralPath $usbMsixPath -Destination $localMsix -Force
                    }

                    Write-PreInstallLog -Event 'BuiltInRefreshComplete' -Message 'Microsoft Teams cache refresh completed.' -Data @{ Id = 'Teams'; Version = $resolvedVersion; Updated = $updated }
                }
                catch {
                    Write-PreInstallLog -Event 'BuiltInRefreshFailed' -Level 'Warning' -Message $_.Exception.Message -Data @{ Id = 'Teams'; Fallback = 'ExistingStagedPayload' }
                }
            }
        }
    }

    Write-PreInstallLog -Event 'RefreshComplete' -Message 'Built-in application refresh phase completed. Installation will continue.'
    exit 0
}
catch {
    try {
        Write-PreInstallLog -Event 'RefreshFailed' -Level 'Warning' -Message $_.Exception.Message -Data @{ Fallback = 'ExistingStagedPayload' }
    }
    catch { }

    # Refresh is intentionally non-fatal. The installer must still be allowed
    # to use the payload that was staged during WinPE.
    exit 0
}
