# Strip directory and suffix from filenames (Linux basename style)
param(
    [Parameter(Position = 0)]
    [string]$Path,
    [Parameter(Position = 1)]
    [string]$Suffix
)

if (-not $Path) {
    Write-Host "Usage: basename PATH [SUFFIX]"
    exit 2
}

$name = Split-Path $Path -Leaf
if ($Suffix -and $name.EndsWith($Suffix)) {
    $name = $name.Substring(0, $name.Length - $Suffix.Length)
}
Write-Output $name
