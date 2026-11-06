Add-Type -AssemblyName System.Drawing

$width = 1200
$height = 680
$bmp = New-Object System.Drawing.Bitmap($width, $height)
$g = [System.Drawing.Graphics]::FromImage($bmp)

$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

# Cores
$cBg = [System.Drawing.ColorTranslator]::FromHtml('#F8FAFC')
$cCard = [System.Drawing.ColorTranslator]::FromHtml('#FFFFFF')
$cBorder = [System.Drawing.ColorTranslator]::FromHtml('#E2E8F0')
$cTextDark = [System.Drawing.ColorTranslator]::FromHtml('#0F172A')
$cTextMuted = [System.Drawing.ColorTranslator]::FromHtml('#64748B')
$cRed = [System.Drawing.ColorTranslator]::FromHtml('#EF4444')
$cOrange = [System.Drawing.ColorTranslator]::FromHtml('#F97316')
$cAmber = [System.Drawing.ColorTranslator]::FromHtml('#F59E0B')
$cBlue = [System.Drawing.ColorTranslator]::FromHtml('#3B82F6')
$cTeal = [System.Drawing.ColorTranslator]::FromHtml('#0D9488')
$cGreen = [System.Drawing.ColorTranslator]::FromHtml('#10B981')

$g.Clear($cBg)

# Fontes
$fTitle = New-Object System.Drawing.Font('Segoe UI', 18, [System.Drawing.FontStyle]::Bold)
$fSub = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
$fHeader = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$fLabel = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$fVal = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Regular)
$fSmall = New-Object System.Drawing.Font('Segoe UI', 8.5, [System.Drawing.FontStyle]::Regular)

$bDark = New-Object System.Drawing.SolidBrush($cTextDark)
$bMuted = New-Object System.Drawing.SolidBrush($cTextMuted)
$pBorder = New-Object System.Drawing.Pen($cBorder, 1)

# Header
$g.DrawString('Evolucao do Desempenho por Mudanca (Mediana de 3 Execucoes)', $fTitle, $bDark, 40, 25)
$g.DrawString('Carga: 20 VUs - Duracao: 60s - Semente: 42 | Limites: 1.0 CPU / 512 MB (Banco) e 0.5 CPU / 256 MB (API)', $fSub, $bMuted, 40, 60)

# Card 1 - p95 (Esquerda)
$card1Rect = New-Object System.Drawing.Rectangle(40, 95, 540, 520)
$bCard = New-Object System.Drawing.SolidBrush($cCard)
$g.FillRectangle($bCard, $card1Rect)
$g.DrawRectangle($pBorder, $card1Rect)

$g.DrawString('Tempo de Resposta p95 Geral (ms) [Menor e melhor]', $fHeader, $bDark, 60, 115)
$g.DrawString('Escala linear ate 16.000 ms. Reducao total de 99,58% alcancada.', $fSub, $bMuted, 60, 140)

# Card 2 - Throughput (Direita)
$card2Rect = New-Object System.Drawing.Rectangle(620, 95, 540, 520)
$g.FillRectangle($bCard, $card2Rect)
$g.DrawRectangle($pBorder, $card2Rect)

$g.DrawString('Vazao Geral (req/s) [Maior e melhor]', $fHeader, $bDark, 640, 115)
$g.DrawString('Ganho total de 348,7x (de 4,34 para 1.513,43 req/s).', $fSub, $bMuted, 640, 140)

