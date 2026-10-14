# Print route packets take to network host (Linux traceroute style)
param(
    [Parameter(Position = 0)]
    [string]$Hostname,
    [Parameter(Position = 1)]
    [int]$MaxHops = 30
)

if (-not $Hostname) {
    Write-Host "Usage: traceroute HOST [MaxHops]"
    exit 2
}

try {
    $target = [System.Net.Dns]::GetHostEntry($Hostname).AddressList[0].IPAddressToString
} catch {
    $target = $Hostname
}

Write-Host "traceroute to $Hostname ($target), $MaxHops hops max"

for ($ttl = 1; $ttl -le $MaxHops; $ttl++) {
    try {
        $ping = Test-Connection -ComputerName $Hostname -Count 1 -TimeToLive $ttl -ErrorAction Stop
        # Windows PowerShell 5.1: ResponseTime / PowerShell 7: Latency
        $time = if ($ping.PSObject.Properties['ResponseTime']) { $ping.ResponseTime } else { $ping.Latency }
        $addr = $ping.ProtocolAddress
        Write-Output ("{0,2}  {1,6} ms  {2}" -f $ttl, $time, $addr)
        if ($addr -eq $target) { break }
    } catch {
        Write-Output ("{0,2}  * * *" -f $ttl)
    }
}
