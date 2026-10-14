# Strip filename from path (Linux dirname style)
param(
    [Parameter(Position = 0)]
    [string]$Path
)

if (-not $Path) {
    Write-Host "Usage: dirname PATH"
    exit 2
}

$dir = Split-Path $Path -Parent
if (-not $dir) { $dir = "." }
Write-Output $dir
