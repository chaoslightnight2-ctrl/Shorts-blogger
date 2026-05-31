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

function S {
    param([int[]]$Codepoints)
    return -join ($Codepoints | ForEach-Object { [string][char]$_ })
}

function Repair-Text {
    param([string]$Text)

    $value = [System.Net.WebUtility]::HtmlDecode($Text)
    $pairs = @(
        @{ bad = (S 0x00C3,0x00A7); good = (S 0x00E7) },
        @{ bad = (S 0x00C3,0x0087); good = (S 0x00C7) },
        @{ bad = (S 0x00C4,0x00B1); good = (S 0x0131) },
        @{ bad = (S 0x00C4,0x00B0); good = (S 0x0130) },
        @{ bad = (S 0x00C3,0x00B6); good = (S 0x00F6) },
        @{ bad = (S 0x00C3,0x0096); good = (S 0x00D6) },
        @{ bad = (S 0x00C3,0x2013); good = (S 0x00D6) },
        @{ bad = (S 0x00C3,0x00BC); good = (S 0x00FC) },
        @{ bad = (S 0x00C3,0x009C); good = (S 0x00DC) },
        @{ bad = (S 0x00C3,0x0153); good = (S 0x00DC) },
        @{ bad = (S 0x00C5,0x0178); good = (S 0x015F) },
        @{ bad = (S 0x00C5,0x00BE); good = (S 0x015E) },
        @{ bad = (S 0x00C4,0x0178); good = (S 0x011F) },
        @{ bad = (S 0x00C4,0x017D); good = (S 0x011E) },
        @{ bad = (S 0x00C4,0x017E); good = (S 0x011E) },
        @{ bad = (S 0x00C3,0x2021); good = (S 0x00C7) },
        @{ bad = (S 0x00E2,0x20AC,0x201D); good = (S 0x2014) },
        @{ bad = (S 0x00E2,0x20AC,0x201C); good = (S 0x201C) },
        @{ bad = (S 0x00E2,0x20AC,0x009D); good = (S 0x201D) },
        @{ bad = (S 0x00E2,0x20AC,0x2122); good = (S 0x2019) },
        @{ bad = (S 0x00E2,0x20AC,0x00BA); good = (S 0x203A) },
        @{ bad = (S 0x00C2,0x00B7); good = (S 0x00B7) }
    )

    foreach ($pair in $pairs) {
        $value = $value.Replace($pair.bad, $pair.good)
    }
    return $value
}

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
$match = Get-PageDataMatch -Html $html
$pages = ConvertTo-PageArray -Json $match.Groups[1].Value

$changed = 0
foreach ($page in $pages) {
    $fixed = Repair-Text -Text $page.html
    if ($fixed -ne $page.html) {
        $page.html = $fixed
        $changed++
    }
}

if ($changed -eq 0) {
    Write-Host "No mojibake repaired."
    exit 0
}

$json = ConvertTo-Json -InputObject $pages -Depth 100 -Compress
$nextScript = "<script id=`"pageData`" type=`"application/json`">$json</script>"
$nextHtml = $html.Remove($match.Index, $match.Length).Insert($match.Index, $nextScript)
Set-Content -LiteralPath $HtmlPath -Value $nextHtml -Encoding UTF8
Copy-Item -LiteralPath $HtmlPath -Destination $FallbackPath -Force

Write-Host "Repaired mojibake in $changed entries."
