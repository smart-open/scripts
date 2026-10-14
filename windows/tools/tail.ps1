# Show end of file or piped input (Linux tail style)
param(
    [Parameter(Position = 0)]
    [string]$File,
    [int]$n = 10,
    [switch]$f,
    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject
)

begin { $script:piped = @() }
process { if ($InputObject) { $script:piped += $InputObject } }
end {
    if ($script:piped.Count -gt 0) {
        if ($f) {
            Write-Host "tail: -f requires a file"
            exit 2
        }
        $script:piped | Select-Object -Last $n
        exit 0
    }

    if (-not $File) {
        Write-Host "Usage: tail [-n COUNT] [-f] FILE"
        Write-Host "   or: <command> | tail [-n COUNT]"
        exit 2
    }

    try {
        if ($f) {
            Get-Content -LiteralPath $File -Tail $n -Wait -ErrorAction Stop
        } else {
            Get-Content -LiteralPath $File -Tail $n -ErrorAction Stop
        }
    } catch {
        Write-Host "tail: cannot open '$File': $($_.Exception.Message)"
        exit 1
    }
}
