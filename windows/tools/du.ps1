# Disk usage (Linux du style)
param(
    [string]$Path = ".",
    [switch]$h,
    [switch]$s,
    [int]$d = 2
)

function Format-Size($bytes) {
    if ($null -eq $bytes) { return "0B" }
    if ($bytes -ge 1GB) { "{0:N2}GB" -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { "{0:N2}MB" -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB) { "{0:N2}KB" -f ($bytes / 1KB) }
    else { "$bytes B" }
}

if ($s) {
    $total = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    if ($null -eq $total) { $total = 0 }
    if ($h) { Write-Output "$(Format-Size $total) $Path" }
    else { Write-Output "$total $Path" }
} else {
    Get-ChildItem -Path $Path -Directory -Depth $d -ErrorAction SilentlyContinue | ForEach-Object {
        $size = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        if ($null -eq $size) { $size = 0 }
        if ($h) { Write-Output "$(Format-Size $size) $($_.FullName)" }
        else { Write-Output "$size $($_.FullName)" }
    }
}