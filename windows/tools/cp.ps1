# Copy files or directories (Linux cp style)
param(
    [Parameter(Position = 0)]
    [string]$Source,
    [Parameter(Position = 1)]
    [string]$Destination,
    [switch]$r,
    [switch]$f
)

if (-not $Source -or -not $Destination) {
    Write-Host "Usage: cp [-r] [-f] SOURCE DEST"
    exit 2
}

try {
    Copy-Item -Path $Source -Destination $Destination -Recurse:$r -Force:$f -ErrorAction Stop
    exit 0
} catch {
    Write-Host "cp: $($_.Exception.Message)"
    exit 1
}
