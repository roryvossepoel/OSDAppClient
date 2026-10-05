[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$StagedPath,
    [string]$CacheVolumeLabel = 'OSDCloud',
    [ValidateRange(1,120)][int]$OfficeRefreshTimeoutMinutes = 20
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
$manifestPath = Join-Path $StagedPath 'DeviceManifest.json'
$logDirectory = Join-Path $env:ProgramData 'OSDApps\Logs'
$logPath = Join-Path $logDirectory 'Install.log'

function Write-PreInstallLog {
    param([string]$Event,[ValidateSet('Info','Warning','Error')][string]$Level='Info',[string]$Message,[hashtable]$Data)
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $type = if ($Level -eq 'Warning') { 2 } elseif ($Level -eq 'Error') { 3 } else { 1 }
    $details = @()
    if ($Data) { foreach ($key in @($Data.Keys | Sort-Object)) { $value=$Data[$key]; if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) { $value=@($value)-join ',' }; $details += ('{0}={1}' -f $key,$value) } }
    $msg = if ($Message) { "[$Event] $Message" } else { "[$Event]" }
    if ($details.Count -gt 0) { $msg += ' | ' + ($details -join '; ') }
    $msg = $msg -replace '\]LOG\]!>', ']LOG]! >'
    $now=(Get-Date).ToUniversalTime(); $time=$now.ToString('HH:mm:ss.fff') + '+000'; $date=$now.ToString('MM-dd-yyyy'); $thread=[System.Threading.Thread]::CurrentThread.ManagedThreadId
    $line='<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="PreInstall" context="" type="{3}" thread="{4}" file="">' -f $msg,$time,$date,$type,$thread
    Add-Content -LiteralPath $logPath -Value $line -Encoding UTF8
}

function Test-InternetEndpoint {
    param([Parameter(Mandatory)][string]$Uri,[int]$TimeoutSec=10)
    try { Invoke-WebRequest -Uri $Uri -Method Head -UseBasicParsing -TimeoutSec $TimeoutSec -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}

function Get-OfficeCacheVersion {
    param([Parameter(Mandatory)][string]$OfficeRoot)
    $dataPath=Join-Path $OfficeRoot 'Office\Data'
    if (-not (Test-Path -LiteralPath $dataPath -PathType Container)) { return $null }
    $versions=@(Get-ChildItem -LiteralPath $dataPath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+\.\d+\.\d+\.\d+$' } | ForEach-Object { try { [pscustomobject]@{Name=$_.Name;Version=[version]$_.Name} } catch{} } | Sort-Object Version -Descending)
    if ($versions.Count -gt 0) { return $versions[0].Name }
    return $null
}

function Get-TeamsPackageVersion {
    param([Parameter(Mandatory)][string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive=[System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry=$archive.Entries | Where-Object { $_.FullName -eq 'AppxManifest.xml' } | Select-Object -First 1
        if (-not $entry) { throw 'AppxManifest.xml was not found in the Teams MSIX.' }
        $reader=New-Object System.IO.StreamReader($entry.Open())
        try { [xml]$m=$reader.ReadToEnd() } finally { $reader.Dispose() }
        return [string]$m.Package.Identity.Version
    } finally { $archive.Dispose() }
}

function Get-RemoteMetadata {
    param([Parameter(Mandatory)][string]$Uri,[int]$TimeoutSec=15)
    $handler=[System.Net.Http.HttpClientHandler]::new(); $handler.AllowAutoRedirect=$true
    $client=[System.Net.Http.HttpClient]::new($handler); $client.Timeout=[TimeSpan]::FromSeconds($TimeoutSec)
    try {
        $request=[System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Head,$Uri)
        $response=$client.SendAsync($request).GetAwaiter().GetResult()
        try {
            $response.EnsureSuccessStatusCode() | Out-Null
            [pscustomobject]@{
                ETag=if($response.Headers.ETag){[string]$response.Headers.ETag.Tag}else{$null}
                LastModified=if($response.Content.Headers.LastModified){$response.Content.Headers.LastModified.UtcDateTime.ToString('o')}else{$null}
                ContentLength=if($response.Content.Headers.ContentLength){[int64]$response.Content.Headers.ContentLength}else{$null}
                FinalUri=[string]$response.RequestMessage.RequestUri.AbsoluteUri
            }
        } finally { $response.Dispose(); $request.Dispose() }
    } finally { $client.Dispose(); $handler.Dispose() }
}

function Copy-DirectoryReplace {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
    $temp="$Destination.refresh"
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force}
    Copy-Item -LiteralPath $Source -Destination $temp -Recurse -Force
    if(Test-Path -LiteralPath $Destination){Remove-Item -LiteralPath $Destination -Recurse -Force}
    Move-Item -LiteralPath $temp -Destination $Destination -Force
}

function Test-LocalOfficeSource {
    param([string]$Root)
    return ((Test-Path -LiteralPath (Join-Path $Root 'setup.exe') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $Root 'configuration.xml') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $Root 'Office\Data') -PathType Container))
}

function Test-LocalTeamsSource {
    param([string]$Root)
    return ((Test-Path -LiteralPath (Join-Path $Root 'teamsbootstrapper.exe') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $Root 'teams.msix') -PathType Leaf))
}

