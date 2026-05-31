param(
    [string]$HtmlPath = "public/content.html",
    [string]$OutPath = "reports/existing_wikipedia_sources.csv"
)

$ErrorActionPreference = "Stop"

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
$match = [regex]::Match($html, '<script id="pageData" type="application/json">([\s\S]*?)</script>')
if (-not $match.Success) {
    throw "pageData JSON block not found in $HtmlPath"
}

$pages = @($match.Groups[1].Value | ConvertFrom-Json)
if ($pages.Count -eq 1 -and $pages[0] -is [System.Array]) {
    $pages = @($pages[0])
}

$rows = foreach ($page in $pages) {
    $links = [regex]::Matches($page.html, 'https://en\.wikipedia\.org/wiki/[^"''<\s]+') |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique

    [pscustomobject]@{
        id = $page.id
        title = $page.title
        kind = $page.kind
        category = $page.category
        wikipedia_source_count = @($links).Count
        wikipedia_urls = (@($links) -join " ")
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path $OutPath) | Out-Null
$rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation -Encoding UTF8
$rows | Group-Object wikipedia_source_count | Sort-Object {[int]$_.Name} | Select-Object Name,Count | Format-Table -AutoSize
Write-Host "Wrote $OutPath"
