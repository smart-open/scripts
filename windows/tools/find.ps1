# Advanced file search (Linux find style)
param(
    [Parameter(Position = 0)]
    [string]$Path = ".",
    [string]$Name,
    [string]$Type,
    [string]$Size,
    [int]$Depth,
    [switch]$IgnoreCase
)

$params = @{
    Path      = $Path
    Recurse   = $true
    File      = $false
    Directory = $false
    ErrorAction = "SilentlyContinue"
}

if ($Type -eq "f") { $params.File = $true }
elseif ($Type -eq "d") { $params.Directory = $true }

if ($Depth) { $params.Depth = $Depth }

Get-ChildItem @params | Where-Object {
    $match = $true

    # -name in Linux is glob matching (*.log, app.*), not regex
    if ($Name) {
        if ($IgnoreCase) { $match = $match -and ($_.Name -ilike $Name) }
        else { $match = $match -and ($_.Name -like $Name) }
    }

    if ($Size) {
        if ($Size -match "^(\+?)(\d+)([kKmMgG]?)$") {
            $isPlus = $matches[1] -eq "+"
            $num = [int]$matches[2]
            $unit = $matches[3].ToLower()

            $bytes = switch ($unit) {
                "k" { $num * 1KB }
                "m" { $num * 1MB }
                "g" { $num * 1GB }
                default { $num }
            }

            if ($isPlus) { $match = $match -and ($_.Length -ge $bytes) }
            else { $match = $match -and ($_.Length -eq $bytes) }
        }
    }

    $match
} | Select-Object -ExpandProperty FullName
