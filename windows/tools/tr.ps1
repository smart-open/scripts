# Translate or delete characters (Linux tr style)
param(
    [Parameter(Position = 0)]
    [string]$Set1,
    [Parameter(Position = 1)]
    [string]$Set2,
    [switch]$d,
    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject
)

begin {
    if (-not $Set1) {
        Write-Host "Usage: <command> | tr [-d] SET1 [SET2]"
        exit 2
    }
}

process {
    $text = "$_"
    if ($d) {
        $text -replace "[$Set1]", ""
    } elseif ($Set2) {
        for ($i = 0; $i -lt [Math]::Min($Set1.Length, $Set2.Length); $i++) {
            $text = $text.Replace($Set1[$i], $Set2[$i])
        }
        $text
    } else {
        $text
    }
}
