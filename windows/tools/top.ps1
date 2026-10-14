# Display top processes (Linux top style)
param(
    [int]$n = 15
)

Write-Host "Windows Task Manager - Top $n Processes"
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host ""

$os = Get-CimInstance Win32_OperatingSystem
$cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
$memTotal = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
$memUsed = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 2)

Write-Host "CPU: $cpuLoad%"
Write-Host "Memory: $memUsed GB / $memTotal GB"
Write-Host ""

Get-Process | Sort-Object CPU -Descending | Select-Object -First $n | 
    Select-Object Id, ProcessName, 
        @{Name='CPU';Expression={[math]::Round($_.CPU,1)}},
        @{Name='Memory(MB)';Expression={[math]::Round($_.WorkingSet/1MB,1)}},
        StartTime | Format-Table -AutoSize