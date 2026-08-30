<#
    make_path_montage.ps1 — erzeugt die SHARED-BRIDGE-PATH-Beweismontage.

    Die 14 Debug-Frames (Bridge-Achse + Figuren-Center markiert, 4x-Skalierung
    in build_screenshots_after\) werden als 2x7-Grid nebeneinander angeordnet
    (jeder Frame auf 50% herunterskaliert), mit Frame-Labels.

    Ausgabe: build_montage\path_transit.png
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$afterDir = Join-Path $root 'build_screenshots_after'
$outDir = Join-Path $root 'build_montage'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Add-Type -AssemblyName System.Drawing

$frames = @(
    'path_pre_a', 'path_align_start', 'path_align_mid', 'path_align_done',
    'path_baby_lead', 'path_player_start', 'path_bridge_start',
    'path_bridge_1_3', 'path_bridge_mid', 'path_bridge_2_3',
    'path_baby_landing', 'path_player_near_landing', 'path_player_landing', 'path_post_landing'
)

$cols = 7
$rows = [math]::Ceiling($frames.Count / $cols)
$cellW = 400   # 50% von 800 (4x -> halbieren)
$cellH = 240
$pad = 24      # Label-Zeile je Zelle
$W = $cols * $cellW
$H = $rows * ($cellH + $pad)

$canvas = [System.Drawing.Bitmap]::new($W, $H)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.Clear([System.Drawing.Color]::Black)
$font = [System.Drawing.Font]::new('Consolas', 10, [System.Drawing.FontStyle]::Regular)
$brush = [System.Drawing.Brushes]::White

$idx = 0
foreach ($f in $frames) {
    $p = Join-Path $afterDir ($f + '.png')
    if (-not (Test-Path $p)) { Write-Output ("SKIP " + $f); continue }
    $img = [System.Drawing.Bitmap]::new($p)
    $col = $idx % $cols
    $row = [math]::Floor($idx / $cols)
    $x = $col * $cellW
    $y = $row * ($cellH + $pad)
    $g.DrawImage($img, $x, $y, $cellW, $cellH)
    $g.DrawString($f, $font, $brush, $x + 4, $y + $cellH + 4)
    $img.Dispose()
    $idx++
}

$out = Join-Path $outDir 'path_transit.png'
$canvas.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $canvas.Dispose()
Write-Output ("PATH_MONTAGE_OK -> " + $out)
