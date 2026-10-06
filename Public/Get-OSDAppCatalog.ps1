function Get-OSDAppCatalog {
    [CmdletBinding()]
    param()

    $catalogUri = (Get-OSDAppConfiguration).CatalogUri

    if (-not $catalogUri) {
        return [pscustomobject]@{
            PSTypeName       = 'OSDAppClient.CatalogStatus'
            Uri              = $null
            Scope            = 'Session'
            Available        = $false
            ApplicationCount = 0
            SchemaVersion    = $null
        }
    }

    try {
        $response = Invoke-WebRequest -Uri $catalogUri -UseBasicParsing -ErrorAction Stop
        $catalog = $response.Content | ConvertFrom-Json -ErrorAction Stop

        [pscustomobject]@{
            PSTypeName       = 'OSDAppClient.CatalogStatus'
            Uri              = $catalogUri
            Scope            = 'Session'
            Available        = $true
            ApplicationCount = @($catalog.Applications).Count
            SchemaVersion    = $catalog.SchemaVersion
        }
    }
    catch {
        [pscustomobject]@{
            PSTypeName       = 'OSDAppClient.CatalogStatus'
            Uri              = $catalogUri
            Scope            = 'Session'
            Available        = $false
            ApplicationCount = 0
            SchemaVersion    = $null
        }
    }
}
