Describe 'Built-in metadata' {
    BeforeAll {
        $script:moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        $script:manifestPath = Join-Path $script:moduleRoot 'OSDApps.psd1'
        $script:metadataPath = Join-Path $script:moduleRoot 'metadata\builtins.json'

        Remove-Module OSDApps -Force -ErrorAction SilentlyContinue
        Import-Module $script:manifestPath -Force

        $script:metadata = Get-Content -LiteralPath $script:metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    It 'uses the supported metadata schema' {
        $script:metadata.SchemaVersion | Should -Be 1
        $script:metadata.Project | Should -Be 'OSDApps'
    }

    It 'contains unique built-in application ids' {
        $ids = @($script:metadata.Applications.Id)
        @($ids | Select-Object -Unique).Count | Should -Be $ids.Count
    }

    It 'contains required fields for every built-in' {
        foreach ($app in @($script:metadata.Applications)) {
            $app.Id | Should -Not -BeNullOrEmpty
            $app.DisplayName | Should -Not -BeNullOrEmpty
            $app.Source | Should -Be 'BuiltIn'
            $app.Vendor | Should -Not -BeNullOrEmpty
            $app.Acquisition | Should -Not -BeNullOrEmpty
            $app.SyncPhase | Should -Be 'FullWindowsPreInstall'
            $app.AddCommand | Should -Not -BeNullOrEmpty
            $app.SyncCommand | Should -Not -BeNullOrEmpty
            @($app.Architectures).Count | Should -BeGreaterThan 0
            $app.CachePath | Should -Not -BeNullOrEmpty
            $app.IconUrl | Should -Match '^https://'
        }
    }

    It 'maps every metadata command to an exported function' {
        $exported = @(Get-Command -Module OSDApps -CommandType Function | Select-Object -ExpandProperty Name)

        foreach ($app in @($script:metadata.Applications)) {
            $app.AddCommand | Should -BeIn $exported
            $app.SyncCommand | Should -BeIn $exported
        }
    }

    It 'contains every exported built-in Add command' {
        $exportedBuiltIns = @(
            Get-Command -Module OSDApps -CommandType Function |
                Select-Object -ExpandProperty Name |
                Where-Object {
                    $_ -like 'Add-OSDApp*' -and
                    $_ -notin @('Add-OSDApp','Add-OSDAppPackage')
                } |
                ForEach-Object { $_ -replace '^Add-OSDApp','' } |
                Sort-Object
        )

        $metadataIds = @($script:metadata.Applications.Id | Sort-Object)

        Compare-Object -ReferenceObject $exportedBuiltIns -DifferenceObject $metadataIds |
            Should -BeNullOrEmpty
    }
}
