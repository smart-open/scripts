# Network utility (Linux nc/netcat style - simplified)
param(
    [Parameter(Position = 0)]
    [string]$TargetHost,
    [Parameter(Position = 1)]
    [int]$Port,
    [switch]$z,
    [switch]$l,
    [int]$Timeout = 3000
)

if ($z -and $TargetHost -and $Port) {
    Write-Host "Checking ${TargetHost}:$Port..."
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $connect = $tcp.BeginConnect($TargetHost, $Port, $null, $null)
        $wait = $connect.AsyncWaitHandle.WaitOne($Timeout, $false)
        if ($wait -and $tcp.Connected) {
            Write-Host "Connection to $TargetHost $Port [tcp/*] succeeded!"
            exit 0
        } else {
            Write-Host "Connection to $TargetHost $Port [tcp/*] failed!"
            exit 1
        }
    } finally {
        $tcp.Close()
    }
} elseif ($l -and $Port) {
    Write-Host "Listening on port $Port..."
    $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Any, $Port)
    $listener.Start()
    $client = $listener.AcceptTcpClient()
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream)
    $writer = New-Object System.IO.StreamWriter($stream)
    $writer.AutoFlush = $true
    while ($line = $reader.ReadLine()) {
        Write-Host $line
    }
    $listener.Stop()
} else {
    Write-Host "Usage: nc [-z] [-l] [host] [port]"
    Write-Host "  -z    Scan for listening daemons"
    Write-Host "  -l    Listen mode"
}