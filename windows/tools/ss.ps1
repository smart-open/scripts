# Show socket statistics (Linux ss style)
param(
    [switch]$t,
    [switch]$u,
    [switch]$l,
    [switch]$p
)

# -u : UDP sockets
if ($u) {
    Get-NetUDPConnection -ErrorAction SilentlyContinue |
        Select-Object @{n = 'Proto'; e = { 'udp' } }, LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess
    exit 0
}

# TCP sockets
$params = @{}
if ($t) { $params['Protocol'] = 'Tcp' }
if ($l) { $params['State'] = 'Listen' }

$conns = Get-NetTCPConnection @params -ErrorAction SilentlyContinue

$result = $conns | Select-Object @{n = 'Proto'; e = { 'tcp' } }, LocalAddress, LocalPort, RemoteAddress, RemotePort, State, OwningProcess

# -p : resolve process names
if ($p) {
    $result = $result | ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        $_ | Select-Object *, @{n = 'Process'; e = { if ($proc) { $proc.ProcessName } else { '?' } } }
    }
}

$result
