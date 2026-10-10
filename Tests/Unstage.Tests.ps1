Describe 'Remove-OSDAppStaging and GUI Apply Changes' {
    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force

        function global:New-OSDAppsStagingFixture {
            param([string]$Root)
            $stage = Join-Path $Root 'Windows\Temp\OSDApps'
            $scripts = Join-Path $Root 'Windows\Setup\Scripts'
            New-Item -ItemType Directory -Path $stage,$scripts -Force | Out-Null
            $pkgA = Join-Path $stage 'Packages\NotepadPlusPlus'
            $pkgB = Join-Path $stage 'BuiltIn\MicrosoftTeams'
            New-Item -ItemType Directory -Path $pkgA,$pkgB -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $pkgA 'Package.zip') -Value 'package' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $pkgB 'teamsbootstrapper.exe') -Value 'teams' -Encoding ASCII
            @{
                SchemaVersion='1.0'
                StagedAt='2026-10-10T10:00:00Z'
                Runtime=@{CleanupMode='Never'}
                Apps=@(
                    @{Id='MicrosoftTeams';Source='BuiltIn';Type='MicrosoftTeamsBootstrapper'},
                    @{Id='NotepadPlusPlus';Source='Repository';Type='RepositoryPackage'}
                )
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $stage 'DeviceManifest.json') -Encoding UTF8
            Add-OSDAppSetupComplete -WindowsPath $Root -Confirm:$false | Out-Null
            return [pscustomobject]@{
                Manifest=Join-Path $stage 'DeviceManifest.json'
                Setup=Join-Path $scripts 'SetupComplete.cmd'
                Stage=$stage
            }
        }
    }
    AfterAll {
        Remove-Item Function:\New-OSDAppsStagingFixture -ErrorAction SilentlyContinue
    }

    It 'removes Teams staging while keeping Notepad++, manifest and USB cache' {
        InModuleScope OSDApps {
            $root=Join-Path $TestDrive 'SafeWindows'
            $fixture=New-OSDAppsStagingFixture -Root $root
            $cache=Join-Path $TestDrive 'USB\OSDApps'
            New-Item -Path (Join-Path $cache 'BuiltIn\MicrosoftTeams') -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $cache 'BuiltIn\MicrosoftTeams\teams.msix') -Value 'cache' -Encoding ASCII
            Mock Test-OSDAppWinPE {$false}
            Mock Get-OSDAppUITestWindowsPath {$root}

            $result=Remove-OSDAppStaging -Name MicrosoftTeams -TestMode -Confirm:$false
            @($result.Removed) | Should -Be @('MicrosoftTeams')
            $manifest=Get-Content -LiteralPath $fixture.Manifest -Raw | ConvertFrom-Json
            @($manifest.Apps.Id) | Should -Be @('NotepadPlusPlus')
            (Test-Path (Join-Path $fixture.Stage 'BuiltIn\MicrosoftTeams')) | Should -BeFalse
            (Test-Path (Join-Path $fixture.Stage 'Packages\NotepadPlusPlus\Package.zip')) | Should -BeTrue
            (Test-Path (Join-Path $cache 'BuiltIn\MicrosoftTeams\teams.msix')) | Should -BeTrue
            (Get-Content -LiteralPath $fixture.Setup -Raw) | Should -Match ':: OSDApps Begin'
        }
    }

    It 'removes the last app and only OSDApps commands from SetupComplete' {
        InModuleScope OSDApps {
            $root=Join-Path $TestDrive 'WindowsWithThirdPartySetup'
            $fixture=New-OSDAppsStagingFixture -Root $root
            $original=Get-Content -LiteralPath $fixture.Setup -Raw
            $external= $original.Replace(':: OSDApps Begin',("echo external-between-blocks" + [Environment]::NewLine + ':: OSDApps Begin'))
            [IO.File]::WriteAllText($fixture.Setup,$external,[Text.Encoding]::ASCII)
            Mock Test-OSDAppWinPE {$false}
            Mock Get-OSDAppUITestWindowsPath {$root}

            Remove-OSDAppStaging -Name @('MicrosoftTeams','NotepadPlusPlus') -TestMode -Confirm:$false | Out-Null

            (Test-Path -LiteralPath $fixture.Manifest) | Should -BeFalse
            (Test-Path (Join-Path $fixture.Stage 'Packages\NotepadPlusPlus')) | Should -BeFalse
            (Test-Path (Join-Path $fixture.Stage 'BuiltIn\MicrosoftTeams')) | Should -BeFalse
            (Test-Path (Join-Path $fixture.Stage 'Invoke-OSDAppRunner.ps1')) | Should -BeFalse
            (Test-Path (Join-Path $fixture.Stage 'Invoke-OSDAppPreInstall.ps1')) | Should -BeFalse
            $setup=Get-Content -LiteralPath $fixture.Setup -Raw
            $setup | Should -Match 'echo external-between-blocks'
            $setup | Should -Not -Match ':: OSDApps Begin'
            $setup | Should -Not -Match ':: OSDApps PreInstall'
            $setup | Should -Not -Match ':: OSDApps End'
        }
    }

    It 'does not touch files in -WhatIf mode' {
        InModuleScope OSDApps {
            $root=Join-Path $TestDrive 'WhatIfRoot'
            $fixture=New-OSDAppsStagingFixture -Root $root
            $original=Get-Content -LiteralPath $fixture.Manifest -Raw
            Mock Test-OSDAppWinPE {$false}
            Mock Get-OSDAppUITestWindowsPath {$root}

            Remove-OSDAppStaging -Name @('MicrosoftTeams','NotepadPlusPlus') -TestMode -WhatIf | Out-Null
            (Get-Content -LiteralPath $fixture.Manifest -Raw) | Should -Be $original
            (Test-Path (Join-Path $fixture.Stage 'BuiltIn\MicrosoftTeams')) | Should -BeTrue
            (Get-Content -LiteralPath $fixture.Setup -Raw) | Should -Match ':: OSDApps End'
        }
    }

    It 'blocks full-Windows unstaging without TestMode and rejects traversal' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE {$false}
            {Remove-OSDAppStaging -Name MicrosoftTeams -WindowsPath 'C:\' -Confirm:$false} |
                Should -Throw '*requires -TestMode*'
            $root=Join-Path $TestDrive 'InvalidId'
            $fixture=New-OSDAppsStagingFixture -Root $root
            Mock Get-OSDAppUITestWindowsPath {$root}
            {Remove-OSDAppStaging -Name '../Windows' -TestMode -Confirm:$false} |
                Should -Throw '*Invalid application ID*'
            (Test-Path $fixture.Manifest) | Should -BeTrue
        }
    }

    It 'preserves the queue if SetupComplete is malformed on last-app removal' {
        InModuleScope OSDApps {
            $root=Join-Path $TestDrive 'BrokenSetup'
            $fixture=New-OSDAppsStagingFixture -Root $root
            [IO.File]::WriteAllText($fixture.Setup,':: OSDApps Begin',[Text.Encoding]::ASCII)
            Mock Test-OSDAppWinPE {$false}
            Mock Get-OSDAppUITestWindowsPath {$root}
            {Remove-OSDAppStaging -Name @('MicrosoftTeams','NotepadPlusPlus') -TestMode -Confirm:$false} |
                Should -Throw '*missing or duplicate OSDApps markers*'
            (Test-Path -LiteralPath $fixture.Manifest) | Should -BeTrue
        }
    }

    It 'applies an unchecked app removal without restaging already selected apps' {
        InModuleScope OSDApps {
            Mock Get-OSDAppUIStagedIds { 'MicrosoftTeams'; 'NotepadPlusPlus' }
            Mock Invoke-OSDAppUIStage { throw 'Should not restage existing app' }
            Mock Remove-OSDAppStaging { }
            $apps=@([pscustomobject]@{Id='NotepadPlusPlus';Source='Repository'})
            $result=Invoke-OSDAppUIApplyChanges -Applications $apps -WindowsPath 'C:\Safe' -TestMode

            @($result.Removed) | Should -Be @('MicrosoftTeams')
            Should -Invoke Invoke-OSDAppUIStage -Exactly 0
            Should -Invoke Remove-OSDAppStaging -Exactly 1 -ParameterFilter {
                [bool]$TestMode -and 'MicrosoftTeams' -in $Name
            }
        }
    }
}
