<#
.SYNOPSIS
Extract zip files (Linux unzip style)
#>

param(
    [Parameter(Position = 0)]
    [string]$File,
    [string]$Destination = "."
)

if (-not $File) {
    Write-Host "Usage: unzip [-Destination DIR] FILE.zip"
    exit 2
}

if (-not (Test-Path -LiteralPath $File)) {
    Write-Host "unzip: cannot find '$File'"
    exit 1
}

try {
    Expand-Archive -Path $File -DestinationPath $Destination -Force -ErrorAction Stop
    Write-Host "Extracted: $File -> $Destination"
    exit 0
} catch {
    Write-Host "unzip: $($_.Exception.Message)"
    exit 1
}
