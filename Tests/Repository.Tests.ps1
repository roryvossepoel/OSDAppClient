$moduleRoot = Split-Path -Path $PSScriptRoot -Parent
$manifestPath = Join-Path $moduleRoot 'OSDApps.psd1'

Describe 'Repository authoring and validation' {
    BeforeAll {
        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        Import-Module $manifestPath -Force
    }

    BeforeEach {
        $script:testRoot = Join-Path $TestDrive 'RepositoryTest'
        $script:source = Join-Path $script:testRoot 'Source'
        $script:build = Join-Path $script:testRoot 'Build'
        $script:repository = Join-Path $script:testRoot 'Repository'
        New-Item -ItemType Directory -Path $script:source -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:source 'Install.ps1') -Value 'exit 0' -Encoding UTF8
    }

    It 'creates a valid repository package end to end' {
        New-OSDAppRepository -Path $script:repository | Out-Null
        $package = New-OSDAppPackage -Id ExampleApp -Version 1.0.0 -SourcePath $script:source -OutputPath $script:build
        Add-OSDAppPackage -Id ExampleApp -DisplayName 'Example App' -Version 1.0.0 -Architecture x64 -PackagePath $package.PackagePath -RepositoryPath $script:repository | Out-Null

        $result = @(Test-OSDAppRepository -RepositoryPath $script:repository)

        $result.Count | Should -Be 1
        $result[0].Valid | Should -BeTrue
        $result[0].HashValid | Should -BeTrue
        $result[0].PackageValid | Should -BeTrue
        $result[0].SuccessCodesValid | Should -BeTrue
        $result[0].ArchiveDefinitionValid | Should -BeTrue
        $result[0].Orphaned | Should -BeFalse
    }

    It 'detects an orphaned manifest' {
        New-OSDAppRepository -Path $script:repository | Out-Null
        $orphan = Join-Path $script:repository 'Apps\Orphan\1.0.0\x64'
        New-Item -ItemType Directory -Path $orphan -Force | Out-Null
        @{
            SchemaVersion = 1
            Id = 'Orphan'
            DisplayName = 'Orphan'
            Version = '1.0.0'
            Architecture = 'x64'
            SuccessCodes = @(0)
            Archive = @{ FileName='Package.zip'; Sha256=('0' * 64) }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $orphan 'manifest.json') -Encoding UTF8

        $result = @(Test-OSDAppRepository -RepositoryPath $script:repository)
        @($result | Where-Object Orphaned).Count | Should -Be 1
    }
}
