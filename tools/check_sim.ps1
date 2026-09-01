# Erfasst den Simulator und liest den Bildschirm per OCR (Schritt-Prüfung).
Start-Sleep -Seconds 4
$root = 'C:\Users\User\Downloads\undertow-master\undertow-master'
& (Join-Path $root 'build\capture_sim.ps1')
& (Join-Path $root 'build\ocr.ps1') -Paths (Join-Path $root 'build\_sim_capture.png')
