Describe 'Custom Office XML syntax-only validation' {
    BeforeAll {
        $moduleRoot = Split-Path -Path $PSScriptRoot -Parent
        Import-Module (Join-Path $moduleRoot 'OSDApps.psd1') -Force
    }

    It 'accepts well-formed XML without interpreting Office product settings' {
        InModuleScope OSDApps {
            $path = Join-Path $TestDrive 'advanced.xml'
            '<Configuration><UnknownVendorSpecificOption Value="anything" /></Configuration>' |
                Set-Content -LiteralPath $path -Encoding UTF8
            Test-OSDAppOfficeConfigurationXml -Path $path | Should -BeTrue
        }
    }

    It 'rejects malformed XML' {
        InModuleScope OSDApps {
            $path = Join-Path $TestDrive 'invalid.xml'
            '<Configuration><Add></Configuration>' | Set-Content -LiteralPath $path -Encoding UTF8
            { Test-OSDAppOfficeConfigurationXml -Path $path } | Should -Throw '*not well-formed*'
        }
    }

    It 'rejects missing files' {
        InModuleScope OSDApps {
            { Test-OSDAppOfficeConfigurationXml -Path (Join-Path $TestDrive 'missing.xml') } |
                Should -Throw '*not found*'
        }
    }

    It 'rejects DTD input to avoid external entity resolution' {
        InModuleScope OSDApps {
            $path = Join-Path $TestDrive 'dtd.xml'
            '<!DOCTYPE Configuration [<!ENTITY x "hi">]><Configuration>&x;</Configuration>' |
                Set-Content -LiteralPath $path -Encoding UTF8
            { Test-OSDAppOfficeConfigurationXml -Path $path } | Should -Throw '*not well-formed*'
        }
    }
}
