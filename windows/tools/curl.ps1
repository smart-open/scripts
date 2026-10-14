<#
.SYNOPSIS
HTTP client (Linux curl style)
#>

param(
    [Parameter(Position = 0)]
    [string]$Url,
    [string]$Method = "GET",
    [string]$OutFile,
    [string]$Headers
)

if (-not $Url) {
    Write-Host "Usage: curl [-Method GET|POST|...] [-Headers 'K1: V1; K2: V2'] [-OutFile FILE] URL"
    exit 2
}

$params = @{
    Uri = $Url
    Method = $Method
    UseBasicParsing = $true
}

if (-not [string]::IsNullOrEmpty($OutFile)) {
    $params['OutFile'] = $OutFile
}

if (-not [string]::IsNullOrEmpty($Headers)) {
    $headerTable = @{}
    foreach ($entry in ($Headers -split ';')) {
        $kv = $entry -split ':', 2
        if ($kv.Count -eq 2 -and $kv[0].Trim()) {
            $headerTable[$kv[0].Trim()] = $kv[1].Trim()
        }
    }
    if ($headerTable.Count -gt 0) { $params['Headers'] = $headerTable }
}

try {
    $response = Invoke-WebRequest @params
    if ([string]::IsNullOrEmpty($OutFile)) {
        $response.Content
    } else {
        Write-Host "HTTP $Method $Url -> $OutFile"
    }
} catch {
    Write-Host "curl: request failed: $($_.Exception.Message)"
    exit 1
}
