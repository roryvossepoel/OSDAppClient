function Add-OSDAppInstallOrderEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('Repository','BuiltIn')][string]$Source
    )

    $installOrder = @()
    if ($Manifest.PSObject.Properties.Name -contains 'InstallOrder' -and $Manifest.InstallOrder) {
        $installOrder = @(
            $Manifest.InstallOrder |
                Where-Object { [string]$_.Id -ne $Id }
        )
    }

    $installOrder += [pscustomobject]@{
        Id     = $Id
        Source = $Source
    }

    if ($Manifest.PSObject.Properties.Name -contains 'InstallOrder') {
        $Manifest.InstallOrder = @($installOrder)
    }
    else {
        $Manifest | Add-Member -NotePropertyName InstallOrder -NotePropertyValue @($installOrder)
    }

    $Manifest
}
