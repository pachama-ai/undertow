<#
    make_gif_montage.ps1 — erzeugt Sequenz-Montagen (zeitlich nebeneinander)
    aus den GIF-Einzelbildern in build_screenshots_after/.

    System.Drawing kann keine animierten GIFs bauen; stattdessen werden die
    Frames als horizontal gestaffelte Beweisbilder angeordnet.

    Ausgabe: build_montage\gif_<name>.png
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$afterDir = Join-Path $root 'build_screenshots_after'
$outDir = Join-Path $root 'build_montage'
if (-not (Test-Path $afterDir)) { throw "after dir fehlt: $afterDir" }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Add-Type -AssemblyName System.Drawing

# Sequenzen: (Name, Titel, Frame-Namen in Reihenfolge)
$seqs = @(
    @('snap', 'SCHALTER SNAP A -> B', @('snap_A_idle', 'snap_A_press', 'snap_B_press', 'snap_B_idle')),
    @('baby_push', 'BABY GEGEN GESCHLOSSENE BLENDE', @('baby_push_0', 'baby_push_1', 'baby_push_2', 'baby_push_3')),
    @('bridge', 'BRUECKE AKTIV vs. INAKTIV', @('bridge_activ_vs_inactive')),
    @('shared_ideal', 'SHARED BRIDGE - IDEALES DOCK', @('shared_ideal_ready', 'shared_ideal_baby_lead', 'shared_ideal_mid_bridge', 'shared_ideal_baby_landing', 'shared_ideal_landing', 'shared_ideal_post_landing')),
    @('shared_vor', 'SHARED BRIDGE - LEICHT VOR DEM DOCK', @('shared_vor_ready', 'shared_vor_baby_lead', 'shared_vor_mid_bridge', 'shared_vor_baby_landing', 'shared_vor_landing', 'shared_vor_post_landing')),
    @('shared_hinter', 'SHARED BRIDGE - LEICHT HINTER DEM DOCK', @('shared_hinter_ready', 'shared_hinter_baby_lead', 'shared_hinter_mid_bridge', 'shared_hinter_baby_landing', 'shared_hinter_landing', 'shared_hinter_post_landing')),
    @('eye', 'PLAYER AUGE BEIM BRUECKENWECHSEL', @('eye_ready', 'eye_focus', 'eye_mid', 'eye_landing', 'eye_post')),
    @('shared_zu_weit', 'ZU WEIT WEG - KEIN SHARED', @('shared_zu_weit')),
    @('r3_start', 'RAUM 3 - STARTZUSTAND', @('r3_start')),
    @('r3_s1', 'RAUM 3 - S1 -> D1 (BABY PARKT)', @('r3_s1')),
    @('r3_solo', 'RAUM 3 - PLAYER SOLO NACH INNEN + S2 -> D2', @('r3_solo_inner', 'r3_s2')),
    @('r3_shared', 'RAUM 3 - RUECKWEG + SHARED BRIDGE', @('r3_return', 'r3_shared_ready', 'r3_shared_mid')),
    @('r3_gate', 'RAUM 3 - GATE-ABSCHLUSS', @('r3_gate')),
    @('r4_start', 'RAUM 4 - STARTZUSTAND (BEIDE SCHALTER B)', @('r4_start')),
    @('r4_s1', 'RAUM 4 - S1 SEGMENT -> D1+D3+D4 (BABY PARKT)', @('r4_s1')),
    @('r4_solo', 'RAUM 4 - PLAYER SOLO + S2 BRUECKE -> B1+D2+T', @('r4_solo_inner', 'r4_s2')),
    @('r4_shared', 'RAUM 4 - RUECKWEG + BABY RETRIEVAL + SHARED B1', @('r4_return', 'r4_shared_ready', 'r4_shared_mid')),
    @('r4_gate', 'RAUM 4 - GATE-ABSCHLUSS', @('r4_gate'))
)

$font = [System.Drawing.Font]::new('Consolas', 14, [System.Drawing.FontStyle]::Bold)
$labelFont = [System.Drawing.Font]::new('Consolas', 11, [System.Drawing.FontStyle]::Regular)
$brush = [System.Drawing.Brushes]::White

foreach ($s in $seqs) {
    $name = $s[0]
    $title = $s[1]
    $frames = $s[2]

    $imgs = @()
    foreach ($f in $frames) {
        $p = Join-Path $afterDir ($f + '.png')
        if (-not (Test-Path $p)) { Write-Output ("SKIP (Frame fehlt): " + $f); continue }
        $imgs += ,[System.Drawing.Bitmap]::new($p)
    }
    if ($imgs.Count -eq 0) { Write-Output ("SKIP (keine Frames): " + $name); continue }

    $fw = $imgs[0].Width
    $fh = $imgs[0].Height
    $w = $fw * $imgs.Count
    $h = $fh + 40
    $canvas = [System.Drawing.Bitmap]::new($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.Clear([System.Drawing.Color]::Black)
    $g.DrawString($title, $font, $brush, 8, 2)

    for ($i = 0; $i -lt $imgs.Count; $i++) {
        $x = $i * $fw
        $g.DrawImage($imgs[$i], $x, 24, $fw, $fh)
        $g.DrawString($frames[$i], $labelFont, $brush, $x + 6, $fh + 26)
    }

    $out = Join-Path $outDir ('gif_' + $name + '.png')
    $canvas.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $canvas.Dispose()
    foreach ($im in $imgs) { $im.Dispose() }
    Write-Output ("GIF_MONTAGE_OK " + $name + " (" + $imgs.Count + " Frames)")
}
Write-Output ("DONE -> " + $outDir)
