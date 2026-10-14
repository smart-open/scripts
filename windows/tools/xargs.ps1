# Build and execute command lines from piped input (Linux xargs style)
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs,
    [int]$n = 0,
    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject
)

begin { $script:items = @() }
process { if ($null -ne $_) { $script:items += $_ } }
end {
    if (-not $CommandArgs -or $CommandArgs.Count -eq 0) {
        Write-Host "Usage: <command> | xargs [-n N] COMMAND [ARGS...]"
        exit 2
    }

    if ($script:items.Count -eq 0) { exit 0 }

    $exe = $CommandArgs[0]
    $prefixArgs = @()
    if ($CommandArgs.Count -gt 1) { $prefixArgs = @($CommandArgs[1..($CommandArgs.Count - 1)]) }

    function Invoke-Batch {
        param([object[]]$Batch)
        & $exe @prefixArgs @Batch
    }

    if ($n -gt 0) {
        for ($i = 0; $i -lt $script:items.Count; $i += $n) {
            $last = [Math]::Min($i + $n - 1, $script:items.Count - 1)
            Invoke-Batch @($script:items[$i..$last])
        }
    } else {
        Invoke-Batch @($script:items)
    }
}
