# DNS lookup tool (Linux dig style)
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Domain,
    [Parameter(Position = 1)]
    [string]$Type = "A"
)

Write-Output "; <<>> Windows dig <<>> $Domain $Type"
Write-Output ";; SERVER: System DNS"
Write-Output ""

try {
    switch ($Type.ToUpper()) {
        "A" {
            $result = [System.Net.Dns]::GetHostEntry($Domain)
            Write-Output ";; ANSWER SECTION:"
            foreach ($ip in $result.AddressList) {
                if ($ip.AddressFamily -eq "InterNetwork") {
                    Write-Output "$Domain.    IN    A    $($ip.IPAddressToString)"
                }
            }
        }
        "AAAA" {
            $result = [System.Net.Dns]::GetHostEntry($Domain)
            Write-Output ";; ANSWER SECTION:"
            foreach ($ip in $result.AddressList) {
                if ($ip.AddressFamily -eq "InterNetworkV6") {
                    Write-Output "$Domain.    IN    AAAA    $($ip.IPAddressToString)"
                }
            }
        }
        "MX" {
            $result = Resolve-DnsName -Name $Domain -Type MX -ErrorAction Stop
            Write-Output ";; ANSWER SECTION:"
            foreach ($record in $result) {
                Write-Output "$Domain.    IN    MX    $($record.Preference) $($record.NameExchange)"
            }
        }
        "NS" {
            $result = Resolve-DnsName -Name $Domain -Type NS -ErrorAction Stop
            Write-Output ";; ANSWER SECTION:"
            foreach ($record in $result) {
                Write-Output "$Domain.    IN    NS    $($record.NameHost)"
            }
        }
        "TXT" {
            $result = Resolve-DnsName -Name $Domain -Type TXT -ErrorAction Stop
            Write-Output ";; ANSWER SECTION:"
            foreach ($record in $result) {
                Write-Output "$Domain.    IN    TXT    `"$($record.Strings)`""
            }
        }
        "CNAME" {
            $result = Resolve-DnsName -Name $Domain -Type CNAME -ErrorAction Stop
            Write-Output ";; ANSWER SECTION:"
            foreach ($record in $result) {
                Write-Output "$Domain.    IN    CNAME    $($record.NameHost)"
            }
        }
        default {
            Write-Output "Unsupported type: $Type"
            Write-Output "Supported: A, AAAA, MX, NS, TXT, CNAME"
        }
    }
} catch {
    Write-Output ";; ERROR: $_"
}

Write-Output ""
Write-Output ";; Query completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"