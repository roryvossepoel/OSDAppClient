function Save-OSDAppDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri]$Uri,

        [Parameter(Mandatory)]
        [string]$DestinationPath,

        [Parameter(Mandatory)]
        [string]$Activity,

        [int]$ProgressId = 20,

        [int]$ParentProgressId = -1
    )

    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue

    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $client = New-Object System.Net.Http.HttpClient($handler)

    try {
        $response = $client.GetAsync($Uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode()

        $totalBytes = $response.Content.Headers.ContentLength
        $source = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()

        $directory = Split-Path -Path $DestinationPath -Parent
        if ($directory) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        $target = New-Object System.IO.FileStream(
            $DestinationPath,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )

        try {
            $buffer = New-Object byte[] (1024 * 1024)
            [int64]$downloaded = 0
            $lastPercent = -1

            while (($read = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $target.Write($buffer, 0, $read)
                $downloaded += $read

                $downloadedMB = [math]::Round($downloaded / 1MB, 1)

                if ($totalBytes -and $totalBytes -gt 0) {
                    $percent = [math]::Min(100, [int](($downloaded / $totalBytes) * 100))
                    if ($percent -ne $lastPercent) {
                        $totalMB = [math]::Round($totalBytes / 1MB, 1)
                        Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $Activity -Status "$downloadedMB MB / $totalMB MB" -PercentComplete $percent
                        $lastPercent = $percent
                    }
                }
                else {
                    Write-Progress -Id $ProgressId -ParentId $ParentProgressId -Activity $Activity -Status "$downloadedMB MB downloaded" -PercentComplete -1
                }
            }
        }
        finally {
            $target.Dispose()
            $source.Dispose()
            Write-Progress -Id $ProgressId -Activity $Activity -Completed
        }
    }
    finally {
        $client.Dispose()
        $handler.Dispose()
    }

    Get-Item -LiteralPath $DestinationPath
}