$mudancas = @(
    @{ Nome = "00-linha-de-base"; P95 = 14721.2; Req = 4.34; Cor = $cRed; TagP95 = "14.721 ms (Base)"; TagReq = "4,34 req/s" },
    @{ Nome = "01-tuning-postgres"; P95 = 14165.3; Req = 4.77; Cor = $cOrange; TagP95 = "14.165 ms (-3,8%)"; TagReq = "4,77 req/s" },
    @{ Nome = "02-pool-e-log"; P95 = 10349.0; Req = 5.54; Cor = $cAmber; TagP95 = "10.349 ms (-29,7%)"; TagReq = "5,54 req/s" },
    @{ Nome = "03-indices-banco"; P95 = 4451.7; Req = 26.66; Cor = $cBlue; TagP95 = "4.452 ms (-69,8%)"; TagReq = "26,66 req/s (6,1x)" },
    @{ Nome = "04-reescrita-sql"; P95 = 4617.4; Req = 30.70; Cor = $cTeal; TagP95 = "4.617 ms (-68,6%)"; TagReq = "30,70 req/s (7,1x)" },
    @{ Nome = "05-mat-views"; P95 = 61.4; Req = 1513.43; Cor = $cGreen; TagP95 = "61,4 ms (-99,58%!)"; TagReq = "1.513,43 req/s (348,7x!)" }
)

$startY = 180
$rowH = 50
$maxP95 = 16000.0
$barMaxW = 280.0

for ($i = 0; $i -lt $mudancas.Count; $i++) {
    $m = $mudancas[$i]
    $y = $startY + ($i * $rowH)

    # Esquerda: p95
    $g.DrawString($m.Nome, $fLabel, $bDark, 60, $y)
    $wP95 = [Math]::Max(4, [int](($m.P95 / $maxP95) * $barMaxW))
    $bBar = New-Object System.Drawing.SolidBrush($m.Cor)
    $g.FillRectangle($bBar, 60, $y + 18, $wP95, 14)
    $g.DrawString($m.TagP95, $fVal, $bDark, (65 + $wP95), $y + 16)
    $bBar.Dispose()

    # Direita: Throughput
    $g.DrawString($m.Nome, $fLabel, $bDark, 640, $y)
    
    $wReq = 0
    if ($m.Req -le 35) {
        $wReq = [Math]::Max(6, [int](($m.Req / 35.0) * 80.0))
    } else {
        $wReq = [int]$barMaxW
    }
    $bBarR = New-Object System.Drawing.SolidBrush($m.Cor)
    $g.FillRectangle($bBarR, 640, $y + 18, $wReq, 14)
    $g.DrawString($m.TagReq, $fVal, $bDark, (645 + $wReq), $y + 16)
    $bBarR.Dispose()
}

# Destaques explicativos na base dos cards
$card1Box = [System.Drawing.RectangleF]::new(60.0, 495.0, 500.0, 105.0)
$txt1 = "Destaques Metodologicos:`n* Ciclo 01: Tuning sem indices variou -3,8% (abaixo do ruido de 30%).`n* Ciclos 02-04: Pool e indices derrubaram p95 geral para ~4,5 s.`n* Ciclo 05: Materialized Views indexadas atingiram p95 de 61,4 ms em todas as 7 rotas da aplicacao."
$g.DrawString($txt1, $fSmall, $bMuted, $card1Box)

$card2Box = [System.Drawing.RectangleF]::new(640.0, 495.0, 500.0, 105.0)
$txt2 = "Destaques Metodologicos:`n* Linha de base: 4,34 req/s com CPU do PostgreSQL travada em 98,0%.`n* Indexacao B-Tree/GIN: saltou para 26,66 req/s (6,1x mais transacoes).`n* Ciclo 05: Pre-computacao analitica liberou CPU para 70,1% e alcancou 1.513,43 req/s."
$g.DrawString($txt2, $fSmall, $bMuted, $card2Box)

# Rodape
$g.DrawString('Fonte: Resultados oficiais registrados em resultados/ gerados por scripts/medir.sh - Processo Seletivo Tech for Humans 2026', $fSmall, $bMuted, 40, 640)

# Salva arquivo
$outPath = 'artigo/img/p95-por-mudanca.png'
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)

$g.Dispose()
$bmp.Dispose()
$bDark.Dispose()
$bMuted.Dispose()
$bCard.Dispose()
$pBorder.Dispose()

Write-Host "Grafico regerado com sucesso em: $outPath"
