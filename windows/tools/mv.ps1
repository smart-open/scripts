# Move files (Linux mv style)
param(
    [Parameter(Position = 0)]
    [string]$Source,
    [Parameter(Position = 1)]
    [string]$Destination,
    [switch]$f
)

if (-not $Source -or -not $Destination) {
    Write-Host "Usage: mv [-f] SOURCE DEST"
    exit 2
}

try {
    Move-Item -Path $Source -Destination $Destination -Force:$f -ErrorAction Stop
    exit 0
} catch {
    Write-Host "mv: $($_.Exception.Message)"
    exit 1
}
