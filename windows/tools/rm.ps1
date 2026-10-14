# Remove files or directories (Linux rm style)
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Path,
    [switch]$r,
    [switch]$f,
    [switch]$i
)

if (-not $Path -or $Path.Count -eq 0) {
    Write-Host "Usage: rm [-r] [-f] [-i] FILE [FILE...]"
    exit 2
}

try {
    Remove-Item -Path $Path -Recurse:$r -Force:$f -Confirm:$i -ErrorAction Stop
    exit 0
} catch {
    Write-Host "rm: $($_.Exception.Message)"
    exit 1
}
