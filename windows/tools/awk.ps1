# Simple awk-like text processor
param(
    [Parameter(Position = 0)]
    [string]$Script,
    [Parameter(Position = 1)]
    [string]$File,
    [string]$FS = " ",
    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject
)

begin { $script:piped = @() }
process { if ($InputObject) { $script:piped += $InputObject } }
end {
    if ($script:piped.Count -gt 0) {
        $inputData = @($script:piped | Out-String -Stream)
    } elseif ($File) {
        try {
            $inputData = @(Get-Content -LiteralPath $File -ErrorAction Stop)
        } catch {
            Write-Host "awk: cannot open '$File': $($_.Exception.Message)"
            exit 1
        }
    } else {
        Write-Host "Usage: awk '{print `$1}' file.txt"
        Write-Host "   or: cat file.txt | awk '{print `$1, `$2}'"
        Write-Host ""
        Write-Host "Supported: print `$1..`$N, `$0, NF, NR"
        exit 2
    }

    $lineNum = 0
    foreach ($line in $inputData) {
        $lineNum++
        $fields = @($line -split "\s+" | Where-Object { $_ })
        $NF = $fields.Count
        $NR = $lineNum

        $output = $Script
        # translate awk 'print' to PowerShell 'Write-Output'
        $output = $output -replace '\bprint\b', 'Write-Output'
        $output = $output -replace '\$0', "`$line"
        for ($i = 1; $i -le $NF; $i++) {
            $output = $output -replace "\`$$i", "`$(`$fields[$($i-1)])"
        }
        $output = $output -replace 'NF', "`$NF"
        $output = $output -replace 'NR', "`$NR"
        $output = $output -replace '^\s*\{', ''
        $output = $output -replace '\}\s*$', ''

        try {
            Invoke-Expression $output
        } catch {
            Write-Output $line
        }
    }
}
