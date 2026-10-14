<#
.SYNOPSIS
Create empty file or update timestamp (Linux touch style)
#>

param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$File
)

if (-not $File -or $File.Count -eq 0) {
    Write-Host "Usage: touch FILE [FILE...]"
    exit 2
}

foreach ($f in $File) {
    try {
        if (Test-Path -LiteralPath $f) {
            (Get-Item -LiteralPath $f).LastWriteTime = Get-Date
        } else {
            New-Item -ItemType File -Path $f -Force -ErrorAction Stop | Out-Null
        }
    } catch {
        Write-Host "touch: cannot touch '$f': $($_.Exception.Message)"
        exit 1
    }
}
exit 0
