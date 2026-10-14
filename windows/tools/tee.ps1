# Write piped input to file and stdout (Linux tee style)
param(
    [Parameter(Position = 0)]
    [string]$File,
    [switch]$a,
    [Parameter(ValueFromPipeline = $true)]
    [object[]]$InputObject
)

begin {
    if (-not $File) {
        Write-Host "Usage: <command> | tee [-a] FILE"
        exit 2
    }
}

process {
    if ($null -eq $_) { return }
    $_ | Out-File -FilePath $File -Encoding UTF8 -Append:$a
    $_
}
