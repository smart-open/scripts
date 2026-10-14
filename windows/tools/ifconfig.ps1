# Show network interfaces (Linux ifconfig style)
param(
    [Parameter(Position = 0)]
    [string]$Interface,
    [switch]$a,
    [switch]$s
)

# Convert prefix length to a dotted netmask (24 -> 255.255.255.0)
function ConvertTo-Netmask {
    param([int]$PrefixLength)
    if ($PrefixLength -le 0) { return "0.0.0.0" }
    if ($PrefixLength -ge 32) { return "255.255.255.255" }
    $mask = [UInt64]([Math]::Pow(2, 32) - [Math]::Pow(2, 32 - $PrefixLength))
    return @(
        [byte](($mask -shr 24) -band 0xFF),
        [byte](($mask -shr 16) -band 0xFF),
        [byte](($mask -shr 8) -band 0xFF),
        [byte]($mask -band 0xFF)
    ) -join "."
}

function Get-BroadcastAddress {
    param([string]$IPAddress, [string]$Netmask)
    try {
        $ip = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
        $mask = [System.Net.IPAddress]::Parse($Netmask).GetAddressBytes()
        $bcast = @()
        for ($i = 0; $i -lt 4; $i++) {
            $bcast += [byte](($ip[$i] -bor (-bnot $mask[$i])) -band 0xFF)
        }
        return ($bcast -join ".")
    } catch {
        return $null
    }
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N1} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

$adapters = @(Get-NetAdapter -ErrorAction SilentlyContinue)

if ($Interface) {
    $adapters = @($adapters | Where-Object {
        $_.Name -like $Interface -or $_.InterfaceDescription -like "*$Interface*"
    })
    if ($adapters.Count -eq 0) {
        Write-Host "ifconfig: interface '$Interface' not found"
        exit 1
    }
}

if (-not $a) {
    $adapters = @($adapters | Where-Object { $_.Status -eq 'Up' })
}

$adapters = @($adapters | Sort-Object ifIndex)

if ($adapters.Count -eq 0) {
    Write-Host "ifconfig: no active interface (use -a to list all)"
    exit 0
}

# ------------------------------------------------------------------------
# -s : short statistics table
# ------------------------------------------------------------------------
if ($s) {
    "{0,-28} {1,12} {2,10} {3,12} {4,10}" -f "IFACE", "RX-BYTES", "RX-PKTS", "TX-BYTES", "TX-PKTS"
    foreach ($ad in $adapters) {
        $stat = Get-NetAdapterStatistics -Name $ad.Name -ErrorAction SilentlyContinue | Select-Object -First 1
        $rxBytes = 0; $txBytes = 0; $rxPkts = 0; $txPkts = 0
        if ($stat) {
            $rxBytes = [double]$stat.ReceivedBytes
            $txBytes = [double]$stat.SentBytes
            $rxPkts = [double]($stat.ReceivedUnicastPackets + $stat.ReceivedMulticastPackets + $stat.ReceivedBroadcastPackets)
            $txPkts = [double]($stat.SentUnicastPackets + $stat.SentMulticastPackets + $stat.SentBroadcastPackets)
        }
        "{0,-28} {1,12} {2,10} {3,12} {4,10}" -f $ad.Name, (Format-Bytes $rxBytes), $rxPkts, (Format-Bytes $txBytes), $txPkts
    }
    exit 0
}

# ------------------------------------------------------------------------
# Default: full per-interface output
# ------------------------------------------------------------------------
$first = $true
foreach ($ad in $adapters) {
    $isUp = $ad.Status -eq 'Up'
    $isLoopback = $ad.InterfaceDescription -like "*Loopback*" -or $ad.Name -like "*Loopback*"

    $flags = 0
    $flagNames = @()
    if ($isUp) { $flags += 1;     $flagNames += 'UP' }
    $flags += 2;                  $flagNames += 'BROADCAST'
    if ($isLoopback) { $flags += 8; $flagNames += 'LOOPBACK' }
    if ($isUp) { $flags += 64;    $flagNames += 'RUNNING' }
    $flags += 4096;               $flagNames += 'MULTICAST'
    if (-not $isUp) { $flagNames += 'NO-CARRIER' }

    $mtu = 1500
    $ipIf = Get-NetIPInterface -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ipIf -and $ipIf.NlMtu) { $mtu = $ipIf.NlMtu }

    if (-not $first) { Write-Host "" }
    $first = $false
    Write-Host "$($ad.Name): flags=$flags<$(($flagNames -join ','))>  mtu $mtu"

    $ipv4s = @(Get-NetIPAddress -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' })
    foreach ($ip in $ipv4s) {
        $netmask = ConvertTo-Netmask $ip.PrefixLength
        $line = "        inet $($ip.IPAddress)  netmask $netmask"
        $bcast = Get-BroadcastAddress $ip.IPAddress $netmask
        if ($bcast) { $line += "  broadcast $bcast" }
        Write-Host $line
    }

    $ipv6s = @(Get-NetIPAddress -InterfaceIndex $ad.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -ne '::1' })
    foreach ($ip in $ipv6s) {
        $addr = $ip.IPAddress -replace '%\d+$'
        $scope = if ($addr -like 'fe80*') { '0x20<link>' } else { '0x0<global>' }
        Write-Host "        inet6 $addr  prefixlen $($ip.PrefixLength)  scopeid $scope"
    }

    $mac = if ($ad.MacAddress) { $ad.MacAddress.Replace('-', ':').ToLower() } else { '00:00:00:00:00:00' }
    $media = if ($ad.MediaType) { $ad.MediaType } else { 'Ethernet' }
    $speed = if ($ad.LinkSpeed) { ", $($ad.LinkSpeed)" } else { "" }
    Write-Host "        ether $mac  ($media$speed)"

    $stat = Get-NetAdapterStatistics -Name $ad.Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($stat) {
        $rxPkts = [double]($stat.ReceivedUnicastPackets + $stat.ReceivedMulticastPackets + $stat.ReceivedBroadcastPackets)
        $txPkts = [double]($stat.SentUnicastPackets + $stat.SentMulticastPackets + $stat.SentBroadcastPackets)
        Write-Host "        RX packets $rxPkts  bytes $(Format-Bytes ([double]$stat.ReceivedBytes))"
        Write-Host "        TX packets $txPkts  bytes $(Format-Bytes ([double]$stat.SentBytes))"
    }
}

exit 0
