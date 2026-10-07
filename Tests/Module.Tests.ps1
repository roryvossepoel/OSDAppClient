$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path $moduleRoot 'OSDApps.psd1'

Describe 'OSDApps module' {
    BeforeAll {
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        Import-Module $manifestPath -Force
        $manifest = Test-ModuleManifest -Path $manifestPath
    }

    It 'has a valid module manifest' {
        $manifest | Should -Not -BeNullOrEmpty
        $manifest.Name | Should -Be 'OSDApps'
    }

    It 'imports successfully' {
        Get-Module OSDApps | Should -Not -BeNullOrEmpty
    }

    It 'exports exactly the functions declared in the manifest' {
        $declared = @((Import-PowerShellDataFile -Path $manifestPath).FunctionsToExport | Sort-Object)
        $exported = @(Get-Command -Module OSDApps -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
        Compare-Object -ReferenceObject $declared -DifferenceObject $exported | Should -BeNullOrEmpty
    }

    It 'uses the Runtime.log default' {
        $configuration = Get-OSDAppConfiguration
        $configuration.LogPath | Should -Be '%ProgramData%\OSDApps\Logs\Runtime.log'
    }

    It 'uses safe default runtime configuration' {
        $configuration = Get-OSDAppConfiguration
        $configuration.CleanupMode | Should -Be 'OnSuccess'
        $configuration.CacheVolumeLabel | Should -Be 'OSDCloud'
        $configuration.Scope | Should -Be 'Session'
    }
}
