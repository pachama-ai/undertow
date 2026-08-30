<#
    measure_region_diff.ps1 — misst den Anteil geänderter Pixel in gezielten
    Bildschirmregionen (Schalter, Brücke) zwischen VORHER/NACHHER.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$before = Join-Path $root 'build_screenshots_before'
$after = Join-Path $root 'build_screenshots_after'
Add-Type -AssemblyName System.Drawing

# (Name, cx, cy, halbBreite) in 800x480-Koordinaten (2x Skalierung)
# Schalter S1 outer@90 -> (304,120) => (608,240); B0@270 -> (114,120) => (228,240)
$regions = @(
    @('switch_C_A', 608, 240, 30),
    @('switch_C_B', 608, 240, 30),
    @('bridge_active_B0', 228, 240, 30),
    @('bridge_inactive_B1', 400, 412, 30)
)
foreach ($r in $regions) {
    $n = $r[0]; $cx = $r[1]; $cy = $r[2]; $half = $r[3]
    $bPath = Join-Path $before ($n + '.png')
    $aPath = Join-Path $after ($n + '.png')
    if (-not (Test-Path $bPath) -or -not (Test-Path $aPath)) { Write-Output ("SKIP " + $n); continue }
    $b = [System.Drawing.Bitmap]::new($bPath)
    $a = [System.Drawing.Bitmap]::new($aPath)
    $diff = 0; $total = 0
    for ($y = $cy - $half; $y -le $cy + $half; $y += 2) {
        for ($x = $cx - $half; $x -le $cx + $half; $x += 2) {
            $total++
            if ($b.GetPixel($x, $y).ToArgb() -ne $a.GetPixel($x, $y).ToArgb()) { $diff++ }
        }
    }
    $pct = [math]::Round(100 * $diff / $total, 1)
    Write-Output ("{0} (Region {1}x{2}±{3}): {4}% Pixel geändert" -f $n, $cx, $cy, $half, $pct)
    $b.Dispose(); $a.Dispose()
}
