function Write-OSDAppsClientLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$LogPath,

        [Parameter(Mandatory)]
        [string]$Component,

        [Parameter(Mandatory)]
        [string]$Event,

        [ValidateSet('Debug','Info','Warning','Error')]
        [string]$Level = 'Info',

        [string]$Message,

        [hashtable]$Data,

        [int]$MaxSizeMB = 1,

        [int]$RetainFiles = 3
    )

    $directory = Split-Path -Path $LogPath -Parent
    if ($directory) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if (Test-Path -LiteralPath $LogPath -PathType Leaf) {
        $maxBytes = $MaxSizeMB * 1MB
        $length = (Get-Item -LiteralPath $LogPath).Length

        if ($length -ge $maxBytes) {
            for ($i = $RetainFiles - 1; $i -ge 1; $i--) {
                $source = "$LogPath.$i"
                $target = "$LogPath.$($i + 1)"

                if (Test-Path -LiteralPath $source) {
                    Move-Item -LiteralPath $source -Destination $target -Force
                }
            }

            Move-Item -LiteralPath $LogPath -Destination "$LogPath.1" -Force

            $oldest = "$LogPath.$($RetainFiles + 1)"
            if (Test-Path -LiteralPath $oldest) {
                Remove-Item -LiteralPath $oldest -Force
            }
        }
    }

    $entry = [ordered]@{
        Timestamp = (Get-Date).ToUniversalTime().ToString('o')
        Level     = $Level
        Component = $Component
        Event     = $Event
        Message   = $Message
    }

    if ($Data) {
        $entry.Data = $Data
    }

    ($entry | ConvertTo-Json -Compress -Depth 10) |
        Add-Content -LiteralPath $LogPath -Encoding UTF8
}
