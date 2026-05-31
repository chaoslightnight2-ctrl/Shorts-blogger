param(
    [string]$HtmlPath = "public/content.html",
    [string]$FallbackPath = "app/src/main/assets/fallback.html"
)

$ErrorActionPreference = "Stop"

function S {
    param([int[]]$Codepoints)
    return -join ($Codepoints | ForEach-Object { [string][char]$_ })
}

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

function Add-LinksInTextOnly {
    param(
        [string]$Html,
        [string]$Term,
        [string]$TargetId,
        [string]$CurrentId
    )

    if ($TargetId -eq $CurrentId) { return @{ html = $Html; count = 0 } }

    $pattern = "(?i)(?<![\p{L}\p{Nd}])$([regex]::Escape($Term))(?![\p{L}\p{Nd}])"
    $parts = [regex]::Split($Html, '(<a\b[\s\S]*?</a>|<[^>]+>)')
    $count = 0

    for ($i = 0; $i -lt $parts.Count; $i++) {
        $part = $parts[$i]
        if (-not $part -or $part[0] -eq '<') { continue }
        if ($part -notmatch $pattern) { continue }

        $localCount = 0
        $parts[$i] = [regex]::Replace($part, $pattern, {
            param($m)
            $script:tradepediaLinkCount++
            '<a href="#' + $TargetId + '">' + $m.Value + '</a>'
        })
        $localCount = $script:tradepediaLinkCount
        $script:tradepediaLinkCount = 0
        $count += $localCount
    }

    return @{ html = ($parts -join ""); count = $count }
}

$terms = @(
    @{ term = "Likidite"; id = "likidite" },
    @{ term = (S 0x0052,0x0069,0x0073,0x006B,0x0020,0x0059,0x00F6,0x006E,0x0065,0x0074,0x0069,0x006D,0x0069); id = "risk-management" },
    @{ term = (S 0x0072,0x0069,0x0073,0x006B,0x0020,0x0079,0x00F6,0x006E,0x0065,0x0074,0x0069,0x006D,0x0069,0x0079,0x006C,0x0065); id = "risk-management" },
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
        $result = Add-LinksInTextOnly -Html $page.html -Term $item.term -TargetId $item.id -CurrentId $page.id
        if ($result.count -gt 0) {
            $page.html = $result.html
            $linkCount += $result.count
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
