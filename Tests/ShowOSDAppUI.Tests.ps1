Describe 'Show-OSDAppUI MVP - staging adapter' {
    BeforeAll {
        $script:root = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $script:root 'OSDApps.psd1') -Force
    }

    It 'exports the public UI command but does not load GUI assemblies at module import' {
        Get-Command Show-OSDAppUI -Module OSDApps | Should -Not -BeNullOrEmpty
    }

    It 'stages repository apps as a single P1 transaction with offline refresh disabled' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            Mock Resolve-OSDAppWindowsPath { 'C:\OfflineWindows' }
            Mock Add-OSDApp {}
            Mock Get-OSDAppUIStagedIds { 'AppA'; 'AppB' }

            $apps = @(
                [pscustomobject]@{ Id='AppA';Source='Repository' },
                [pscustomobject]@{ Id='AppB';Source='Repository' }
            )
            $result = Invoke-OSDAppUIStage -Applications $apps -WindowsPath 'C:\OfflineWindows' -Offline

            @($result.Requested) | Should -Be @('AppA','AppB')
            $result.Offline | Should -BeTrue
            Should -Invoke Add-OSDApp -Exactly 1 -ParameterFilter {
                @($Name).Count -eq 2 -and 'AppA' -in $Name -and 'AppB' -in $Name -and
                [bool]$SkipCacheRefresh -and $WindowsPath -eq 'C:\OfflineWindows'
            }
        }
    }

    It 'invokes built-in cmdlets and stages the repository batch after them' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            Mock Resolve-OSDAppWindowsPath { 'C:\OfflineWindows' }
            Mock Add-OSDAppMicrosoftTeams {}
            Mock Add-OSDApp {}
            Mock Get-OSDAppUIStagedIds { 'MicrosoftTeams'; 'AppA' }

            $apps = @(
                [pscustomobject]@{ Id='MicrosoftTeams';Source='BuiltIn' },
                [pscustomobject]@{ Id='AppA';Source='Repository' }
            )
            Invoke-OSDAppUIStage -Applications $apps -WindowsPath 'C:\OfflineWindows' | Out-Null

            Should -Invoke Add-OSDAppMicrosoftTeams -Exactly 1
            Should -Invoke Add-OSDApp -Exactly 1 -ParameterFilter { @($Name).Count -eq 1 -and $Name[0] -eq 'AppA' }
        }
    }

    It 'rejects unsupported or duplicate application IDs before staging' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $true }
            Mock Resolve-OSDAppWindowsPath { 'C:\OfflineWindows' }
            Mock Add-OSDApp {}
            $duplicate = @(
                [pscustomobject]@{ Id='AppA';Source='Repository' },
                [pscustomobject]@{ Id='appa';Source='Repository' }
            )
            { Invoke-OSDAppUIStage -Applications $duplicate -WindowsPath 'C:\OfflineWindows' } |
                Should -Throw '*selected multiple times*'

            $traversal = @([pscustomobject]@{ Id='../escape'; Source='Repository' })
            { Invoke-OSDAppUIStage -Applications $traversal -WindowsPath 'C:\OfflineWindows' } |
                Should -Throw '*Invalid application ID*'

            Should -Invoke Add-OSDApp -Exactly 0
        }
    }

    It 'refuses staging from full Windows in preview mode' {
        InModuleScope OSDApps {
            Mock Test-OSDAppWinPE { $false }
            Mock Add-OSDApp {}
            { Invoke-OSDAppUIStage -Applications @([pscustomobject]@{Id='AppA';Source='Repository'}) -WindowsPath 'C:\OfflineWindows' } |
                Should -Throw '*supported in WinPE*'
            Should -Invoke Add-OSDApp -Exactly 0
        }
    }

    It 'reads an existing manifest queue without mutating it' {
        InModuleScope OSDApps {
            $windows = Join-Path $TestDrive 'WindowsDisk'
            $folder = Join-Path $windows 'Windows\Temp\OSDApps'
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
            $manifestPath = Join-Path $folder 'DeviceManifest.json'
            '{"Apps":[{"Id":"AppA"},{"Id":"MicrosoftTeams"}]}' |
                Set-Content -LiteralPath $manifestPath -Encoding UTF8

            @(Get-OSDAppUIStagedIds -WindowsPath $windows) | Should -Be @('AppA','MicrosoftTeams')
            (Get-Content -LiteralPath $manifestPath -Raw) | Should -Match '"MicrosoftTeams"'
        }
    }
}
