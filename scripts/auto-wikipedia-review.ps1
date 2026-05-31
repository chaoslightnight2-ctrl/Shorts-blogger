param(
    [string]$HtmlPath = "public/content.html",
    [string]$OutPath = "reports/auto_wikipedia_review.csv",
    [string]$CacheDir = "reports/wiki_cache",
    [int]$Start = 0,
    [int]$Limit = 25,
    [int]$DelayMs = 1200
)

$ErrorActionPreference = "Stop"

function Get-PageData {
    param([string]$Path)
    $html = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $match = [regex]::Match($html, '<script id="pageData" type="application/json">([\s\S]*?)</script>')
    if (-not $match.Success) {
        throw "pageData JSON block not found in $Path"
    }
    $pages = @($match.Groups[1].Value | ConvertFrom-Json)
    if ($pages.Count -eq 1 -and $pages[0] -is [System.Array]) {
        $pages = @($pages[0])
    }
    return $pages
}

function Get-PlainText {
    param([string]$Html)
    $text = $Html -replace '<script[\s\S]*?</script>', ' '
    $text = $text -replace '<style[\s\S]*?</style>', ' '
    $text = $text -replace '<[^>]+>', ' '
    $text = [System.Net.WebUtility]::HtmlDecode($text)
    $text -replace '\s+', ' '
}

function Get-WikipediaUrls {
    param([string]$Html)
    @([regex]::Matches($Html, 'https://en\.wikipedia\.org/wiki/[^"''<\s]+') |
        ForEach-Object { $_.Value } |
        Sort-Object -Unique)
}

function Get-WikiSlug {
    param([string]$Url)
    $slug = $Url -replace '^https://en\.wikipedia\.org/wiki/', ''
    [uri]::UnescapeDataString($slug)
}

function Get-CachePath {
    param([string]$Slug)
    $safe = ($Slug -replace '[^A-Za-z0-9._-]', '_')
    Join-Path $CacheDir "$safe.json"
}

function Invoke-WithRetry {
    param([string]$Uri)
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            return Invoke-RestMethod -Uri $Uri -Headers @{
                "User-Agent" = "TradepediaAutoReview/1.0 (local user audit)"
            }
        } catch {
            if ($attempt -eq 6) { throw }
            Start-Sleep -Seconds ([Math]::Min(30, 3 * $attempt))
        }
    }
}

