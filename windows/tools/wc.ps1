# Count lines, words, characters (Linux wc style)
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$File,
    [switch]$l,
    [switch]$w,
    [switch]$c,
    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject
)

begin { $script:piped = @() }
process { if ($InputObject) { $script:piped += $InputObject } }
end {
    $items = @()
    if ($script:piped.Count -gt 0) {
        $items += , @("", @($script:piped))
    } elseif ($File -and $File.Count -gt 0) {
        foreach ($f in $File) {
            try {
                $items += , @($f, @(Get-Content -LiteralPath $f -ErrorAction Stop))
            } catch {
                Write-Host "wc: cannot open '$f': $($_.Exception.Message)"
                exit 1
            }
        }
    } else {
        Write-Host "Usage: wc [-l] [-w] [-c] [FILE...]"
        Write-Host "   or: <command> | wc [-l] [-w] [-c]"
        exit 2
    }

    $showAll = -not ($l -or $w -or $c)
    $multi = $items.Count -gt 1
    $totalL = 0; $totalW = 0; $totalC = 0

    foreach ($item in $items) {
        $label = $item[0]
        $lines = @($item[1])
        $lc = $lines.Count
        $words = ($lines -join " " -split "\s+" | Where-Object { $_ }).Count
        $chars = (($lines -join "`n") + "`n").Length
        $totalL += $lc; $totalW += $words; $totalC += $chars

        $out = ""
        if ($showAll -or $l) { $out += "{0,8}" -f $lc }
        if ($showAll -or $w) { $out += "{0,8}" -f $words }
        if ($showAll -or $c) { $out += "{0,8}" -f $chars }
        if ($label -or $multi) { $out += " $label" }
        Write-Output $out.TrimEnd()
    }

    if ($multi) {
        $out = ""
        if ($showAll -or $l) { $out += "{0,8}" -f $totalL }
        if ($showAll -or $w) { $out += "{0,8}" -f $totalW }
        if ($showAll -or $c) { $out += "{0,8}" -f $totalC }
        Write-Output "$out total"
    }
}
