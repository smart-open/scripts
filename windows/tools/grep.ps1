# Search text in files or piped input (Linux grep style)
param(
    [Parameter(Position = 0)]
    [string]$Pattern,
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)]
    [string[]]$Path,
    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject,
    [switch]$i,
    [switch]$r,
    [switch]$n,
    [switch]$v,
    [switch]$l,
    [switch]$c,
    [switch]$w,
    [switch]$E
)

begin {
    $script:usage = @"
Usage: grep [OPTIONS] PATTERN [FILE...]
       <command> | grep [OPTIONS] PATTERN

Options:
  -i   ignore case
  -r   recursive (when FILE is a directory)
  -n   print line numbers
  -v   select non-matching lines
  -l   print only names of files containing matches
  -c   print only a count of matching lines per file
  -w   match whole words
  -E   extended regex (regex is always enabled, accepted for compatibility)

Examples:
  grep "error" app.log
  grep -i -n "error" *.log
  grep -r -n "TODO" .
  cat app.log | grep -v "DEBUG"
  ps | grep chrome

Exit code: 0 = match found, 1 = no match, 2 = usage error
"@

    # items received from the pipeline (empty when called with files only)
    $script:piped = @()

    function Get-DisplayName {
        param([string]$FullPath)
        $cwd = (Get-Location).Path.TrimEnd('\')
        if ($FullPath.StartsWith($cwd, [System.StringComparison]::OrdinalIgnoreCase)) {
            $rel = $FullPath.Substring($cwd.Length).TrimStart('\')
            if ($rel) { return $rel }
        }
        return $FullPath
    }

    function Write-Hits {
        param([object[]]$Hits, [string]$Prefix, [switch]$Numbered)
        foreach ($h in $Hits) {
            if ($Numbered) {
                Write-Output "$Prefix$($h.Number):$($h.Text)"
            } else {
                Write-Output "$Prefix$($h.Text)"
            }
        }
    }
}

process {
    if ($InputObject) { $script:piped += $InputObject }
}

end {
    if ([string]::IsNullOrEmpty($Pattern)) {
        Write-Host $script:usage
        exit 2
    }

    # -w wraps the pattern with word boundaries; -E needs no conversion (regex is default)
    if ($w) { $Pattern = "\b(?:$Pattern)\b" }

    $regex = $Pattern
    $caseSensitive = -not $i
    $found = $false

    function Test-Line {
        param([string]$Line, [string]$Regex, [bool]$CaseSensitive, [bool]$Invert)
        $hit = if ($CaseSensitive) { $Line -cmatch $Regex } else { $Line -imatch $Regex }
        if ($Invert) { $hit = -not $hit }
        return $hit
    }

    # --------------------------------------------------------------------
    # Pipeline mode: cat file | grep ... / ps | grep ...
    # --------------------------------------------------------------------
    if ($script:piped.Count -gt 0) {
        $hits = @()
        $lineNum = 0
        foreach ($line in @($script:piped | Out-String -Stream)) {
            $lineNum++
            if (Test-Line $line $regex $caseSensitive $v) { $hits += [PSCustomObject]@{ Number = $lineNum; Text = $line } }
        }
        if ($hits.Count -gt 0) { $found = $true }

        if ($l) {
            if ($found) { Write-Output "(standard input)" }
        } elseif ($c) {
            Write-Output $hits.Count
        } else {
            Write-Hits $hits -Numbered:$n
        }
        if ($found) { exit 0 } else { exit 1 }
    }

    # --------------------------------------------------------------------
    # File mode
    # --------------------------------------------------------------------
    if (-not $Path -or $Path.Count -eq 0) {
        Write-Host $script:usage
        exit 2
    }

    $files = @()
    foreach ($p in $Path) {
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            $files += (Resolve-Path -LiteralPath $p).Path
        } elseif (Test-Path -LiteralPath $p -PathType Container) {
            $files += @(Get-ChildItem -LiteralPath $p -Recurse:$r -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        } else {
            # wildcards like *.log are not expanded by PowerShell for scripts
            $files += @(Get-ChildItem -Path $p -File -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        }
    }
    $files = @($files | Where-Object { $_ } | Select-Object -Unique)

    if ($files.Count -eq 0) {
        Write-Host "grep: no such file or directory: $($Path -join ', ')"
        exit 2
    }

    $multi = $files.Count -gt 1

    foreach ($file in $files) {
        $display = Get-DisplayName $file
        try {
            $matches = @(Select-String -LiteralPath $file -Pattern $regex -CaseSensitive:$caseSensitive -NotMatch:$v -AllMatches -ErrorAction SilentlyContinue)
        } catch {
            continue
        }
        if ($matches.Count -gt 0) { $found = $true }

        if ($l) {
            if ($matches.Count -gt 0) { Write-Output $display }
            continue
        }
        if ($c) {
            if ($multi) { Write-Output "${display}:$($matches.Count)" } else { Write-Output $matches.Count }
            continue
        }
        $hits = @($matches | ForEach-Object { [PSCustomObject]@{ Number = $_.LineNumber; Text = $_.Line } })
        $prefix = if ($multi) { "${display}:" } else { "" }
        Write-Hits $hits $prefix -Numbered:$n
    }

    if ($found) { exit 0 } else { exit 1 }
}
