function Add-OSDApp {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position=0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [string[]]$Name,
        [string]$WindowsPath
    )

    begin { $requested=[System.Collections.Generic.List[string]]::new() }
    process { foreach($item in $Name){ if(-not [string]::IsNullOrWhiteSpace($item)){ $requested.Add($item) } } }
    end {
        $apps=@($requested | Select-Object -Unique)
        if($apps.Count -eq 0){throw 'No applications were supplied.'}

        foreach($app in $apps){
            if($app -ieq 'Microsoft365Apps'){throw "'Microsoft365Apps' is a built-in application. Use Add-OSDAppMicrosoft365Apps instead."}
            if($app -ieq 'Teams'){throw "'Teams' is a built-in application. Use Add-OSDAppTeams instead."}
            if($app -ieq 'AdobeAcrobatUnified'){throw "'AdobeAcrobatUnified' is a built-in application. Use Add-OSDAppAdobeAcrobatUnified instead."}
        }

        $cachePath=Get-OSDAppCachePath
        $cacheCatalogPath=Join-Path $cachePath 'CacheCatalog.json'
        if(-not (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf)){throw "OSD App repository cache metadata not found: $cacheCatalogPath. Run Sync-OSDAppRepository first."}

        $resolvedWindowsPath=Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
        $stagedRelativePath='Windows\Temp\OSDApps'

        if($PSCmdlet.ShouldProcess(($apps -join ', '),"Stage repository applications for SetupComplete on $resolvedWindowsPath")){
            Copy-OSDAppContent -Name $apps -CachePath $cachePath -WindowsPath $resolvedWindowsPath -DestinationRelativePath $stagedRelativePath | Out-Null
            $manifestPath=Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
            $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if(-not ($manifest.PSObject.Properties.Name -contains 'Runtime')){
                $manifest | Add-Member -NotePropertyName Runtime -NotePropertyValue ([pscustomobject]@{KeepSource=$false;LogPath='%ProgramData%\OSDApps\Logs\Install.log'})
                $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
            }
            Add-OSDAppSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null
        }

        foreach($app in $apps){[pscustomobject]@{PSTypeName='OSDAppClient.StagedApp';Name=$app;CachePath=$cachePath;WindowsPath=$resolvedWindowsPath;StagedPath=(Join-Path $resolvedWindowsPath $stagedRelativePath);Source='Repository'}}
    }
}