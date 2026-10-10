function Get-OSDAppUIStagedIds {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$WindowsPath)

    $manifestPath = Join-Path $WindowsPath 'Windows\Temp\OSDApps\DeviceManifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
        ConvertFrom-Json -ErrorAction Stop
    foreach ($app in @($manifest.Apps)) {
        if ($null -ne $app -and -not [string]::IsNullOrWhiteSpace([string]$app.Id)) {
            [string]$app.Id
        }
    }
}

function Invoke-OSDAppUIStage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Applications,
        [Parameter(Mandatory)][string]$WindowsPath,
        [switch]$Offline
    )

    if (-not (Test-OSDAppWinPE)) {
        throw 'Staging from the GUI is supported in WinPE after Windows has been applied. Full Windows is inspection-only in this MVP.'
    }

    $resolvedTarget = Resolve-OSDAppWindowsPath -WindowsPath $WindowsPath
    $apps = @($Applications)
    if ($apps.Count -eq 0) {
        throw 'Select at least one application.'
    }

    $builtInCmdlets = @{
        Microsoft365Apps          = 'Add-OSDAppMicrosoft365Apps'
        MicrosoftTeams            = 'Add-OSDAppMicrosoftTeams'
        AdobeAcrobatUnified       = 'Add-OSDAppAdobeAcrobatUnified'
        GoogleChromeEnterprise   = 'Add-OSDAppGoogleChromeEnterprise'
        MozillaFirefoxEnterprise = 'Add-OSDAppMozillaFirefoxEnterprise'
        CiscoWebex                = 'Add-OSDAppCiscoWebex'
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $builtIns = [System.Collections.Generic.List[object]]::new()
    $repository = [System.Collections.Generic.List[string]]::new()

    # Resolve/validate the entire selection before executing any staging.
    foreach ($app in $apps) {
        $id = [string]$app.Id
        if ([string]::IsNullOrWhiteSpace($id) -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or $id -match '\.\.') {
            throw "Invalid application ID: '$id'."
        }
        if (-not $seen.Add($id)) {
            throw "Application '$id' is selected multiple times."
        }

        if ($app.Source -eq 'BuiltIn') {
            if (-not $builtInCmdlets.ContainsKey($id)) {
                throw "Unsupported built-in application: '$id'."
            }
            $builtIns.Add($app)
        }
        elseif ($app.Source -eq 'Repository') {
            if ($builtInCmdlets.ContainsKey($id)) {
                throw "Application '$id' must be staged as a built-in, not a repository package."
            }
            $repository.Add($id)
        }
        else {
            throw "Unknown application source '$($app.Source)' for '$id'."
        }
    }

    # UI lists built-ins before repository packages to match queue order.
    # Repository apps are staged in one call to retain P1 multi-app integrity.
    foreach ($app in $builtIns) {
        $commandName = $builtInCmdlets[[string]$app.Id]
        & $commandName -WindowsPath $resolvedTarget -Confirm:$false -ErrorAction Stop | Out-Null
    }

    if ($repository.Count -gt 0) {
        Add-OSDApp -Name @($repository.ToArray()) -WindowsPath $resolvedTarget -SkipCacheRefresh:$Offline -Confirm:$false -ErrorAction Stop | Out-Null
    }

    $staged = @(Get-OSDAppUIStagedIds -WindowsPath $resolvedTarget)
    $missing = @($apps | Where-Object { [string]$_.Id -notin $staged })
    if ($missing.Count -gt 0) {
        throw "Staging completed but DeviceManifest is missing: $((@($missing.Id)) -join ', ')."
    }

    [pscustomobject]@{
        WindowsPath = $resolvedTarget
        Requested   = @($apps | ForEach-Object { [string]$_.Id })
        Staged      = @($staged)
        Offline     = [bool]$Offline
    }
}
