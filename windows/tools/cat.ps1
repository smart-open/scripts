# Display file contents (Linux cat style)
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$File,
    [switch]$n
)

if (-not $File -or $File.Count -eq 0) {
    Write-Host "Usage: cat [-n] FILE [FILE...]"
    exit 2
}

foreach ($f in $File) {
    try {
        $lines = @(Get-Content -LiteralPath $f -ErrorAction Stop)
    } catch {
        Write-Host "cat: cannot open '$f': $($_.Exception.Message)"
        exit 1
    }
    if ($n) {
        $i = 1
        foreach ($line in $lines) {
            Write-Output ("{0,6}`t{1}" -f $i++, $line)
        }
    } else {
        Write-Output $lines
    }
}