function Get-WikipediaSummary {
    param([string]$Url)
    New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

    $slug = Get-WikiSlug -Url $Url
    $cachePath = Get-CachePath -Slug $slug
    if (Test-Path -LiteralPath $cachePath) {
        return Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $apiSlug = [uri]::EscapeDataString($slug).Replace('%2F', '/')
    $summaryUrl = "https://en.wikipedia.org/api/rest_v1/page/summary/$apiSlug"
    $summary = Invoke-WithRetry -Uri $summaryUrl
    $summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $cachePath -Encoding UTF8
    Start-Sleep -Milliseconds $DelayMs
    return $summary
}

function Get-Terms {
    param([string]$Text)
    $stop = @(
        'about','after','also','and','are','because','been','being','between','both','but','can','does','each','from',
        'has','have','into','its','more','most','not','only','other','over','than','that','the','their','then','there',
        'these','this','through','used','uses','using','when','where','which','while','with','without','için','olan',
        'olarak','veya','bir','bu','şu','ile','çok','daha','gibi','değil'
    )
    $words = [regex]::Matches($Text.ToLowerInvariant(), '[a-zA-Z][a-zA-Z0-9-]{3,}') |
        ForEach-Object { $_.Value.Trim('-') } |
        Where-Object { $_ -and ($stop -notcontains $_) }
    @($words | Group-Object | Sort-Object Count -Descending | Select-Object -First 40 -ExpandProperty Name)
}

function Get-CoverageScore {
    param(
        [string[]]$SourceTerms,
        [string]$EntryText
    )
    if (-not $SourceTerms -or $SourceTerms.Count -eq 0) { return 0 }
    $entryLower = $EntryText.ToLowerInvariant()
    $hits = 0
    foreach ($term in $SourceTerms) {
        if ($entryLower.Contains($term)) { $hits++ }
    }
    [Math]::Round(($hits / $SourceTerms.Count) * 100, 1)
}

function Get-TitleMatchScore {
    param(
        [string]$Title,
        [string[]]$SourceTitles
    )
    if (-not $SourceTitles -or $SourceTitles.Count -eq 0) { return 0 }
    $normalizedTitle = Normalize-ComparableText -Text $Title
    $best = 0
    foreach ($sourceTitle in $SourceTitles) {
        $normalizedSource = Normalize-ComparableText -Text $sourceTitle
        if (-not $normalizedSource) { continue }
        $score = 0
        if ($normalizedTitle -eq $normalizedSource) {
            $score = 100
        } elseif ($normalizedTitle.Contains($normalizedSource) -or $normalizedSource.Contains($normalizedTitle)) {
            $score = 80
        } else {
            $titleTerms = @($normalizedTitle -split ' ' | Where-Object { $_.Length -gt 2 })
            $sourceTerms = @($normalizedSource -split ' ' | Where-Object { $_.Length -gt 2 })
            if ($titleTerms.Count -gt 0) {
                $hits = 0
                foreach ($term in $titleTerms) {
                    if ($sourceTerms -contains $term) { $hits++ }
                }
                $score = [Math]::Round(($hits / $titleTerms.Count) * 100, 1)
            }
        }
        if ($score -gt $best) { $best = $score }
    }
    return $best
}

function Normalize-ComparableText {
    param([string]$Text)
    $value = [System.Net.WebUtility]::HtmlDecode([string]$Text).ToLowerInvariant()
    $value = $value -replace '[^\p{L}\p{Nd}]+', ' '
    ($value -replace '\s+', ' ').Trim()
}

$pages = Get-PageData -Path $HtmlPath
$batch = @($pages | Select-Object -Skip $Start -First $Limit)
$rows = New-Object System.Collections.Generic.List[object]

foreach ($page in $batch) {
    $entryText = Get-PlainText -Html $page.html
    $urls = Get-WikipediaUrls -Html $page.html
    $summaries = New-Object System.Collections.Generic.List[string]
    $titles = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($url in $urls) {
        try {
            $summary = Get-WikipediaSummary -Url $url
            if ($summary.title) { $titles.Add([string]$summary.title) }
            if ($summary.extract) { $summaries.Add([string]$summary.extract) }
        } catch {
            $errors.Add("$url :: $($_.Exception.Message)")
        }
    }

    $sourceText = ($summaries -join " ")
    $sourceTerms = Get-Terms -Text $sourceText
    $coverage = Get-CoverageScore -SourceTerms $sourceTerms -EntryText $entryText
    $titleMatch = Get-TitleMatchScore -Title $page.title -SourceTitles @($titles)
    $needsRewrite = ($urls.Count -eq 0) -or ($titleMatch -lt 35) -or ($entryText.Length -lt 1800) -or ($errors.Count -gt 0)
    $status = if ($urls.Count -eq 0) {
        "missing_sources"
    } elseif ($errors.Count -gt 0) {
        "source_fetch_error"
    } elseif ($titleMatch -lt 35) {
        "source_title_mismatch"
    } elseif ($entryText.Length -lt 1800) {
        "too_short"
    } elseif ($coverage -lt 20) {
        "needs_translation_review"
    } else {
        "pass"
    }

    $rows.Add([pscustomobject]@{
        id = $page.id
        title = $page.title
        kind = $page.kind
        category = $page.category
        entry_chars = $entryText.Length
        wikipedia_source_count = $urls.Count
        wikipedia_titles = (@($titles) -join " | ")
        coverage_score = $coverage
        title_match_score = $titleMatch
        needs_rewrite = $needsRewrite
        review_status = $status
        source_errors = (@($errors) -join " || ")
        wikipedia_urls = (@($urls) -join " ")
    })
}

New-Item -ItemType Directory -Force -Path (Split-Path $OutPath) | Out-Null
if ((Test-Path -LiteralPath $OutPath) -and $Start -gt 0) {
    $rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation -Encoding UTF8 -Append
} else {
    $rows | Export-Csv -LiteralPath $OutPath -NoTypeInformation -Encoding UTF8
}

$rows | Group-Object review_status | Select-Object Name,Count | Format-Table -AutoSize
Write-Host "Reviewed $($rows.Count) entries. Wrote $OutPath"
