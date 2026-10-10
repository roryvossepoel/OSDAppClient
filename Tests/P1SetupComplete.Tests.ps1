Describe 'P1 SetupComplete coexistence and refresh' {
    BeforeAll {
        $moduleRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force
    }

    It 'preserves third-party commands between OSDApps blocks during repeated staging' {
        InModuleScope OSDApps {
            $winRoot = Join-Path $TestDrive 'OfflineWindows'
            $scripts = Join-Path $winRoot 'Windows\Setup\Scripts'
            New-Item -ItemType Directory -Path $scripts -Force | Out-Null
            $setupPath = Join-Path $scripts 'SetupComplete.cmd'
            @('@echo off','echo existing-before','echo after-script') |
                Set-Content -LiteralPath $setupPath -Encoding ASCII

            Add-OSDAppSetupComplete -WindowsPath $winRoot -Confirm:$false | Out-Null

            $original = [IO.File]::ReadAllText($setupPath)
            $withThirdParty = $original.Replace(
                ':: OSDApps Begin',
                "echo third-party-between-blocks$([Environment]::NewLine):: OSDApps Begin"
            )
            [IO.File]::WriteAllText($setupPath, $withThirdParty, [Text.Encoding]::ASCII)

            Add-OSDAppSetupComplete -WindowsPath $winRoot -Confirm:$false | Out-Null
            Add-OSDAppSetupComplete -WindowsPath $winRoot -Confirm:$false | Out-Null

            $final = [IO.File]::ReadAllText($setupPath)
            $final | Should -Match 'echo existing-before'
            $final | Should -Match 'echo after-script'
            $final | Should -Match 'echo third-party-between-blocks'
            ([regex]::Matches($final, '(?m)^:: OSDApps PreInstall\r?$')).Count | Should -Be 1
            ([regex]::Matches($final, '(?m)^:: OSDApps Begin\r?$')).Count | Should -Be 1
            ([regex]::Matches($final, '(?m)^:: OSDApps End\r?$')).Count | Should -Be 1
        }
    }

    It 'rejects an incomplete OSDApps block instead of adding duplicates' {
        InModuleScope OSDApps {
            $winRoot = Join-Path $TestDrive 'BrokenWindows'
            $scripts = Join-Path $winRoot 'Windows\Setup\Scripts'
            New-Item -ItemType Directory -Path $scripts -Force | Out-Null
            $setupPath = Join-Path $scripts 'SetupComplete.cmd'
            $initial = "@echo off$([Environment]::NewLine):: OSDApps PreInstall$([Environment]::NewLine)echo something"
            [IO.File]::WriteAllText($setupPath, $initial, [Text.Encoding]::ASCII)

            { Add-OSDAppSetupComplete -WindowsPath $winRoot -Confirm:$false } |
                Should -Throw '*without a runner block*'
            [IO.File]::ReadAllText($setupPath) | Should -Be $initial
        }
    }

    It 'does not create directories or scripts when called with WhatIf' {
        InModuleScope OSDApps {
            $winRoot = Join-Path $TestDrive 'WhatIfWindows'
            Add-OSDAppSetupComplete -WindowsPath $winRoot -WhatIf | Out-Null
            (Test-Path -LiteralPath $winRoot) | Should -BeFalse
        }
    }
}
