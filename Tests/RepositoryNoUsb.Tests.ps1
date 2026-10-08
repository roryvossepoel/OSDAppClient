Describe 'Repository staging without OSDCloud USB' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force
    }

    It 'uses offline Windows cache when USB cache resolution fails' {
        InModuleScope OSDApps {
            $root = Join-Path $TestDrive 'WindowsVolume'
            $stage = Join-Path $root 'Windows\Temp\OSDApps'
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            $manifest = [pscustomobject]@{ SchemaVersion='1.0'; StagedAt=''; Apps=@() }
            $manifest | ConvertTo-Json | Set-Content (Join-Path $stage 'DeviceManifest.json')

            Mock Get-OSDAppCachePath { throw "No volume with label 'OSDCloud' was found." }
            Mock Resolve-OSDAppWindowsPath { return $root }
            Mock Get-OSDAppConfiguration { return [pscustomobject]@{ CatalogUri='https://example.org/catalog.json' } }
            Mock Sync-OSDAppCache {}
            Mock Copy-OSDAppContent {}
            Mock Set-OSDAppManifestRuntimeConfiguration { param($Manifest) return $Manifest }
            Mock Add-OSDAppSetupComplete {}

            $result = Add-OSDApp -Name 'NotepadPlusPlus' -WindowsPath $root
            $result.CachePath | Should -Be (Join-Path $root 'Windows\Temp\OSDApps\RepositoryCache')
            Should -Invoke Sync-OSDAppCache -Exactly 1 -ParameterFilter {
                $CachePath -eq (Join-Path $root 'Windows\Temp\OSDApps\RepositoryCache')
            }
            Should -Invoke Copy-OSDAppContent -Exactly 1
        }
    }

    It 'returns no entries rather than throwing when the USB cache is missing' {
        InModuleScope OSDApps {
            Mock Get-OSDAppCachePath { throw "No volume with label 'OSDCloud' was found." }
            { @(Get-OSDAppCache) } | Should -Not -Throw
            @(Get-OSDAppCache).Count | Should -Be 0
        }
    }
}
