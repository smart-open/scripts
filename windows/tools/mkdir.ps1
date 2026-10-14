# Make directories (Linux mkdir style)
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$Path,
    [switch]$p
)

if (-not $Path -or $Path.Count -eq 0) {
    Write-Host "Usage: mkdir [-p] DIR [DIR...]"
    exit 2
}

foreach ($dir in $Path) {
    try {
        New-Item -ItemType Directory -Path $dir -Force:$p -ErrorAction Stop | Out-Null
    } catch {
        Write-Host "mkdir: cannot create '$dir': $($_.Exception.Message)"
        exit 1
    }
}
exit 0
