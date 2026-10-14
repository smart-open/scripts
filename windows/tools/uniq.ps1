# Remove consecutive duplicate lines (Linux uniq style)
param(
    [Parameter(Position = 0)]
    [string]$File,
    [switch]$c,
    [switch]$d,
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
            Write-Host "uniq: cannot open '$File': $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "Usage: uniq [-c] [-d] [-u] [FILE]"
        Write-Host "   or: <command> | uniq [-c] [-d] [-u]"
        exit 2
    }

    $groups = @()
    $prev = $null
    $count = 0
    foreach ($line in $lines) {
        if ($null -ne $prev -and $line -ceq $prev) {
            $count++
        } else {
            if ($null -ne $prev) { $groups += [PSCustomObject]@{ Count = $count; Text = $prev } }
            $prev = $line
            $count = 1
        }
    }
    if ($null -ne $prev) { $groups += [PSCustomObject]@{ Count = $count; Text = $prev } }

    foreach ($g in $groups) {
        $show = if ($d) { $g.Count -gt 1 }
                elseif ($u) { $g.Count -eq 1 }
                else { $true }
        if ($show) {
            if ($c) { Write-Output ("{0,7} {1}" -f $g.Count, $g.Text) }
            else { Write-Output $g.Text }
        }
    }
}
