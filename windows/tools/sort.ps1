# Sort lines from file or piped input (Linux sort style)
param(
    [Parameter(Position = 0)]
    [string]$File,
    [switch]$n,
    [switch]$r,
    [switch]$u,
    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject
)

begin { $script:piped = @() }
process { if ($InputObject) { $script:piped += $InputObject } }
end {
    if ($script:piped.Count -gt 0) {
        $lines = @($script:piped)
    } elseif ($File) {
        try {
            $lines = @(Get-Content -LiteralPath $File -ErrorAction Stop)
        } catch {
            Write-Host "sort: cannot open '$File': $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "Usage: sort [-n] [-r] [-u] [FILE]"
        Write-Host "   or: <command> | sort [-n] [-r] [-u]"
        exit 2
    }

    if ($n) {
        $lines = $lines | Sort-Object {
            $value = 0.0
            [void][double]::TryParse("$_", [ref]$value)
            $value
        } -Descending:$r
    } else {
        $lines = $lines | Sort-Object -Descending:$r
    }

    if ($u) { $lines = $lines | Select-Object -Unique }
    $lines
}