try {
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Device manifest not found: $manifestPath" }
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $builtInApps=if($manifest.PSObject.Properties.Name -contains 'BuiltInApps'){@($manifest.BuiltInApps)}else{@()}
    if($builtInApps.Count -eq 0){Write-PreInstallLog -Event 'RefreshSkipped' -Message 'No built-in applications are staged. Nothing to refresh.'; exit 0}

    $cacheVolume=Get-Volume -ErrorAction SilentlyContinue | Where-Object { $_.FileSystemLabel -eq $CacheVolumeLabel -and $_.DriveLetter } | Select-Object -First 1
    $usbRoot=if($cacheVolume){"$($cacheVolume.DriveLetter):\OSDApps"}else{$null}
    Write-PreInstallLog -Event 'RefreshStart' -Message 'Starting built-in acquisition and refresh before installation.' -Data @{StagedPath=$StagedPath;BuiltInApps=@($builtInApps.Id);CacheAvailable=[bool]$usbRoot;CacheRoot=$usbRoot}
    if($usbRoot){New-Item -ItemType Directory -Path $usbRoot -Force | Out-Null; Write-PreInstallLog -Event 'CacheVolumeFound' -Message 'OSDCloud USB cache is available and will be used automatically.' -Data @{CacheRoot=$usbRoot}}
    else{Write-PreInstallLog -Event 'CacheVolumeNotFound' -Message 'No OSDCloud USB cache is connected. Built-ins will be acquired directly to the local Windows runtime.'}

    $networkAvailable=[System.Net.NetworkInformation.NetworkInterface]::GetIsNetworkAvailable()

    foreach($app in $builtInApps){
        switch($app.Id){
            'Microsoft365Apps' {
                $localRoot=Join-Path $StagedPath 'BuiltIn\Microsoft365Apps'
                New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
                $acquireRoot=if($usbRoot){Join-Path $usbRoot 'BuiltIn\Microsoft365Apps'}else{$localRoot}
                New-Item -ItemType Directory -Path $acquireRoot -Force | Out-Null
                $localConfig=Join-Path $localRoot 'configuration.xml'
                if(-not (Test-Path -LiteralPath $localConfig -PathType Leaf)){throw 'Microsoft 365 Apps configuration.xml is missing from the staged deployment intent.'}

                if($usbRoot -and -not (Test-LocalOfficeSource -Root $localRoot) -and (Test-LocalOfficeSource -Root $acquireRoot)){
                    Copy-Item -LiteralPath (Join-Path $acquireRoot 'setup.exe') -Destination (Join-Path $localRoot 'setup.exe') -Force
                    Copy-Item -LiteralPath (Join-Path $acquireRoot 'configuration.xml') -Destination $localConfig -Force
                    if(Test-Path -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -PathType Leaf){Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force}
                    Copy-DirectoryReplace -Source (Join-Path $acquireRoot 'Office') -Destination (Join-Path $localRoot 'Office')
                    Write-PreInstallLog -Event 'BuiltInCacheRestaged' -Message 'Existing Microsoft 365 Apps USB cache was staged locally.' -Data @{Id='Microsoft365Apps'}
                }

                if(-not $networkAvailable){
                    if(Test-LocalOfficeSource -Root $localRoot){Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Level 'Warning' -Message 'No network is available. Existing staged Office payload will be used.' -Data @{Id='Microsoft365Apps'}; continue}
                    throw 'Microsoft 365 Apps has no staged or USB-cached payload and no network connection is available to acquire one.'
                }

                try {
                    $acquireConfig=Join-Path $acquireRoot 'configuration.xml'
                    Copy-Item -LiteralPath $localConfig -Destination $acquireConfig -Force
                    $setupPath=Join-Path $acquireRoot 'setup.exe'
                    $odtUri=if($app.OfficeDeploymentToolUri){[string]$app.OfficeDeploymentToolUri}else{'https://officecdn.microsoft.com/pr/wsus/setup.exe'}
                    if(-not (Test-Path -LiteralPath $setupPath -PathType Leaf)){Invoke-WebRequest -Uri $odtUri -OutFile $setupPath -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop}
                    if(-not (Test-InternetEndpoint -Uri $odtUri)){throw 'Microsoft 365 Apps CDN is not reachable.'}
                    $previous=Get-OfficeCacheVersion -OfficeRoot $acquireRoot
                    Write-PreInstallLog -Event 'BuiltInRefreshStart' -Message 'Synchronizing Microsoft 365 Apps content.' -Data @{Id='Microsoft365Apps';Target=if($usbRoot){'USB'}else{'Local'};PreviousVersion=$previous;TimeoutMinutes=$OfficeRefreshTimeoutMinutes}
                    $process=Start-Process -FilePath $setupPath -ArgumentList @('/download',$acquireConfig) -WorkingDirectory $acquireRoot -PassThru
                    $sw=[System.Diagnostics.Stopwatch]::StartNew()
                    while(-not $process.HasExited){if($sw.Elapsed.TotalMinutes -ge $OfficeRefreshTimeoutMinutes){try{$process.Kill();$process.WaitForExit()}catch{};throw "Office Deployment Tool cache refresh exceeded the $OfficeRefreshTimeoutMinutes minute timeout."};Start-Sleep -Seconds 2;$process.Refresh()}
                    $sw.Stop()
                    if($process.ExitCode -ne 0){throw "Office Deployment Tool exited with code $($process.ExitCode)."}
                    $version=Get-OfficeCacheVersion -OfficeRoot $acquireRoot
                    if(-not $version){throw 'Office acquisition completed but Office\Data does not contain a resolvable version.'}
                    $cacheInfo=[ordered]@{Id='Microsoft365Apps';Cached=[bool]$usbRoot;Version=$version;Architecture=$app.Architecture;Channel=$app.Channel;ProductId=$app.ProductId;Language=@($app.Language);SyncedAt=(Get-Date).ToUniversalTime().ToString('o')}
                    $cacheInfoPath=Join-Path $acquireRoot 'CacheInfo.json'; $cacheInfo | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8
                    if($usbRoot){
                        Copy-Item -LiteralPath $setupPath -Destination (Join-Path $localRoot 'setup.exe') -Force
                        Copy-Item -LiteralPath $acquireConfig -Destination $localConfig -Force
                        Copy-Item -LiteralPath $cacheInfoPath -Destination (Join-Path $localRoot 'CacheInfo.json') -Force
                        Copy-DirectoryReplace -Source (Join-Path $acquireRoot 'Office') -Destination (Join-Path $localRoot 'Office')
                    }
                    Write-PreInstallLog -Event 'BuiltInRefreshComplete' -Message 'Microsoft 365 Apps content is ready for installation.' -Data @{Id='Microsoft365Apps';Version=$version;CacheUpdated=[bool]$usbRoot}
                } catch {
                    if(Test-LocalOfficeSource -Root $localRoot){Write-PreInstallLog -Event 'BuiltInRefreshFailed' -Level 'Warning' -Message $_.Exception.Message -Data @{Id='Microsoft365Apps';Fallback='ExistingStagedPayload'};continue}
                    throw "Microsoft 365 Apps acquisition failed and no staged fallback is available. $($_.Exception.Message)"
                }
            }
            'Teams' {
                $localRoot=Join-Path $StagedPath 'BuiltIn\Teams'; New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
                $acquireRoot=if($usbRoot){Join-Path $usbRoot 'BuiltIn\Teams'}else{$localRoot}; New-Item -ItemType Directory -Path $acquireRoot -Force | Out-Null
                if($usbRoot -and -not (Test-LocalTeamsSource -Root $localRoot) -and (Test-LocalTeamsSource -Root $acquireRoot)){
                    Copy-Item -LiteralPath (Join-Path $acquireRoot 'teamsbootstrapper.exe') -Destination (Join-Path $localRoot 'teamsbootstrapper.exe') -Force
                    Copy-Item -LiteralPath (Join-Path $acquireRoot 'teams.msix') -Destination (Join-Path $localRoot 'teams.msix') -Force
                    if(Test-Path -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -PathType Leaf){Copy-Item -LiteralPath (Join-Path $acquireRoot 'CacheInfo.json') -Destination (Join-Path $localRoot 'CacheInfo.json') -Force}
                    Write-PreInstallLog -Event 'BuiltInCacheRestaged' -Message 'Existing Microsoft Teams USB cache was staged locally.' -Data @{Id='Teams'}
                }

                if(-not $networkAvailable){
                    if(Test-LocalTeamsSource -Root $localRoot){Write-PreInstallLog -Event 'BuiltInRefreshSkipped' -Level 'Warning' -Message 'No network is available. Existing staged Teams payload will be used.' -Data @{Id='Teams'};continue}
                    throw 'Microsoft Teams has no staged or USB-cached payload and no network connection is available to acquire one.'
                }
                try {
                    $architecture=if($app.Architecture){[string]$app.Architecture}elseif($env:PROCESSOR_ARCHITECTURE -eq 'ARM64'){'arm64'}else{'x64'}
                    $msixUri=if($app.MsixUri){[string]$app.MsixUri}else{switch($architecture){'x86'{'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196060'}'x64'{'https://go.microsoft.com/fwlink/?linkid=2196106'}'arm64'{'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2196207'}}}
                    $bootstrapperUri=if($app.BootstrapperUri){[string]$app.BootstrapperUri}else{'https://go.microsoft.com/fwlink/?clcid=0x409&linkid=2243204'}
                    $cacheInfoPath=Join-Path $acquireRoot 'CacheInfo.json'; $cacheInfo=$null
                    if(Test-Path -LiteralPath $cacheInfoPath -PathType Leaf){try{$cacheInfo=Get-Content -LiteralPath $cacheInfoPath -Raw -Encoding UTF8 | ConvertFrom-Json}catch{}}
                    $msixPath=Join-Path $acquireRoot 'teams.msix'; $bootstrapperPath=Join-Path $acquireRoot 'teamsbootstrapper.exe'
                    $remote=Get-RemoteMetadata -Uri $msixUri; $matches=$false
                    if((Test-Path -LiteralPath $msixPath -PathType Leaf) -and $cacheInfo){if($remote.ETag -and $cacheInfo.RemoteETag){$matches=$remote.ETag -eq [string]$cacheInfo.RemoteETag}elseif($remote.LastModified -and $cacheInfo.RemoteLastModified -and $remote.ContentLength -and $cacheInfo.RemoteContentLength){$matches=($remote.LastModified -eq [string]$cacheInfo.RemoteLastModified -and [int64]$remote.ContentLength -eq [int64]$cacheInfo.RemoteContentLength)}}
                    $tempRoot=Join-Path $StagedPath 'Work\Refresh\Teams'; New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
                    $tempBootstrapper=Join-Path $tempRoot 'teamsbootstrapper.exe'; Invoke-WebRequest -Uri $bootstrapperUri -OutFile $tempBootstrapper -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop; Copy-Item -LiteralPath $tempBootstrapper -Destination $bootstrapperPath -Force
                    $updated=$false
                    if(-not $matches){$tempMsix=Join-Path $tempRoot 'teams.msix';Invoke-WebRequest -Uri $msixUri -OutFile $tempMsix -UseBasicParsing -TimeoutSec 900 -ErrorAction Stop;$version=Get-TeamsPackageVersion -Path $tempMsix;Copy-Item -LiteralPath $tempMsix -Destination $msixPath -Force;$updated=$true}else{$version=if($cacheInfo -and $cacheInfo.Version){[string]$cacheInfo.Version}else{Get-TeamsPackageVersion -Path $msixPath}}
                    [ordered]@{Id='Teams';Cached=[bool]$usbRoot;Version=$version;Architecture=$architecture;BootstrapperUri=$bootstrapperUri;RemoteETag=$remote.ETag;RemoteLastModified=$remote.LastModified;RemoteContentLength=$remote.ContentLength;RemoteFinalUri=$remote.FinalUri;SyncedAt=(Get-Date).ToUniversalTime().ToString('o')} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $cacheInfoPath -Encoding UTF8
                    if($usbRoot){Copy-Item -LiteralPath $bootstrapperPath -Destination (Join-Path $localRoot 'teamsbootstrapper.exe') -Force;Copy-Item -LiteralPath $msixPath -Destination (Join-Path $localRoot 'teams.msix') -Force;Copy-Item -LiteralPath $cacheInfoPath -Destination (Join-Path $localRoot 'CacheInfo.json') -Force}
                    Write-PreInstallLog -Event 'BuiltInRefreshComplete' -Message 'Microsoft Teams content is ready for installation.' -Data @{Id='Teams';Version=$version;Updated=$updated;CacheUpdated=[bool]$usbRoot}
                } catch {
                    if(Test-LocalTeamsSource -Root $localRoot){Write-PreInstallLog -Event 'BuiltInRefreshFailed' -Level 'Warning' -Message $_.Exception.Message -Data @{Id='Teams';Fallback='ExistingStagedPayload'};continue}
                    throw "Microsoft Teams acquisition failed and no staged fallback is available. $($_.Exception.Message)"
                }
            }
        }
    }

    Write-PreInstallLog -Event 'RefreshComplete' -Message 'Built-in acquisition and refresh completed. Installation will continue.' -Data @{CacheUsed=[bool]$usbRoot}
    exit 0
} catch {
    Write-PreInstallLog -Event 'RefreshFailed' -Level 'Error' -Message $_.Exception.Message
    exit 1
}