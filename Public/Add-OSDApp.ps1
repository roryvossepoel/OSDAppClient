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
            if($app -ieq 'GoogleChromeEnterprise'){throw "'GoogleChromeEnterprise' is a built-in application. Use Add-OSDAppGoogleChromeEnterprise instead."}
            if($app -ieq 'MozillaFirefoxEnterprise'){throw "'MozillaFirefoxEnterprise' is a built-in application. Use Add-OSDAppMozillaFirefoxEnterprise instead."}
        }

        $cachePath=Get-OSDAppCachePath

        $sourceUri = (Get-OSDAppConfiguration).CatalogUri
        if (-not $sourceUri) {
            $cacheCatalogPath = Join-Path $cachePath 'CacheCatalog.json'
            if (-not (Test-Path -LiteralPath $cacheCatalogPath -PathType Leaf)) {
                throw 'No OSD App Catalog is configured and no repository cache is available. Configure CatalogUri with Set-OSDAppConfiguration, or synchronize the repository cache explicitly.'
            }
        }
        else {
            if ($VerbosePreference -ne 'SilentlyContinue') {
                Write-OSDAppConsole -Level Info -Component 'Repository' -Message ("Synchronizing requested repository application(s): {0}" -f ($apps -join ', '))
            }

            Sync-OSDAppCache -CatalogUri $sourceUri -CachePath $cachePath -Name $apps -Confirm:$false | Out-Null

            if ($VerbosePreference -ne 'SilentlyContinue') {
                Write-OSDAppConsole -Level Success -Component 'Repository' -Message 'Requested repository application cache is current'
            }
        }

        $resolvedWindowsPath=Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
        $stagedRelativePath='Windows\Temp\OSDApps'

        if($PSCmdlet.ShouldProcess(($apps -join ', '),"Stage repository applications for SetupComplete on $resolvedWindowsPath")){
            Copy-OSDAppContent -Name $apps -CachePath $cachePath -WindowsPath $resolvedWindowsPath -DestinationRelativePath $stagedRelativePath | Out-Null
            $manifestPath=Join-Path (Join-Path $resolvedWindowsPath $stagedRelativePath) 'DeviceManifest.json'
            $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $manifest = Set-OSDAppManifestRuntimeConfiguration -Manifest $manifest
            $manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
            Add-OSDAppSetupComplete -WindowsPath $resolvedWindowsPath -StagedRelativePath $stagedRelativePath -Confirm:$false | Out-Null
        }

        foreach($app in $apps){[pscustomobject]@{PSTypeName='OSDApps.StagedApp';Name=$app;CachePath=$cachePath;WindowsPath=$resolvedWindowsPath;StagedPath=(Join-Path $resolvedWindowsPath $stagedRelativePath);Source='Repository'}}
    }
}