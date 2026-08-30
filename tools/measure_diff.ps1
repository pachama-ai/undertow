<#
    measure_diff.ps1 — misst den Anteil geänderter Pixel zwischen VORHER/NACHHER
    (Beweis, dass die visuelle Änderung bei 400x240 deutlich sichtbar ist).
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$before = Join-Path $root 'build_screenshots_before'
$after = Join-Path $root 'build_screenshots_after'
Add-Type -AssemblyName System.Drawing
$names = @('switch_C_A', 'switch_C_B', 'bridge_active_B0', 'bridge_inactive_B1', 'room_overview')
foreach ($n in $names) {
    $bPath = Join-Path $before ($n + '.png')
    $aPath = Join-Path $after ($n + '.png')
    if (-not (Test-Path $bPath) -or -not (Test-Path $aPath)) { Write-Output ("SKIP " + $n); continue }
    $b = [System.Drawing.Bitmap]::new($bPath)
    $a = [System.Drawing.Bitmap]::new($aPath)
    $diff = 0
    $total = 0
    for ($y = 0; $y -lt $b.Height; $y += 2) {
        for ($x = 0; $x -lt $b.Width; $x += 2) {
            $total++
            if ($b.GetPixel($x, $y).ToArgb() -ne $a.GetPixel($x, $y).ToArgb()) { $diff++ }
        }
    }
    $pct = [math]::Round(100 * $diff / $total, 1)
    Write-Output ("{0}: {1} von {2} Probenpixeln geändert = {3}%" -f $n, $diff, $total, $pct)
    $b.Dispose(); $a.Dispose()
}
