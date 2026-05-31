param(
    [string]$HtmlPath = "public/content.html",
    [string]$FallbackPath = "app/src/main/assets/fallback.html"
)

$ErrorActionPreference = "Stop"

function Get-PageDataMatch {
    param([string]$Html)
    $match = [regex]::Match($Html, '<script id="pageData" type="application/json">([\s\S]*?)</script>')
    if (-not $match.Success) { throw "pageData JSON block not found." }
    return $match
}

function ConvertTo-PageArray {
    param([string]$Json)
    $pages = @($Json | ConvertFrom-Json)
    if ($pages.Count -eq 1 -and $pages[0] -is [System.Array]) { $pages = @($pages[0]) }
    return $pages
}

function Add-LinkInTextOnly {
    param(
        [string]$Html,
        [string]$Term,
        [string]$TargetId,
        [string]$CurrentId
    )

    if ($TargetId -eq $CurrentId) { return @{ html = $Html; changed = $false } }
    if ($Html.Contains("href=""#$TargetId""")) { return @{ html = $Html; changed = $false } }
    if (-not $Html.Contains($Term)) { return @{ html = $Html; changed = $false } }

    $pattern = "(?<![A-Za-zÇĞİÖŞÜçğıöşü])$([regex]::Escape($Term))(?![A-Za-zÇĞİÖŞÜçğıöşü])"
    $parts = [regex]::Split($Html, '(<a\b[\s\S]*?</a>|<[^>]+>)')

    for ($i = 0; $i -lt $parts.Count; $i++) {
        $part = $parts[$i]
        if (-not $part -or $part[0] -eq '<') { continue }
        if ($part -notmatch $pattern) { continue }
        $parts[$i] = [regex]::Replace($part, $pattern, '<a href="#' + $TargetId + '">$0</a>', 1)
        return @{ html = ($parts -join ""); changed = $true }
    }

    return @{ html = $Html; changed = $false }
}

$terms = @(
    @{ term = "Likidite"; id = "likidite" },
    @{ term = "Risk Yönetimi"; id = "risk-management" },
    @{ term = "Backtest"; id = "backtest" },
    @{ term = "Trend"; id = "trend" },
    @{ term = "Hacim"; id = "hacim-kavram" },
    @{ term = "Volatilite"; id = "volatilite" },
    @{ term = "Stop Loss"; id = "stop-loss" },
    @{ term = "Take Profit"; id = "take-profit" },
    @{ term = "Order Book"; id = "order-book" },
    @{ term = "Order Flow"; id = "order-flow" },
    @{ term = "Slippage"; id = "slippage-spread" },
    @{ term = "Piyasa Rejimi"; id = "piyasa-rejimi" }
)

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
$match = Get-PageDataMatch -Html $html
$pages = ConvertTo-PageArray -Json $match.Groups[1].Value
$ids = @{}
foreach ($page in $pages) { $ids[$page.id] = $true }

$linkCount = 0
$changedPages = 0

foreach ($page in $pages) {
    $changedThisPage = $false
    foreach ($item in $terms) {
        if (-not $ids.ContainsKey($item.id)) { continue }
        $result = Add-LinkInTextOnly -Html $page.html -Term $item.term -TargetId $item.id -CurrentId $page.id
        if ($result.changed) {
            $page.html = $result.html
            $linkCount++
            $changedThisPage = $true
        }
    }
    if ($changedThisPage) { $changedPages++ }
}

if ($linkCount -eq 0) {
    Write-Host "No new links added."
    exit 0
}

$json = ConvertTo-Json -InputObject $pages -Depth 100 -Compress
$nextScript = "<script id=`"pageData`" type=`"application/json`">$json</script>"
$nextHtml = $html.Remove($match.Index, $match.Length).Insert($match.Index, $nextScript)
Set-Content -LiteralPath $HtmlPath -Value $nextHtml -Encoding UTF8
Copy-Item -LiteralPath $HtmlPath -Destination $FallbackPath -Force

Write-Host "Added $linkCount links across $changedPages pages."
