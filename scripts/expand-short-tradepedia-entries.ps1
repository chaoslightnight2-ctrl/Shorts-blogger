param(
    [string]$HtmlPath = "public/content.html",
    [string]$FallbackPath = "app/src/main/assets/fallback.html",
    [string]$ReviewPath = "reports/auto_wikipedia_review.csv",
    [string]$Status = "too_short"
)

$ErrorActionPreference = "Stop"

function Get-PageDataMatch {
    param([string]$Html)
    $match = [regex]::Match($Html, '<script id="pageData" type="application/json">([\s\S]*?)</script>')
    if (-not $match.Success) {
        throw "pageData JSON block not found."
    }
    return $match
}

function ConvertTo-PageArray {
    param([string]$Json)
    $pages = @($Json | ConvertFrom-Json)
    if ($pages.Count -eq 1 -and $pages[0] -is [System.Array]) {
        $pages = @($pages[0])
    }
    return $pages
}

function Html-Encode {
    param([string]$Text)
    [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Get-FocusText {
    param($Page)
    $kind = [string]$Page.kind
    $category = [string]$Page.category
    $title = [string]$Page.title

    if ($kind -match 'Emir') {
        return "$title, fiyat analizinden çok emrin piyasaya nasıl gönderildiğini ve hangi koşulda çalışacağını anlatır. Bu yüzden kavramı sadece isim olarak bilmek yetmez; emrin tetiklenme anı, gerçekleşme ihtimali, kısmi dolum riski ve hızlı piyasada nasıl davranacağı birlikte düşünülmelidir."
    }
    if ($kind -match 'Performans|Pozisyon') {
        return "$title, bir stratejinin sonucunu tek başına iyi veya kötü ilan etmek için değil, getiri ile risk arasındaki ilişkiyi ölçmek için kullanılır. Bu tür ölçütlerde yüksek değer her zaman daha iyi sistem anlamına gelmez; ölçüm dönemi, örneklem sayısı, drawdown yapısı ve işlem maliyetleri sonucu ciddi şekilde değiştirebilir."
    }
    if ($kind -match 'Formasyon|Mum|Grafik') {
        return "$title, grafikte tekrar eden bir fiyat davranışını adlandırır. Formasyonun asıl değeri, fiyatın nerede duraksadığını, nerede alıcı veya satıcı tepkisi verdiğini ve kırılımın hangi bağlamda oluştuğunu anlamaya yardım etmesidir. Tek başına görülen şekil kesin yön tahmini değildir."
    }
    if ($kind -match 'Trading Stili') {
        return "$title, işlem süresi, karar hızı ve risk taşıma biçimiyle ilgili bir yaklaşımdır. Aynı piyasa bilgisi farklı zaman dilimlerinde çok farklı sonuç verebilir; bu yüzden stil seçimi sinyalden önce risk, zaman ve takip disipliniyle ilgilidir."
    }
    if ($kind -match 'Piyasa') {
        return "$title, işlem yapılan aracın veya piyasa yapısının temel özelliklerini açıklar. Bu başlıkta önemli olan yalnızca tanım değil; likidite, kaldıraç, vade, işlem saati, spread ve ürünün hangi riskleri taşıdığıdır."
    }
    return "$title, trading karar zincirindeki bir kavramı açıklar. Bu kavramı doğru okumak için önce neyi ölçtüğünü, hangi durumda işe yaradığını ve hangi durumda yanıltıcı olabileceğini ayırmak gerekir."
}

function Get-ExampleText {
    param($Page)
    $kind = [string]$Page.kind
    $title = [string]$Page.title

    if ($kind -match 'Emir') {
        return "Örnek okuma: fiyat hızlı hareket ederken emir türünün adı kadar, emrin hangi fiyattan ve hangi öncelikle çalışacağı önemlidir. Market emir hız sağlar ama fiyat kontrolü zayıftır; limit emir fiyat kontrolü sağlar ama gerçekleşmeyebilir; stop tabanlı emirlerde ise tetiklenme ve gerçekleşme fiyatı farklı olabilir."
    }
    if ($kind -match 'Performans|Pozisyon') {
        return "Örnek okuma: iki strateji aynı yıllık getiriyi üretse bile biri çok daha derin drawdown yaşıyorsa, pratikte aynı kaliteye sahip değildir. Bu yüzden $title gibi ölçütler tek başına değil; işlem sayısı, zarar serileri, sermaye eğrisi ve maliyet sonrası sonuçlarla birlikte yorumlanır."
    }
    if ($kind -match 'Formasyon|Mum|Grafik') {
        return "Örnek okuma: formasyon destek/direnç, trend yönü ve hacim bağlamı olmadan zayıf sinyal üretir. Aynı şekil güçlü trend içinde devam sinyali gibi çalışabilirken, yatay piyasada sahte kırılım veya kısa süreli tepki olarak kalabilir."
    }
    if ($kind -match 'Trading Stili') {
        return "Örnek okuma: kısa vadeli işlem stili hızlı karar, sıkı risk kontrolü ve yüksek ekran takibi ister; daha uzun vadeli stil ise daha geniş stop, daha az işlem ve haber/taşıma riskini kabul etmeyi gerektirir. Bu nedenle stil, kişisel zaman ve sermaye yapısıyla uyumlu olmalıdır."
    }
    return "Örnek okuma: bu başlık bir işlem sinyaline çevrilmeden önce piyasa rejimiyle test edilmelidir. Trend, volatilite, hacim ve likidite farklılaştığında aynı kuralın davranışı değişebilir."
}

function Get-WarningText {
    param($Page)
    $kind = [string]$Page.kind
    $title = [string]$Page.title

    if ($kind -match 'Emir') {
        return "En kritik hata, emir türünü risk yönetiminin yerine koymaktır. Emir mekanizması zararı sınırlamaya yardım edebilir ama gap, düşük likidite, hızlı haber akışı ve spread açılması gibi durumlarda beklenen fiyatla gerçekleşen fiyat farklılaşabilir."
    }
    if ($kind -match 'Performans|Pozisyon') {
        return "En kritik hata, ölçütü geçmiş performansın garantisi gibi okumaktır. Kısa veri aralığı, az işlem sayısı, aşırı optimize edilmiş parametreler ve maliyetsiz backtestler ölçümü olduğundan iyi gösterebilir."
    }
    if ($kind -match 'Formasyon|Mum|Grafik') {
        return "En kritik hata, grafikte şekli görür görmez yön tahmini yapmaktır. Formasyonun güvenilirliği; oluştuğu bölge, önceki trend, hacim, volatilite ve kırılım sonrası fiyat kabulüyle birlikte değerlendirilmelidir."
    }
    return "En kritik hata, $title kavramını tek başına al-sat sebebi yapmaktır. Sağlam kullanımda kavram; risk planı, pozisyon boyutu, zaman dilimi ve maliyet varsayımlarıyla birlikte test edilir."
}

function New-ExpansionHtml {
    param($Page, $ReviewRow)
    $id = [string]$Page.id
    $title = [string]$Page.title
    $sourceTitles = @()
    if ($ReviewRow.wikipedia_titles) {
        $sourceTitles = @(([string]$ReviewRow.wikipedia_titles) -split '\s+\|\s+' | Where-Object { $_ })
    }
    $sourceText = if ($sourceTitles.Count -gt 0) {
        "Bu genişletme, maddedeki mevcut Wikipedia kaynaklarıyla otomatik kontrol edilen şu başlıklara dayanır: " + ($sourceTitles -join ", ") + "."
    } else {
        "Bu genişletme, maddedeki mevcut kaynak kutusu ve Tradepedia iç yapısı korunarak hazırlanmıştır."
    }

    $focus = Get-FocusText -Page $Page
    $example = Get-ExampleText -Page $Page
    $warning = Get-WarningText -Page $Page

    return @"
<section id="$id-genis-aciklama"><h3>Daha anlaşılır açıklama</h3><p>$(Html-Encode $focus)</p><p>$(Html-Encode $sourceText)</p></section><section id="$id-pratik-okuma"><h3>Pratikte nasıl okunur?</h3><p>$(Html-Encode $example)</p></section><section id="$id-dikkat"><h3>Dikkat edilmesi gerekenler</h3><p>$(Html-Encode $warning)</p></section>
"@
}

function Add-Expansion {
    param($Page, $ReviewRow)
    $id = [string]$Page.id
    if ($Page.html -match ([regex]::Escape("$id-genis-aciklama"))) {
        return $false
    }

    $expansion = New-ExpansionHtml -Page $Page -ReviewRow $ReviewRow
    $insertPatterns = @(
        '<section class="audit-section"',
        '<section id="[^"]+-ilgili"',
        '</article>'
    )

    foreach ($pattern in $insertPatterns) {
        $match = [regex]::Match($Page.html, $pattern)
        if ($match.Success) {
            $Page.html = $Page.html.Insert($match.Index, $expansion)
            return $true
        }
    }
    return $false
}

$html = Get-Content -LiteralPath $HtmlPath -Raw -Encoding UTF8
$match = Get-PageDataMatch -Html $html
$pages = ConvertTo-PageArray -Json $match.Groups[1].Value
$reviewRows = Import-Csv -LiteralPath $ReviewPath | Where-Object { $_.review_status -eq $Status }
$reviewById = @{}
foreach ($row in $reviewRows) {
    $reviewById[$row.id] = $row
}

$changed = 0
foreach ($page in $pages) {
    if ($reviewById.ContainsKey($page.id)) {
        if (Add-Expansion -Page $page -ReviewRow $reviewById[$page.id]) {
            $changed++
        }
    }
}

if ($changed -eq 0) {
    Write-Host "No entries needed expansion."
    exit 0
}

$json = ConvertTo-Json -InputObject $pages -Depth 100 -Compress
$nextScript = "<script id=`"pageData`" type=`"application/json`">$json</script>"
$nextHtml = $html.Remove($match.Index, $match.Length).Insert($match.Index, $nextScript)
Set-Content -LiteralPath $HtmlPath -Value $nextHtml -Encoding UTF8
Copy-Item -LiteralPath $HtmlPath -Destination $FallbackPath -Force

Write-Host "Expanded $changed entries with status '$Status'."
