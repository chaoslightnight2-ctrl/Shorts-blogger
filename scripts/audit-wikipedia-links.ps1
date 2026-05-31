param(
    [string]$HtmlPath = "public/content.html",
    [string]$OutPath = "reports/wikipedia_link_audit.csv",
    [int]$Start = 0,
    [int]$Limit = 20
)

$ErrorActionPreference = "Stop"

function Get-PageData {
    param([string]$Path)
    $html = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $match = [regex]::Match($html, '<script id="pageData" type="application/json">([\s\S]*?)</script>')
    if (-not $match.Success) {
        throw "pageData JSON block not found in $Path"
    }
    return $match.Groups[1].Value | ConvertFrom-Json
}

function Normalize-SearchTitle {
    param([string]$Title)
    $title = $Title -replace '\s+[\u2013\u2014-]\s+.*$', ''
    $title = $title -replace '\s+/.*$', ''
    $title = $title -replace '\s+ve\s+.*$', ''
    $title.Trim()
}

function Search-Wikipedia {
    param([string]$Title)
    $query = [uri]::EscapeDataString($Title)
    $url = "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=$query&format=json&srlimit=3"
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        try {
            $result = Invoke-RestMethod -Uri $url -Headers @{ "User-Agent" = "TradepediaAudit/1.0 (personal research script)" }
            return $result.query.search
        } catch {
            if ($attempt -eq 5) { throw }
            Start-Sleep -Seconds ([Math]::Min(10, 2 * $attempt))
        }
    }
}

$pages = @(Get-PageData -Path $HtmlPath)
if ($pages.Count -eq 1 -and $pages[0] -is [System.Array]) {
    $pages = @($pages[0])
}
$pages = @($pages | Select-Object -Skip $Start -First $Limit)
$rows = New-Object System.Collections.Generic.List[object]

foreach ($page in $pages) {
    $searchTitle = Normalize-SearchTitle -Title $page.title
    $results = Search-Wikipedia -Title $searchTitle
    $top = $results | Select-Object -First 1
    $wikiTitle = if ($top) { $top.title } else { "" }
    $wikiUrl = if ($top) { "https://en.wikipedia.org/wiki/" + [uri]::EscapeDataString(($top.title -replace " ", "_")) } else { "" }
    $confidence = if ($top -and (($top.title -ieq $searchTitle) -or ($top.title -like "*$searchTitle*") -or ($searchTitle -like "*$($top.title)*"))) { "high" } elseif ($top) { "review" } else { "missing" }

    $rows.Add([pscustomobject]@{
        id = $page.id
        title = $page.title
        kind = $page.kind
        category = $page.category
        search_title = $searchTitle
        wikipedia_title = $wikiTitle
        wikipedia_url = $wikiUrl
        confidence = $confidence
        snippet = if ($top) { ($top.snippet -replace "<[^>]+>", "") } else { "" }
    })

    Start-Sleep -Milliseconds 900
}

New-Item -ItemType Directory -Force -Path (Split-Path $OutPath) | Out-Null
if ((Test-Path -LiteralPath $OutPath) -and $Start -gt 0) {
    $rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation -Encoding UTF8 -Append
} else {
    $rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation -Encoding UTF8
}
$rows | Group-Object confidence | Select-Object Name,Count | Format-Table -AutoSize
Write-Host "Wrote $OutPath"
