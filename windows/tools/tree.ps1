# Display directory tree (Linux tree style)
param(
    [Parameter(Position = 0)]
    [string]$Path = ".",
    [int]$Level = 0,
    [switch]$a,
    [switch]$f
)

function Show-Tree {
    param([string]$dir, [string]$prefix = "", [int]$depth = 0)

    if ($Level -gt 0 -and $depth -ge $Level) { return }

    $items = @(Get-ChildItem -LiteralPath $dir -Force:$a -ErrorAction SilentlyContinue)
    $count = $items.Count
    $i = 0

    foreach ($item in $items) {
        $i++
        $isLast = $i -eq $count
        $connector = if ($isLast) { "`\-- " } else { "|-- " }
        $itemPath = if ($f) { $item.FullName } else { $item.Name }
        Write-Output "$prefix$connector$itemPath"

        if ($item.PSIsContainer) {
            $newPrefix = if ($isLast) { "$prefix    " } else { "$prefix|   " }
            Show-Tree $item.FullName $newPrefix ($depth + 1)
        }
    }
}

$root = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
if (-not $root) {
    Write-Host "tree: path not found: $Path"
    exit 1
}

Write-Output $root.Path
Show-Tree $root.Path
