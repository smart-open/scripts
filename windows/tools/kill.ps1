# Kill processes (Linux kill style)
param(
    [Parameter(Position = 0)]
    [string]$Id,
    [int]$Signal = 9
)

if (-not $Id) {
    Write-Host "Usage: kill [-Signal N] PID"
    exit 2
}

try {
    $proc = Get-Process -Id $Id -ErrorAction Stop
    if ($Signal -eq 9) {
        $proc.Kill()
        Write-Host "Process $Id killed (SIGKILL)"
    } else {
        Stop-Process -Id $Id -Force
        Write-Host "Process $Id terminated"
    }
    exit 0
} catch {
    Write-Host "kill: process $Id not found"
    exit 1
}
