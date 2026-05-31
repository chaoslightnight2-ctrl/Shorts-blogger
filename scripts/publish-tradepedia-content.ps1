param(
    [Parameter(Mandatory = $true)]
    [string]$SourceHtml
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$source = Resolve-Path $SourceHtml
$publicPath = Join-Path $repoRoot "public\content.html"
$fallbackPath = Join-Path $repoRoot "app\src\main\assets\fallback.html"

New-Item -ItemType Directory -Force -Path (Split-Path $publicPath), (Split-Path $fallbackPath) | Out-Null
Copy-Item -LiteralPath $source -Destination $publicPath -Force
Copy-Item -LiteralPath $source -Destination $fallbackPath -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath $source, $publicPath, $fallbackPath
$uniqueHashes = $hashes.Hash | Sort-Object -Unique

if ($uniqueHashes.Count -ne 1) {
    $hashes | Format-Table -AutoSize
    throw "Copied files do not match the source HTML."
}

$hashes | Format-Table -AutoSize
git -C $repoRoot status --short
