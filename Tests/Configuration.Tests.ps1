$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path $moduleRoot 'OSDApps.psd1'

Describe 'OSDApps configuration' {
    BeforeEach {
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        Import-Module $manifestPath -Force
    }

    It 'is silent by default when setting configuration' {
        @(Set-OSDAppConfiguration -CleanupMode Never).Count | Should -Be 0
    }

    It 'returns the effective configuration with PassThru' {
        $result = Set-OSDAppConfiguration -CleanupMode Never -CacheVolumeLabel TestCache -PassThru
        $result.CleanupMode | Should -Be 'Never'
        $result.CacheVolumeLabel | Should -Be 'TestCache'
    }

    It 'preserves values that were not changed' {
        Set-OSDAppConfiguration -CacheVolumeLabel TestCache
        Set-OSDAppConfiguration -CleanupMode Never
        $result = Get-OSDAppConfiguration
        $result.CacheVolumeLabel | Should -Be 'TestCache'
        $result.CleanupMode | Should -Be 'Never'
    }

    It 'rejects non-http catalog schemes' {
        { Set-OSDAppConfiguration -CatalogUri 'file:///C:/catalog.json' } | Should -Throw '*HTTP or HTTPS*'
    }
}
