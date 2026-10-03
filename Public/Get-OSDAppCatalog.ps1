function Get-OSDAppCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string[]]$Name,

        [uri]$Uri
    )

    $catalogUri = if ($Uri) { $Uri } else { $script:OSDAppCatalogUri }

    if (-not $catalogUri) {
        throw 'No OSD App Catalog is configured. Run Set-OSDAppCatalog -Uri <catalog.json URL> first, or specify -Uri.'
    }

    try {
        $response = Invoke-WebRequest -Uri $catalogUri -UseBasicParsing -ErrorAction Stop
        $catalog = $response.Content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to read OSD App Catalog '$catalogUri': $($_.Exception.Message)"
    }

    $apps = @(
        foreach ($package in @($catalog.Packages)) {
            [pscustomobject]@{
                PSTypeName   = 'OSDAppClient.CatalogApp'
                Id           = $package.Id
                Name         = $package.Id
                DisplayName  = $package.DisplayName
                Version      = $package.Version
                Architecture = $package.Architecture
                Source       = 'Repository'
                Availability = 'Online'
            }
        }
    )

    if ($Name) {
        $apps = @(
            $apps | Where-Object {
                foreach ($pattern in $Name) {
                    if ($_.Id -like $pattern -or $_.DisplayName -like $pattern) {
                        return $true
                    }
                }
                return $false
            }
        )
    }

    $apps
}
