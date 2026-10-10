Describe 'Show-OSDAppUI - read-only device inspector' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }

    It 'exports the UI without loading WinForms at module import time' {
        Get-Command Show-OSDAppUI -Module OSDApps | Should -Not -BeNullOrEmpty
        (Get-Command Show-OSDAppUI).Parameters.ContainsKey('WindowsPath') | Should -BeTrue
        (Get-Command Show-OSDAppUI).Parameters.ContainsKey('Offline') | Should -BeTrue
        (Get-Command Show-OSDAppUI).Parameters.ContainsKey('CatalogUri') | Should -BeFalse
    }

    It 'has no staging, unstaging or configuration mutation calls in the UI implementation' {
        $uiSource = Get-Content -LiteralPath (Join-Path $script:root 'Public\Show-OSDAppUI.ps1') -Raw
        $uiSource | Should -Not -Match '(?i)\bInvoke-OSDAppUIApplyChanges\b'
        $uiSource | Should -Not -Match '(?i)\bInvoke-OSDAppUIStage\b'
        $uiSource | Should -Not -Match '(?i)\bRemove-OSDAppStaging\b'
        $uiSource | Should -Not -Match '(?i)\bAdd-OSDApp(?:Microsoft|Adobe|Cisco|Mozilla|Google|\s|$)'
        $uiSource | Should -Not -Match '(?i)\bSet-OSDAppConfiguration\b'
        $uiSource | Should -Not -Match '(?i)\bNew-Item\b'
        $uiSource | Should -Not -Match '(?i)\bSet-Content\b'
        $uiSource | Should -Not -Match '(?i)\bRemove-Item\b'
    }

    It 'read-only snapshot reads a manifest containing built-in and repository apps in order' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'Offline'
            $stage = Join-Path $target 'Windows\Temp\OSDApps'
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            $manifestPath = Join-Path $stage 'DeviceManifest.json'
            $raw = '{"Apps":[{"Id":"MicrosoftTeams","Source":"BuiltIn","DisplayName":"Microsoft Teams","Architecture":"arm64"},{"Id":"NotepadPlusPlus","Source":"Repository","Version":"8.9.8.1","DisplayName":"Notepad++","Architecture":"x64"}]}'
            Set-Content -LiteralPath $manifestPath -Value $raw -Encoding UTF8

            Mock Get-OSDApp { @(
                [pscustomobject]@{ Id='MicrosoftTeams';Source='BuiltIn';DisplayName='Microsoft Teams' },
                [pscustomobject]@{ Id='NotepadPlusPlus';Source='Repository';DisplayName='Notepad++' }
            ) }
            Mock Get-OSDAppCache { }
            Mock Get-OSDAppCachePath { throw 'No USB cache' }
            Mock Add-OSDApp { throw 'MUTATION' }
            Mock Remove-OSDAppStaging { throw 'MUTATION' }

            $snapshot = Get-OSDAppUIReadOnlySnapshot -WindowsPath $target -Offline
            $snapshot.ManifestExists | Should -BeTrue
            @($snapshot.StagedApps.Id) | Should -Be @('MicrosoftTeams','NotepadPlusPlus')
            $snapshot.StagedApps[0].Architecture | Should -Be 'arm64'
            $snapshot.StagedApps[1].Version | Should -Be '8.9.8.1'
            $snapshot.SetupCompleteExists | Should -BeFalse
            (Get-Content -LiteralPath $manifestPath -Raw) | Should -Be ($raw + [Environment]::NewLine)
            Should -Invoke Add-OSDApp -Exactly 0
            Should -Invoke Remove-OSDAppStaging -Exactly 0
        }
    }

    It 'shows empty staging status without creating files when manifest does not exist' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'EmptyTarget'
            New-Item -Path $target -ItemType Directory -Force | Out-Null
            Mock Get-OSDApp { }
            Mock Get-OSDAppCache { }
            Mock Get-OSDAppCachePath { throw 'No cache' }

            $snapshot = Get-OSDAppUIReadOnlySnapshot -WindowsPath $target -Offline
            $snapshot.ManifestExists | Should -BeFalse
            @($snapshot.StagedApps).Count | Should -Be 0
            (Test-Path (Join-Path $target 'Windows')) | Should -BeFalse
        }
    }

    It 'rejects malformed DeviceManifest rather than silently reporting no apps' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'InvalidTarget'
            $stage = Join-Path $target 'Windows\Temp\OSDApps'
            New-Item -ItemType Directory -Path $stage -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Value '{"StagedAt":"2026"}' -Encoding UTF8

            Mock Get-OSDApp { }
            Mock Get-OSDAppCache { }
            Mock Get-OSDAppCachePath { throw 'No cache' }
            { Get-OSDAppUIReadOnlySnapshot -WindowsPath $target -Offline } |
                Should -Throw '*Apps property is missing*'
        }
    }

    It 'lists real cache and offline-device log paths without writing to either' {
        InModuleScope OSDApps {
            $target = Join-Path $TestDrive 'Device'
            $cache = Join-Path $TestDrive 'USB\OSDApps'
            $clientDir = Join-Path $cache 'Logs'
            $runtimeDir = Join-Path $target 'ProgramData\OSDApps\Logs'
            New-Item -ItemType Directory -Path $clientDir,$runtimeDir -Force | Out-Null
            $clientLog = Join-Path $clientDir 'Client.log'
            $runtimeLog = Join-Path $runtimeDir 'Runtime.log'
            'CLIENT ORIGINAL' | Set-Content $clientLog -Encoding UTF8
            'RUNTIME ORIGINAL' | Set-Content $runtimeLog -Encoding UTF8

            Mock Get-OSDApp { }
            Mock Get-OSDAppCache {
                [pscustomobject]@{Id='NotepadPlusPlus';Source='Repository';Valid=$true;SizeMB=6.6}
            }
            $script:FixtureCachePath = $cache
            Mock Get-OSDAppCachePath { $script:FixtureCachePath }
            $snapshot = Get-OSDAppUIReadOnlySnapshot -WindowsPath $target -Offline
            $snapshot.CachePath | Should -Be $cache
            @($snapshot.CacheEntries).Count | Should -Be 1
            @($snapshot.Logs).Count | Should -Be 2
            @($snapshot.Logs.Path) | Should -Contain $clientLog
            @($snapshot.Logs.Path) | Should -Contain $runtimeLog
            (Get-Content $clientLog -Raw) | Should -Match 'CLIENT ORIGINAL'
            (Get-Content $runtimeLog -Raw) | Should -Match 'RUNTIME ORIGINAL'
        }
    }

    It 'formats stored configuration fields but hides installer paths and download URLs' {
        InModuleScope OSDApps {
            $app = [pscustomobject]@{
                Id='Microsoft365Apps';DisplayName='Microsoft 365 Apps';Source='BuiltIn'
                Channel='MonthlyEnterprise';Architecture='x64';Language=@('nl-nl','en-us')
                SharedComputerLicensing=$true
                PackageUri='https://example.org/installer?token=sensitive'
                CommandLine='Do-Not-Surface'
            }
            $details = Format-OSDAppUIStagedDetails -Application $app
            $details | Should -Match 'Channel: MonthlyEnterprise'
            $details | Should -Match 'Language: nl-nl, en-us'
            $details | Should -Match 'SharedComputerLicensing: True'
            $details | Should -Not -Match 'token=sensitive'
            $details | Should -Not -Match 'Do-Not-Surface'
            $details | Should -Match 'does not confirm'
        }
    }

    It 'does not query configured repository online when Get-OSDApp -Offline is used' {
        InModuleScope OSDApps {
            Mock Get-OSDAppConfiguration { [pscustomobject]@{CatalogUri=[uri]'https://example.org/catalog.json'} }
            Mock Get-OSDAppCachePath { throw 'No USB media attached' }
            Mock Get-OSDAppCatalogPackages { throw 'Should not query online' }
            @((Get-OSDApp -Offline) | Where-Object Source -eq 'BuiltIn').Count | Should -Be 6
            Should -Invoke Get-OSDAppCatalogPackages -Exactly 0
        }
    }

    It 'preserves session configuration during snapshot' {
        InModuleScope OSDApps {
            Mock Get-OSDAppConfiguration { [pscustomobject]@{CatalogUri=[uri]'https://example.org/catalog.json'} }
            Mock Get-OSDApp { }
            Mock Get-OSDAppCache { }
            Mock Get-OSDAppCachePath { throw 'No USB media attached' }
            Mock Set-OSDAppConfiguration { throw 'Unexpected configuration mutation' }
            Get-OSDAppUIReadOnlySnapshot -Offline | Out-Null
            Should -Invoke Set-OSDAppConfiguration -Exactly 0
            (Get-OSDAppConfiguration).CatalogUri.AbsoluteUri | Should -Be 'https://example.org/catalog.json'
        }
    }
}
