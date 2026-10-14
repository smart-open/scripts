# Install Linux-style tools to Windows PATH
$toolsPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")

if ($currentPath -notlike "*$toolsPath*") {
    $newPath = "$currentPath;$toolsPath"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "Added to PATH: $toolsPath"
    Write-Host "Please restart your terminal to use the commands."
} else {
    Write-Host "Already in PATH: $toolsPath"
}

Write-Host ""
Write-Host "Available commands (55 total):"
Write-Host "  File: ls, ll, cat, head, tail, more, less, touch, rm, cp, mv, mkdir,"
Write-Host "        pwd, find, tree, wc, grep, awk, sort, uniq, cut, tr, tee, xargs"
Write-Host "        basename, dirname, realpath, which, open, diff"
Write-Host "  System: df, du, free, uptime, ps, top, htop, kill"
Write-Host "  Network: ip, ifconfig, netstat, ss, dig, nc, traceroute"
Write-Host "  Archive/Web: zip, unzip, wget, curl"
Write-Host "  Other: history, whoami, hostname, date, env, cal"
Write-Host ""
Write-Host "Usage: grep -i -n ""err"" *.log, ifconfig -a, tree -Level 2, etc."