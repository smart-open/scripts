# Show memory usage (Linux free style)
param(
    [switch]$h,
    [switch]$m
)

$os = Get-CimInstance Win32_OperatingSystem
$total = $os.TotalVisibleMemorySize * 1KB
$free = $os.FreePhysicalMemory * 1KB
$used = $total - $free

$pageTotal = $os.TotalVirtualMemorySize * 1KB
$pageFree = $os.FreeVirtualMemory * 1KB
$pageUsed = $pageTotal - $pageFree

function Format-Size($bytes) {
    if ($bytes -ge 1GB) { "{0:N2}GB" -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { "{0:N2}MB" -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB) { "{0:N2}KB" -f ($bytes / 1KB) }
    else { "$bytes B" }
}

if ($h) {
    $totalFmt = Format-Size $total
    $usedFmt = Format-Size $used
    $freeFmt = Format-Size $free
    $pageTotalFmt = Format-Size $pageTotal
    $pageUsedFmt = Format-Size $pageUsed
    $pageFreeFmt = Format-Size $pageFree
} elseif ($m) {
    $totalFmt = [math]::Round($total / 1MB)
    $usedFmt = [math]::Round($used / 1MB)
    $freeFmt = [math]::Round($free / 1MB)
    $pageTotalFmt = [math]::Round($pageTotal / 1MB)
    $pageUsedFmt = [math]::Round($pageUsed / 1MB)
    $pageFreeFmt = [math]::Round($pageFree / 1MB)
} else {
    $totalFmt = [math]::Round($total / 1KB)
    $usedFmt = [math]::Round($used / 1KB)
    $freeFmt = [math]::Round($free / 1KB)
    $pageTotalFmt = [math]::Round($pageTotal / 1KB)
    $pageUsedFmt = [math]::Round($pageUsed / 1KB)
    $pageFreeFmt = [math]::Round($pageFree / 1KB)
}

$result = @(
    [PSCustomObject]@{
        Type = "Mem"
        Total = $totalFmt
        Used = $usedFmt
        Free = $freeFmt
    },
    [PSCustomObject]@{
        Type = "Swap"
        Total = $pageTotalFmt
        Used = $pageUsedFmt
        Free = $pageFreeFmt
    }
)

$result | Format-Table -AutoSize