<#
.SYNOPSIS
Page through text (Linux more style)
#>

param(
    [Parameter(Position = 0)]
    [string]$File
)

if (-not $File) {
    Write-Host "Usage: more FILE"
    exit 2
}

try {
    Get-Content -LiteralPath $File -ErrorAction Stop | Out-Host -Paging
} catch {
    Write-Host "more: cannot open '$File': $($_.Exception.Message)"
    exit 1
}
