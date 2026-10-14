<#
.SYNOPSIS
Download files (Linux wget style)
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Url,
    [string]$OutFile
)

if ([string]::IsNullOrEmpty($OutFile)) {
    try {
        $uri = [Uri]$Url
        $leaf = Split-Path $uri.AbsolutePath -Leaf
        if ([string]::IsNullOrEmpty($leaf)) { $leaf = "download.html" }
        $OutFile = $leaf
    } catch {
        $OutFile = (Split-Path $Url -Leaf) -replace '\?.*$', ''
    }
}

try {
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -ErrorAction Stop
    Write-Host "Downloaded: $Url -> $OutFile"
} catch {
    Write-Host "wget: download failed: $($_.Exception.Message)"
    exit 1
}
