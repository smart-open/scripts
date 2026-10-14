# Find command path (Linux which style)
param(
    [Parameter(Position = 0)]
    [string]$Command
)

if (-not $Command) {
    Write-Host "Usage: which COMMAND"
    exit 2
}

$found = $false
$extensions = @(".com", ".exe", ".bat", ".cmd", ".ps1")

$env:Path -split ";" | Where-Object { $_ } | ForEach-Object {
    $dir = $_
    foreach ($ext in $extensions) {
        $fullPath = Join-Path $dir "$Command$ext"
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            Write-Output $fullPath
            $found = $true
        }
    }
    $fullPath = Join-Path $dir $Command
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        Write-Output $fullPath
        $found = $true
    }
}

if (-not $found) { exit 1 }
