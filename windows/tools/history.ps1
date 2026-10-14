# Show command history (Linux history style)
param(
    [int]$n
)

$history = Get-History
if ($n -gt 0) {
    $history = $history | Select-Object -Last $n
}

$history | ForEach-Object {
    Write-Output ("{0,5}  {1}" -f $_.Id, $_.CommandLine)
}