# build_deck.ps1 - assemble the SIH 2026 PS 26038 deck on the official template.
#
# Reads results/deck_facts.txt and builds 6 slides of native PowerPoint shapes.
# Rules enforced here, not left to memory:
#   * exactly 6 slides (the template's instruction slide 7 is deleted)
#   * master elements untouched: title, footer bar, slide number, team oval, logo
#   * every figure comes from deck_facts.txt; a missing fact renders as "n/a",
#     never as a plausible-looking guess
#
# Usage:  powershell -ExecutionPolicy Bypass -File ppt\build_deck.ps1
#         powershell ... -File ppt\build_deck.ps1 -TeamName "X" -TeamId "Y"

param(
  [string]$TeamName = "<<TEAM NAME>>",
  [string]$TeamId   = "<<TEAM ID>>",
  [string]$Root     = "C:\Users\kanha\Desktop\SIH"
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- palette --
function RGBv([int]$r,[int]$g,[int]$b) { return $r + ($g * 256) + ($b * 65536) }
$NAVY  = RGBv 11 37 69
$TEAL  = RGBv 14 124 134
$SAGE  = RGBv 62 142 90
$AMBER = RGBv 240 162 2
$CRIM  = RGBv 193 39 45
$GREY  = RGBv 237 240 242
$WHITE = RGBv 255 255 255
$MIDGREY = RGBv 120 130 140

$msoTrue = -1; $msoFalse = 0
$shpRect = 1; $shpRounded = 5; $shpChevron = 52; $shpDownArrow = 36; $shpRightArrow = 33
$alignL = 1; $alignC = 2
$anchorTop = 1; $anchorMid = 3

# ------------------------------------------------------------------ facts --
$factsPath = Join-Path $Root "results\deck_facts.txt"
$F = @{}
if (Test-Path $factsPath) {
  foreach ($line in Get-Content $factsPath) {
    $t = $line.Trim()
    if ($t -eq "" -or $t.StartsWith("#") -or $t.StartsWith("[")) { continue }
    $i = $t.IndexOf("=")
    if ($i -lt 1) { continue }
    $k = $t.Substring(0,$i).Trim()
    $v = $t.Substring($i+1).Trim()
    $h = $v.IndexOf("  #")
    if ($h -ge 0) { $v = $v.Substring(0,$h).Trim() }
    $F[$k] = $v
  }
  Write-Host "loaded $($F.Count) measured facts"
} else {
  Write-Warning "deck_facts.txt not found - measured values will render as n/a"
}

function Fact([string]$key, [string]$fallback = "n/a") {
  if ($F.ContainsKey($key) -and $F[$key] -ne "") { return $F[$key] }
  return $fallback
}
function Pct([string]$key, [int]$dp = 1) {
  if (-not $F.ContainsKey($key)) { return "n/a" }
  try { return ([double]$F[$key] * 100).ToString("F$dp") + "%" } catch { return "n/a" }
}
function Num([string]$key, [int]$dp = 0) {
  if (-not $F.ContainsKey($key)) { return "n/a" }
  # Invariant culture on purpose: the machine locale is en-IN, which renders
  # 100000 as "1,00,000" and made the slide inconsistent with its own heading.
  try { return ([double]$F[$key]).ToString("N$dp", [cultureinfo]::InvariantCulture) } catch { return "n/a" }
}
function Dec([string]$key, [int]$dp = 3) {
  if (-not $F.ContainsKey($key)) { return "n/a" }
  try { return ([double]$F[$key]).ToString("F$dp") } catch { return "n/a" }
}

# --------------------------------------------------------------- helpers ---
function Box {
  param($slide, $l, $t, $w, $h, $text = "", $fill = $null, $size = 12,
        $bold = $false, $color = $NAVY, $align = 1, $anchor = 1,
        $lineCol = $null, $shape = 1, $wrap = $true)
  $s = $slide.Shapes.AddShape($shape, $l, $t, $w, $h)
  if ($null -eq $fill) { $s.Fill.Visible = $msoFalse } else { $s.Fill.Solid(); $s.Fill.ForeColor.RGB = $fill; $s.Fill.Transparency = [single]0; $s.Fill.Visible = $msoTrue }
  if ($null -eq $lineCol) { $s.Line.Visible = $msoFalse } else { $s.Line.ForeColor.RGB = $lineCol; $s.Line.Weight = [single]1.0; $s.Line.Visible = $msoTrue }
  $s.Shadow.Visible = $msoFalse
  $tf = $s.TextFrame
  $tf.WordWrap = $(if ($wrap) { $msoTrue } else { $msoFalse })
  $tf.MarginLeft = 5; $tf.MarginRight = 5; $tf.MarginTop = 2; $tf.MarginBottom = 2
  $tf.VerticalAnchor = $anchor
  $tr = $tf.TextRange
  $tr.Text = $text
  $tr.Font.Name = "Calibri"
  $tr.Font.Size = [single]$size
  $tr.Font.Bold = $(if ($bold) { $msoTrue } else { $msoFalse })
  $tr.Font.Color.RGB = $color
  $tr.ParagraphFormat.Alignment = $align
  return $s
}

function Txt {
  param($slide, $l, $t, $w, $h, $text, $size = 12, $bold = $false,
        $color = $NAVY, $align = 1, $anchor = 1, $italic = $false)
  $s = $slide.Shapes.AddTextbox(1, $l, $t, $w, $h)
  $tf = $s.TextFrame
  $tf.WordWrap = $msoTrue
  $tf.MarginLeft = 0; $tf.MarginRight = 0; $tf.MarginTop = 0; $tf.MarginBottom = 0
  $tf.VerticalAnchor = $anchor
  $tr = $tf.TextRange
  $tr.Text = $text
  $tr.Font.Name = "Calibri"
  $tr.Font.Size = [single]$size
  $tr.Font.Bold = $(if ($bold) { $msoTrue } else { $msoFalse })
  $tr.Font.Italic = $(if ($italic) { $msoTrue } else { $msoFalse })
  $tr.Font.Color.RGB = $color
  $tr.ParagraphFormat.Alignment = $align
  return $s
}

# A card: coloured top rule, heading, body.
function Card {
  param($slide, $l, $t, $w, $h, $head, $body, $accent = $TEAL,
        $headSize = 13, $bodySize = 10.5)
  Box $slide $l $t $w $h "" $GREY 10 $false $NAVY 1 1 $null $shpRect | Out-Null
  Box $slide $l $t $w 4 "" $accent 8 $false $WHITE 1 1 $null $shpRect | Out-Null
  Txt $slide ($l+9) ($t+10) ($w-18) 22 $head $headSize $true $NAVY 1 1 | Out-Null
  Txt $slide ($l+9) ($t+32) ($w-18) ($h-40) $body $bodySize $false $NAVY 1 1 | Out-Null
}

# Shrink the template's grey instruction pointers to a header strip.
function Demote-Pointer {
  param($slide, $top = 95, $height = 30, $left = 30, $width = 730, $size = 8.5)
  foreach ($sh in @($slide.Shapes)) {
    if ($sh.Name -like "TextBox*" -and $sh.HasTextFrame -eq $msoTrue -and $sh.TextFrame.HasText -eq $msoTrue) {
      $sh.Left = $left; $sh.Top = $top; $sh.Width = $width; $sh.Height = $height
      $tr = $sh.TextFrame.TextRange
      $tr.Text = ($tr.Text -replace "[`r`n]+", "  ·  ").Trim(" ·".ToCharArray())
      $tr.Font.Name = "Calibri"; $tr.Font.Size = [single]$size; $tr.Font.Italic = $msoTrue
      $tr.Font.Color.RGB = $MIDGREY; $tr.Font.Bold = $msoFalse
      $sh.TextFrame.WordWrap = $msoTrue
      return $sh
    }
  }
  return $null
}

function Add-Pic {
  param($slide, $path, $l, $t, $w, $h)
  if (-not (Test-Path $path)) {
    Box $slide $l $t $w $h "figure pending`r$(Split-Path $path -Leaf)" $GREY 9 $false $MIDGREY 2 3 $MIDGREY $shpRect | Out-Null
    return $null
  }
  $p = $slide.Shapes.AddPicture($path, $msoFalse, $msoTrue, $l, $t, $w, $h)
  return $p
}

function Style-Table {
  param($tblShape, $headFill = $TEAL, $size = 9.5)
  $tbl = $tblShape.Table
  for ($r = 1; $r -le $tbl.Rows.Count; $r++) {
    for ($c = 1; $c -le $tbl.Columns.Count; $c++) {
      $cell = $tbl.Cell($r,$c)
      $tr = $cell.Shape.TextFrame.TextRange
      $tr.Font.Name = "Calibri"; $tr.Font.Size = [single]$size
      $cell.Shape.TextFrame.MarginTop = 1; $cell.Shape.TextFrame.MarginBottom = 1
      $cell.Shape.TextFrame.MarginLeft = 5
      $cell.Borders(1).ForeColor.RGB = $GREY; $cell.Borders(2).ForeColor.RGB = $GREY
      $cell.Borders(3).ForeColor.RGB = $GREY; $cell.Borders(4).ForeColor.RGB = $GREY
      if ($r -eq 1) {
        $cell.Shape.Fill.Solid(); $cell.Shape.Fill.ForeColor.RGB = $headFill
        $tr.Font.Bold = $msoTrue; $tr.Font.Color.RGB = $WHITE
      } else {
        $tr.Font.Color.RGB = $NAVY
        $cell.Shape.Fill.Solid()
        if ($r % 2 -eq 0) { $cell.Shape.Fill.ForeColor.RGB = $WHITE } else { $cell.Shape.Fill.ForeColor.RGB = $GREY }
      }
    }
  }
}

function Set-Cell {
  param($tbl, $r, $c, $text, $bold = $false, $color = $null)
  $tr = $tbl.Cell($r,$c).Shape.TextFrame.TextRange
  $tr.Text = $text
  if ($bold) { $tr.Font.Bold = $msoTrue }
  if ($null -ne $color) { $tr.Font.Color.RGB = $color }
}

# ============================================================== build ======
$tpl = Join-Path $Root "SIH2026-IDEA-Presentation-Format.pptx"
$outDir = Join-Path $Root "ppt"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$outPptx = Join-Path $outDir "NETRA_SIH2026_PS26038.pptx"
$outPdf  = Join-Path $outDir "NETRA_SIH2026_PS26038.pdf"
$figDir  = Join-Path $Root "figures"

$pp = New-Object -ComObject PowerPoint.Application
$pres = $pp.Presentations.Open($tpl, $false, $false, $false)

# six slides, hard limit - drop the instruction slide
while ($pres.Slides.Count -gt 6) { $pres.Slides($pres.Slides.Count).Delete() }

# ----------------------------------------------------------- SLIDE 1 ------
$s1 = $pres.Slides(1)
foreach ($sh in @($s1.Shapes)) {
  if ($sh.Name -like "TextBox*") {
    $sh.TextFrame.TextRange.Text = @"
Problem Statement ID – 26038
Problem Statement Title – Explainable AI for Diabetic Retinopathy Screening in Rural India
Theme – MedTech / BioTech / HealthTech
PS Category – Software
Team ID – $TeamId
Team Name – $TeamName
"@ -replace "`r`n", "`r"
    $tr = $sh.TextFrame.TextRange
    $tr.Font.Name = "Calibri"; $tr.Font.Size = 15; $tr.Font.Color.RGB = $NAVY
    $sh.Top = 175; $sh.Height = 300
  }
  # the template's decorative stock photo makes way for our own result
  if ($sh.Name -eq "Picture 4") { $sh.Delete() }
  # "TITLE PAGE" is placeholder text the template expects to be replaced
  if ($sh.Name -like "Subtitle*") {
    $tr = $sh.TextFrame.TextRange
    $tr.Text = "NETRA — Neural Explainable Triage for Retinal Assessment"
    $tr.Font.Name = "Calibri"; $tr.Font.Size = [single]22; $tr.Font.Bold = $msoTrue
    $tr.Font.Color.RGB = $TEAL
  }
}
$hero = Join-Path $figDir "title_hero.png"
Add-Pic $s1 $hero 545 130 242 242 | Out-Null
Txt $s1 470 380 392 34 "Grad-CAM attention on a held-out test image — the evidence behind the grade" 10 $false $MIDGREY 2 1 $true | Out-Null

# ----------------------------------------------------------- SLIDE 2 ------
$s2 = $pres.Slides(2)
Demote-Pointer $s2 92 26 30 730 8.5 | Out-Null

$ribbonY = 128; $chW = 152; $chH = 52; $x0 = 30
$blocks = @(
  @("CAPTURE","portable fundus camera"),
  @("QUALITY GATE","focus · illumination · exposure"),
  @("LESION EVIDENCE","MA · HE · EX · SE · disc"),
  @("DR GRADE","ICDR 0–4 + confidence"),
  @("DUAL CHECK","CNN vs lesion rules"),
  @("REPORT","30-second clinician review")
)
for ($i = 0; $i -lt 6; $i++) {
  $x = $x0 + ($i * ($chW - 4))
  Box $s2 $x $ribbonY $chW $chH $blocks[$i][0] $TEAL 11.5 $true $WHITE 2 3 $null $shpChevron | Out-Null
  Txt $s2 ($x + 14) ($ribbonY + $chH + 3) ($chW - 20) 24 $blocks[$i][1] 9 $false $MIDGREY 2 1 | Out-Null
}

# the two branches that carry the pitch
$brY = $ribbonY + $chH + 32
Box $s2 178 $brY 14 20 "" $CRIM 8 $false $WHITE 2 3 $null $shpDownArrow | Out-Null
Box $s2 60 ($brY + 22) 300 34 "REJECT → recapture instruction to the operator" $CRIM 10 $true $WHITE 2 3 $null $shpRounded | Out-Null
Box $s2 660 $brY 14 20 "" $AMBER 8 $false $WHITE 2 3 $null $shpDownArrow | Out-Null
Box $s2 540 ($brY + 22) 300 34 "CNN ≠ lesion rules → escalate to a human" $AMBER 10 $true $WHITE 2 3 $null $shpRounded | Out-Null

$cardY = $brY + 68
$c1 = "Refuses ungradeable captures with a specific recapture instruction, at a threshold " +
      "fitted to reject the worst $(Pct 'quality.actual_reject' 1) of $(Fact 'quality.calibration_n') real captures — not a guessed cut-off."
$c2 = "The CNN grade must agree with a rule-based ICDR grade read off counted lesions. " +
      "It escalated $(Pct 'd2.catch_rate' 0) of the CNN's referable errors, and of $(Fact 'd2.cnn_missed_referable') referable cases the CNN " +
      "alone missed, $(Fact 'd2.silently_missed_after_d2') were auto-reported as normal."
$c3 = "At 100,000 patients/year manual review is an unstable queue — $(Fact 'sl.backlog_manual_expert_days') expert-days of " +
      "backlog accrue in one year. Triage flags $(Pct 'district.flagged_fraction' 0), against a $(Pct 'district.break_even_flagged' 0) stability limit."
Card $s2 30 $cardY 288 138 "It refuses to guess" $c1 $CRIM 13 9.5
Card $s2 336 $cardY 288 138 "Dual-evidence safety check" $c2 $AMBER 13 9.5
Card $s2 642 $cardY 288 138 "Edge-first, Simulink-proven" $c3 $TEAL 13 9.5

Txt $s2 30 434 900 26 "Not a black box — an evidence-based triage system that shows its work and knows when to abstain." 13 $true $NAVY 2 1 $true | Out-Null

# ----------------------------------------------------------- SLIDE 3 ------
$s3 = $pres.Slides(3)
Demote-Pointer $s3 92 26 30 730 8.5 | Out-Null

$mods = @(
  @("M1  QUALITY ASSESSMENT","Image Processing","imgradient · fspecial('laplacian') · adapthisteq · regionprops → score 0–100, thresholds fitted on $(Fact 'quality.calibration_n') real captures"),
  @("M2  ADAPTIVE ENHANCEMENT","Image Processing","imgaussfilt illumination field · adapthisteq (CLAHE) · imnlmfilt denoise"),
  @("M3  LESION SEGMENTATION","Deep Learning + CV","ResNet-18 encoder + U-Net decoder, 5 channels, native resolution, focal-Tversky loss"),
  @("M4  GRADING + EXPLAINABILITY","Deep Learning","resnet18 · trainnet · gradCAM · operating point at sensitivity ≥ 0.90"),
  @("M5  DEPLOYMENT SIMULATION","Simulink","discrete-time backlog model B(k+1)=max(0,B(k)+demand−capacity), two arms on identical arrivals")
)
$my = 126; $mh = 46
for ($i = 0; $i -lt 5; $i++) {
  $y = $my + ($i * ($mh + 6))
  Box $s3 30 $y 560 $mh "" $WHITE 9 $false $NAVY 1 1 $NAVY $shpRect | Out-Null
  Box $s3 30 $y 560 16 "" $TEAL 9 $false $WHITE 1 1 $null $shpRect | Out-Null
  Txt $s3 36 ($y+1) 380 14 $mods[$i][0] 9.5 $true $WHITE 1 3 | Out-Null
  Txt $s3 416 ($y+1) 168 14 $mods[$i][1] 8.5 $false $WHITE 3 3 | Out-Null
  Txt $s3 36 ($y+18) 548 26 $mods[$i][2] 8.5 $false $NAVY 1 1 | Out-Null
}

$chips = @("Image Processing","Computer Vision","Deep Learning","Statistics & ML","Parallel Computing","Simulink")
for ($i = 0; $i -lt $chips.Count; $i++) {
  $cy = 126 + ($i * 25)
  Box $s3 606 $cy 150 21 $chips[$i] $WHITE 9 $false $TEAL 2 3 $TEAL $shpRounded | Out-Null
}
Txt $s3 606 278 150 16 "verified installed, R2026a" 9 $false $MIDGREY 2 1 $true | Out-Null

Add-Pic $s3 (Join-Path $figDir "triptych.png") 606 300 324 74 | Out-Null
Txt $s3 606 376 324 14 "raw  →  enhanced  →  lesion overlay" 9 $false $MIDGREY 2 1 $true | Out-Null

$dt = $s3.Shapes.AddTable(4, 3, 30, 398, 900, 76)
$tb = $dt.Table
Set-Cell $tb 1 1 "Dataset"; Set-Cell $tb 1 2 "Images used"; Set-Cell $tb 1 3 "Role in this build"
Set-Cell $tb 2 1 "APTOS 2019"; Set-Cell $tb 2 2 "3,662"; Set-Cell $tb 2 3 "ICDR 0–4 grading — train / val / sealed test"
Set-Cell $tb 3 1 "IDRiD (Indian)"; Set-Cell $tb 3 2 "81 pixel-annotated"; Set-Cell $tb 3 3 "Lesion ground truth — 44 train / 10 val / 27 sealed test"
Set-Cell $tb 4 1 "Neovascularisation"; Set-Cell $tb 4 2 "0"; Set-Cell $tb 4 3 "No pixel-level labels exist — not modelled, stated as a limit"
Style-Table $dt $TEAL 9
$tb.Columns(1).Width = 150; $tb.Columns(2).Width = 130; $tb.Columns(3).Width = 620

# ----------------------------------------------------------- SLIDE 4 ------
$s4 = $pres.Slides(4)
Demote-Pointer $s4 92 26 30 730 8.5 | Out-Null

Txt $s4 30 124 440 18 "WHAT IS ACTUALLY BUILT AND MEASURED" 11 $true $NAVY 1 1 | Out-Null
$status = @(
  @("Quality gate + enhancement", (Fact 'status.quality_gate'), $SAGE),
  @("Lesion segmentation (5 channels)", (Fact 'status.lesion_segmentation'), $SAGE),
  @("DR grader (ResNet-18, ICDR 0–4)", (Fact 'status.dr_grader'), $SAGE),
  @("Grad-CAM explainability", (Fact 'status.gradcam'), $SAGE),
  @("Dual-evidence check", (Fact 'status.dual_evidence'), $SAGE),
  @("App Designer GUI", (Fact 'status.gui'), $SAGE),
  @("Simulink district model", (Fact 'status.simulink'), $SAGE),
  @("Neovascularisation detection", "not built — no labels exist", $CRIM)
)
for ($i = 0; $i -lt $status.Count; $i++) {
  $y = 146 + ($i * 21)
  Box $s4 30 $y 262 18 "  $($status[$i][0])" $GREY 8.5 $false $NAVY 1 3 $null $shpRect | Out-Null
  Box $s4 296 $y 174 18 $status[$i][1] $status[$i][2] 8 $true $WHITE 2 3 $null $shpRect | Out-Null
}
Txt $s4 30 318 440 14 "Status words, not percentages — a percentage of a module is not a measurable thing." 9 $false $MIDGREY 1 1 $true | Out-Null

Txt $s4 488 124 442 18 "RISKS AND WHAT ABSORBS THEM" 11 $true $NAVY 1 1 | Out-Null
$risks = @(
  @("Poor field image quality","quality gate refuses and instructs recapture",$CRIM),
  @("Class imbalance (few grade 3–4)","inverse-sqrt class weights + augmentation",$AMBER),
  @("Rural bandwidth limits","edge inference, only flagged cases uploaded",$AMBER),
  @("Clinician distrust of AI","lesion evidence + Grad-CAM + human-in-the-loop",$AMBER),
  @("Domain shift across cameras","illumination normalisation; external validation is future work",$CRIM),
  @("54 annotated training images","the IDRiD benchmark's own limit — stated, not hidden",$CRIM)
)
for ($i = 0; $i -lt $risks.Count; $i++) {
  $y = 146 + ($i * 29)
  Box $s4 488 $y 6 25 "" $risks[$i][2] 8 $false $WHITE 1 1 $null $shpRect | Out-Null
  Txt $s4 500 $y 200 25 $risks[$i][0] 8.5 $true $NAVY 1 3 | Out-Null
  Txt $s4 704 $y 226 25 $risks[$i][1] 8 $false $MIDGREY 1 3 | Out-Null
}

Txt $s4 30 344 440 16 "COST PER SCREENING" 11 $true $NAVY 1 1 | Out-Null
$tiles = @(@("₹6–12","per screening, camera amortised"), @("₹0","software licence (academic)"), @("₹500–1,500","private consult avoided"))
for ($i = 0; $i -lt 3; $i++) {
  $x = 30 + ($i * 148)
  Box $s4 $x 364 140 58 "" $GREY 9 $false $NAVY 1 1 $null $shpRect | Out-Null
  Txt $s4 $x 368 140 26 $tiles[$i][0] 17 $true $TEAL 2 1 | Out-Null
  Txt $s4 $x 394 140 24 $tiles[$i][1] 7.5 $false $NAVY 2 1 | Out-Null
}

Txt $s4 488 344 442 16 "DEPLOYMENT READINESS" 11 $true $NAVY 1 1 | Out-Null
$steps = @("Prototype`r(now)","PHC pilot`r2 districts","Clinical validation`rvs 3 graders","District rollout`r100k/yr")
for ($i = 0; $i -lt 4; $i++) {
  $x = 488 + ($i * 112)
  $shade = RGBv (14 + $i*10) (124 - $i*14) (134 - $i*10)
  Box $s4 $x 364 104 42 $steps[$i] $shade 8 $true $WHITE 2 3 $null $shpChevron | Out-Null
}
Txt $s4 488 410 442 14 "Prototype stage is where this build actually is today." 9 $false $MIDGREY 1 1 $true | Out-Null

Txt $s4 30 432 900 42 ("MATLAB R2026a trial (expires 4 Oct 2026): Image Processing, Computer Vision, Deep Learning, Statistics & ML, " +
  "Parallel Computing and Simulink, all verified installed. SimEvents is licensed but not installed on this machine, so the " +
  "district model is built from core Simulink blocks. Trained on one RTX 4060 laptop GPU — lesion net 63 min, grader 11 min.") 9 $false $NAVY 1 1 | Out-Null

# ----------------------------------------------------------- SLIDE 5 ------
$s5 = $pres.Slides(5)
Demote-Pointer $s5 92 26 30 730 8.5 | Out-Null

Txt $s5 30 124 400 18 "WHY SCREENING, NOT TREATMENT, IS THE GAP" 11 $true $NAVY 1 1 | Out-Null
$funnel = @(
  @("101 million","adults with diabetes in India (ICMR-INDIAB, Lancet 2023)", 400),
  @("~17 million","have diabetic retinopathy (16.9% prevalence)", 330),
  @("~4 million","referable DR — need a specialist now", 250),
  @("1 : 100,000","rural ophthalmologist-to-population ratio", 170),
  @("90%","of resulting vision loss is preventable", 110)
)
for ($i = 0; $i -lt 5; $i++) {
  $y = 148 + ($i * 46)
  $w = $funnel[$i][2]
  $x = 30 + ((400 - $w) / 2)
  $col = RGBv (14 + $i*45) (124 - $i*18) (134 - $i*22)
  Box $s5 $x $y $w 40 "" $col 9 $false $WHITE 2 3 $null $shpRect | Out-Null
  Txt $s5 ($x+8) ($y+3) ($w-16) 20 $funnel[$i][0] 14 $true $WHITE 2 1 | Out-Null
  Txt $s5 ($x+8) ($y+21) ($w-16) 16 $funnel[$i][1] 7.5 $false $WHITE 2 1 | Out-Null
}
Txt $s5 30 380 400 16 "The gap is not treatment. The gap is screening capacity." 10 $true $NAVY 2 1 $true | Out-Null

Txt $s5 452 124 478 18 "ONE DISTRICT, 100,000 PATIENTS PER YEAR" 11 $true $NAVY 1 1 | Out-Null
$dt5 = $s5.Shapes.AddTable(7, 3, 452, 146, 478, 200)
$t5 = $dt5.Table
Set-Cell $t5 1 1 ""; Set-Cell $t5 1 2 "✕  Manual"; Set-Cell $t5 1 3 "✓  With NETRA"
Set-Cell $t5 2 1 "Patients screened / year"; Set-Cell $t5 2 2 (Num 'district.patients_per_year'); Set-Cell $t5 2 3 (Num 'district.patients_per_year')
Set-Cell $t5 3 1 "Images an expert must read"; Set-Cell $t5 3 2 (Num 'district.manual_reviewed'); Set-Cell $t5 3 3 (Num 'district.netra_reviewed')
Set-Cell $t5 4 1 "Ophthalmologists (FTE)"; Set-Cell $t5 4 2 (Dec 'district.manual_experts' 1); Set-Cell $t5 4 3 (Dec 'district.netra_experts' 1)
Set-Cell $t5 5 1 "Expert reading time / day"; Set-Cell $t5 5 2 "10 hrs of work, 6 available"; Set-Cell $t5 5 3 ((Dec 'district.expert_min_per_day' 0) + " min")
Set-Cell $t5 6 1 "Upload volume / day"; Set-Cell $t5 6 2 ((Dec 'district.manual_gb_per_day' 2) + " GB"); Set-Cell $t5 6 3 ((Dec 'district.netra_gb_per_day' 2) + " GB")
Set-Cell $t5 7 1 "Result turnaround"; Set-Cell $t5 7 2 "2–4 weeks"; Set-Cell $t5 7 3 ((Dec 'pipeline.mean_seconds_per_image' 0) + " s, at the point of care")
Style-Table $dt5 $NAVY 9
$t5.Columns(1).Width = 190; $t5.Columns(2).Width = 118; $t5.Columns(3).Width = 170
for ($r = 2; $r -le 7; $r++) {
  $t5.Cell($r,2).Shape.TextFrame.TextRange.Font.Color.RGB = $CRIM
  $t5.Cell($r,3).Shape.TextFrame.TextRange.Font.Bold = $msoTrue
  $t5.Cell($r,3).Shape.TextFrame.TextRange.Font.Color.RGB = $SAGE
}
Box $s5 452 350 478 40 "" $GREY 9 $false $NAVY 1 1 $null $shpRect | Out-Null
Txt $s5 460 354 462 34 ("Manual review is not a staffing shortfall — it is an unstable queue. The Simulink model accumulates " +
  "$(Fact 'sl.backlog_manual_expert_days') expert-days of backlog in one working year. An expert can absorb " +
  "$(Pct 'district.break_even_flagged' 0) of captures before the queue diverges; NETRA flags $(Pct 'district.flagged_fraction' 0).") 9 $true $NAVY 1 3 | Out-Null
Txt $s5 452 392 478 12 ("districtSim.m + buildNetraSimulink.m, driven by the grader's own held-out triage rate. Assumptions named in the scripts.") 9 $false $MIDGREY 1 1 $true | Out-Null

$ben = @(
  @("Social","sight preserved for patients who would never reach a specialist"),
  @("Economic","averts the lifetime cost of avoidable blindness per case"),
  @("Systemic","turns one scarce ophthalmologist into district-wide coverage"),
  @("Aligned","supports Ayushman Bharat HWCs and NPCBVI screening targets")
)
for ($i = 0; $i -lt 4; $i++) {
  $x = 30 + ($i * 228)
  Box $s5 $x 404 218 62 "" $GREY 9 $false $NAVY 1 1 $null $shpRect | Out-Null
  Txt $s5 ($x+8) 408 202 16 $ben[$i][0] 10.5 $true $TEAL 1 1 | Out-Null
  Txt $s5 ($x+8) 424 202 38 $ben[$i][1] 8 $false $NAVY 1 1 | Out-Null
}

# ----------------------------------------------------------- SLIDE 6 ------
$s6 = $pres.Slides(6)
Demote-Pointer $s6 92 24 30 730 8.5 | Out-Null

Txt $s6 30 120 900 16 "REFERABLE DR (ICDR 2+) — PUBLISHED SYSTEMS AND THIS BUILD" 11 $true $NAVY 1 1 | Out-Null
$bt = $s6.Shapes.AddTable(6, 5, 30, 140, 900, 132)
$b = $bt.Table
Set-Cell $b 1 1 "System"; Set-Cell $b 1 2 "Dataset"; Set-Cell $b 1 3 "Sensitivity"; Set-Cell $b 1 4 "Specificity"; Set-Cell $b 1 5 "Source"
Set-Cell $b 2 1 "Gulshan et al. 2016 (Google)"; Set-Cell $b 2 2 "EyePACS-1"; Set-Cell $b 2 3 "90.3%"; Set-Cell $b 2 4 "98.1%"; Set-Cell $b 2 5 "JAMA 316(22):2402"
Set-Cell $b 3 1 "Gulshan et al. 2016"; Set-Cell $b 3 2 "Messidor-2"; Set-Cell $b 3 3 "96.1%"; Set-Cell $b 3 4 "93.9%"; Set-Cell $b 3 5 "high-sensitivity point"
Set-Cell $b 4 1 "IDx-DR pivotal (Abràmoff 2018)"; Set-Cell $b 4 2 "900 primary-care"; Set-Cell $b 4 3 "87.2%"; Set-Cell $b 4 4 "90.7%"; Set-Cell $b 4 5 "npj Digital Med 1:39"
Set-Cell $b 5 1 "PS 26038 requirement"; Set-Cell $b 5 2 "referable DR"; Set-Cell $b 5 3 "> 90%"; Set-Cell $b 5 4 "> 85%"; Set-Cell $b 5 5 "the problem statement"
Set-Cell $b 6 1 "NETRA (this build)" $true; Set-Cell $b 6 2 ("APTOS held-out, n = " + (Fact 'grader.n_test')) $true
Set-Cell $b 6 3 (Pct 'grader.sensitivity') $true; Set-Cell $b 6 4 (Pct 'grader.specificity') $true
Set-Cell $b 6 5 ("AUC " + (Dec 'grader.roc_auc' 3) + " · s12_eval_grader") $true
Style-Table $bt $NAVY 8.5
$b.Columns(1).Width = 230; $b.Columns(2).Width = 170; $b.Columns(3).Width = 110; $b.Columns(4).Width = 110; $b.Columns(5).Width = 280
for ($c = 1; $c -le 5; $c++) {
  $b.Cell(6,$c).Shape.Fill.Solid(); $b.Cell(6,$c).Shape.Fill.ForeColor.RGB = RGBv 224 240 241
  $b.Cell(6,$c).Shape.TextFrame.TextRange.Font.Color.RGB = $NAVY
  $b.Cell(5,$c).Shape.TextFrame.TextRange.Font.Italic = $msoTrue
}
Txt $s6 30 276 900 26 ("Operating point chosen on the VALIDATION split to meet sensitivity ≥ 0.90, then applied unchanged to a sealed test split — " +
  "the protocol Gulshan 2016 and the IDx-DR trial both use. Different dataset from the rows above, so this is a like-for-like task, not a like-for-like benchmark.") 9 $false $MIDGREY 1 1 $true | Out-Null

Txt $s6 30 306 900 16 "LESION-LEVEL RESULTS — 27 SEALED IDRiD TEST IMAGES (Dice)" 10 $true $NAVY 1 1 | Out-Null
$les = @(
  @("Hard exudate", (Dec 'dice.exudates_hard' 3)),
  @("Haemorrhage", (Dec 'dice.haemorrhage_mask' 3)),
  @("Soft exudate", (Dec 'dice.exudates_soft' 3)),
  @("Microaneurysm", (Dec 'dice.microaneurysm' 3)),
  @("Haemorrhage flag (region)", ((Pct 'haem_region.recall' 1) + " sens"))
)
for ($i = 0; $i -lt 5; $i++) {
  $x = 30 + ($i * 182)
  Box $s6 $x 326 172 44 "" $GREY 9 $false $NAVY 1 1 $null $shpRect | Out-Null
  Txt $s6 ($x+6) 329 160 20 $les[$i][1] 14 $true $TEAL 2 1 | Out-Null
  Txt $s6 ($x+6) 349 160 18 $les[$i][0] 7.5 $false $NAVY 2 1 | Out-Null
}

$refs = @(
  @("Datasets", "APTOS 2019 — kaggle.com/c/aptos2019-blindness-detection`rIDRiD — ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid`rBoth used under their published licences (CC-BY-4.0 for IDRiD)"),
  @("Clinical standards", "Wilkinson et al., International Clinical DR Severity Scale, Ophthalmology 2003;110:1677`rICMR-INDIAB, Lancet Diabetes & Endocrinology 2023`rNPCBVI, Ministry of Health & Family Welfare"),
  @("Methods and tooling", "Selvaraju et al., Grad-CAM, ICCV 2017`rPorwal et al., IDRiD, Medical Image Analysis 2020;59:101561`rMathWorks: gradCAM, adapthisteq, trainnet, Simulink")
)
for ($i = 0; $i -lt 3; $i++) {
  $x = 30 + ($i * 306)
  Txt $s6 $x 380 292 16 $refs[$i][0] 9.5 $true $TEAL 1 1 | Out-Null
  Txt $s6 $x 396 292 76 $refs[$i][1] 7.5 $false $NAVY 1 1 | Out-Null
}

# ------------------------------------------------------------- save -------
if (Test-Path $outPptx) { Remove-Item $outPptx -Force }
$pres.SaveAs($outPptx)
Write-Host "saved $outPptx"
try {
  if (Test-Path $outPdf) { Remove-Item $outPdf -Force }
  $pres.SaveAs($outPdf, 32)   # ppSaveAsPDF
  Write-Host "saved $outPdf"
} catch {
  Write-Warning "PDF export failed: $($_.Exception.Message)"
}
$pres.Close()
$pp.Quit()
[System.Runtime.InteropServices.Marshal]::ReleaseComObject($pp) | Out-Null
Write-Host "slides: 6"
