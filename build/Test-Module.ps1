[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Path $PSScriptRoot -Parent

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object Version -ge ([version]'5.5.0'))) {
    throw 'Pester 5.5.0 or later is required.'
}
if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    throw 'PSScriptAnalyzer is required.'
}

$settingsPath = Join-Path $root 'PSScriptAnalyzerSettings.psd1'
$analysisTargets = @(
    (Join-Path $root 'OSDApps.psm1'),
    (Join-Path $root 'Public'),
    (Join-Path $root 'Private'),
    (Join-Path $root 'Runtime'),
    (Join-Path $root 'build')
)

$analysis = @(
    foreach ($target in $analysisTargets) {
        if (Test-Path -LiteralPath $target) {
            Invoke-ScriptAnalyzer -Path $target -Recurse -Settings $settingsPath
        }
    }
)

if ($analysis.Count -gt 0) {
    $analysis |
        Sort-Object Severity, ScriptName, Line |
        Format-Table Severity, RuleName, ScriptName, Line, Message -AutoSize |
        Out-String |
        Write-Host
}

$analysisErrors = @($analysis | Where-Object Severity -eq 'Error')
if ($analysisErrors.Count -gt 0) {
    throw "PSScriptAnalyzer reported $($analysisErrors.Count) error finding(s)."
}

if ($analysis.Count -gt 0) {
    Write-Host "PSScriptAnalyzer completed with $($analysis.Count) warning(s)/informational finding(s); no blocking errors were found."
}
else {
    Write-Host 'PSScriptAnalyzer completed with no findings.'
}

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $root 'Tests'
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$result = Invoke-Pester -Configuration $config

if ($result.FailedCount -gt 0) {
    throw "Pester reported $($result.FailedCount) failed test(s)."
}

& (Join-Path $PSScriptRoot 'Build-Module.ps1') | Out-Host
