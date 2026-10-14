# Show beginning of file or piped input (Linux head style)
param(
    [Parameter(Position = 0)]
    [string]$File,
    [int]$n = 10,
    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject
)

begin { $script:piped = @() }
process { if ($InputObject) { $script:piped += $InputObject } }
end {
    if ($script:piped.Count -gt 0) {
        $script:piped | Select-Object -First $n
        exit 0
    }

    if (-not $File) {
        Write-Host "Usage: head [-n COUNT] [FILE]"
        Write-Host "   or: <command> | head [-n COUNT]"
        exit 2
    }

    try {
        Get-Content -LiteralPath $File -Head $n -ErrorAction Stop
    } catch {
        Write-Host "head: cannot open '$File': $($_.Exception.Message)"
        exit 1
    }
}
