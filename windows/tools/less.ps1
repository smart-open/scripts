# Page through text (Linux less style, using more)
param(
    [Parameter(Position = 0)]
    [string]$File
)

if (-not $File) {
    Write-Host "Usage: less FILE"
    exit 2
}

try {
    Get-Content -LiteralPath $File -ErrorAction Stop | Out-Host -Paging
} catch {
    Write-Host "less: cannot open '$File': $($_.Exception.Message)"
    exit 1
}
