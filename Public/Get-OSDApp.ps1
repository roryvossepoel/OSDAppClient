function Get-OSDApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ManifestPath,
        [string[]]$Name
    )

    $manifest = Get-OSDAppManifest -Path $ManifestPath
    $packages = @($manifest.Packages)

    if ($Name) {
        $packages = $packages | Where-Object { $_.Id -in $Name }
    }

    $packages
}
