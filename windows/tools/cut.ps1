# Extract fields from each line (Linux cut style)
param(
    [Parameter(Position = 0)]
    [string]$File,
    [string]$d = "`t",
    [string]$f,
    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject
)

begin { $script:piped = @() }
process { if ($InputObject) { $script:piped += $InputObject } }
end {
    if (-not $f) {
        Write-Host "Usage: cut -d DELIM -f LIST [FILE]"
        Write-Host "   or: <command> | cut -d DELIM -f LIST"
        exit 2
    }

    # field list: 1,3,5-7
    $fields = @()
    foreach ($part in ($f -split ",")) {
        if ($part -match "^(\d+)-(\d+)$") {
            $fields += ([int]$matches[1] - 1)..([int]$matches[2] - 1)
        } elseif ($part -match "^\d+$") {
            $fields += [int]$part - 1
        } else {
            Write-Host "cut: invalid field list '$f'"
            exit 2
        }
    }

    if ($script:piped.Count -gt 0) {
        $lines = @($script:piped)
    } elseif ($File) {
        try {
            $lines = @(Get-Content -LiteralPath $File -ErrorAction Stop)
        } catch {
            Write-Host "cut: cannot open '$File': $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "Usage: cut -d DELIM -f LIST [FILE]"
        exit 2
    }

    foreach ($line in $lines) {
        $parts = $line -split [regex]::Escape($d)
        $selected = $fields | Where-Object { $_ -ge 0 -and $_ -lt $parts.Length } | ForEach-Object { $parts[$_] }
        Write-Output ($selected -join $d)
    }
}
