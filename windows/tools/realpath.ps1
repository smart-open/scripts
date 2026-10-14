# Print resolved path (Linux realpath style)
param(
    [Parameter(Position = 0)]
    [string]$Path
)

if (-not $Path) {
    Write-Host "Usage: realpath PATH"
    exit 2
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "realpath: no such file or directory: $Path"
    exit 1
}

[System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
