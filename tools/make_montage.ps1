<#
    make_montage.ps1 — erzeugt VORHER/NACHHER-Vergleichsbilder (Side-by-Side)
    aus den Screenshot-Ordnern build_screenshots_before/ und build_screenshots_after/.

    Ausgabe: build_montage\<name>_comparison.png (1600x480, mit Labels)
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$beforeDir = Join-Path $root 'build_screenshots_before'
$afterDir = Join-Path $root 'build_screenshots_after'
$outDir = Join-Path $root 'build_montage'
if (-not (Test-Path $beforeDir)) { throw "before dir fehlt: $beforeDir" }
if (-not (Test-Path $afterDir)) { throw "after dir fehlt: $afterDir" }
if (Test-Path $outDir) { Remove-Item -Recurse -Force $outDir }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Add-Type -AssemblyName System.Drawing

# Vergleichspaare: (Name, Titel)
$pairs = @(
    @('switch_C_A', 'SCHALTER ZUSTAND A'),
    @('switch_C_B', 'SCHALTER ZUSTAND B'),
    @('switch_C_press_A', 'SCHALTER SNAP (PRESS)'),
    @('bridge_active_B0', 'BRUECKE AKTIV'),
    @('bridge_inactive_B1', 'BRUECKE INAKTIV'),
    @('bridge_ready_B0', 'BRUECKE READY'),
    @('room_overview', 'RAUM UEBERBLICK')
)

foreach ($p in $pairs) {
    $name = $p[0]
    $title = $p[1]
    $bPath = Join-Path $beforeDir ($name + '.png')
    $aPath = Join-Path $afterDir ($name + '.png')
    if (-not (Test-Path $bPath)) { Write-Output ("SKIP (kein before): " + $name); continue }
    if (-not (Test-Path $aPath)) { Write-Output ("SKIP (kein after): " + $name); continue }

    $bmp = [System.Drawing.Bitmap]::new($bPath)
    $amp = [System.Drawing.Bitmap]::new($aPath)
    $w = $bmp.Width + $amp.Width
    $h = [Math]::Max($bmp.Height, $amp.Height) + 20
    $canvas = [System.Drawing.Bitmap]::new($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.Clear([System.Drawing.Color]::Black)
    $g.DrawImage($bmp, 0, 20, $bmp.Width, $bmp.Height)
    $g.DrawImage($amp, $bmp.Width, 20, $amp.Width, $amp.Height)

    $font = [System.Drawing.Font]::new('Consolas', 14, [System.Drawing.FontStyle]::Bold)
    $brush = [System.Drawing.Brushes]::White
    $g.DrawString('VORHER', $font, $brush, 8, 0)
    $g.DrawString('NACHHER', $font, $brush, $bmp.Width + 8, 0)
    $g.DrawString($title, $font, $brush, ($w / 2) - 60, 0)

    $out = Join-Path $outDir ($name + '_comparison.png')
    $canvas.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $canvas.Dispose(); $bmp.Dispose(); $amp.Dispose()
    Write-Output ("MONTAGE_OK " + $name)
}
Write-Output ("DONE -> " + $outDir)
