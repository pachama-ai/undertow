<#
    run_screenshots.ps1 — Visuelle Abnahme: rendert echte Render.drawRoom-Szenen
    im Playdate-Simulator und kopiert die PNGs nach build_screenshots\.

    Ablauf:
      1. PLAYDATE_SDK_PATH prüfen.
      2. pdc.exe und PlaydateSimulator.exe prüfen.
      3. Quellverzeichnis vollständig nach build\_shots_src kopieren.
      4. main.lua durch tools\screenshot_harness.lua ersetzen; pdxinfo-BundleID
         auf com.selina.ringe.shots setzen.
      5. Screenshot-PDX bauen (Ausgabe außerhalb des Quellverzeichnisses).
      6. Simulator starten und auf selbstständige Beendigung warten (Timeout).
      7. PNGs aus Disk\Data\com.selina.ringe.shots\ nach build_screenshots\ kopieren.
#>
$ErrorActionPreference = 'Stop'
$exitCode = 1

try {
    $sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
    if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
    if (-not $sdk -or -not (Test-Path -LiteralPath $sdk)) {
        throw "PLAYDATE_SDK_PATH fehlt oder ungültig: '$sdk'"
    }
    $pdc = Join-Path $sdk 'bin\pdc.exe'
    $sim = Join-Path $sdk 'bin\PlaydateSimulator.exe'
    if (-not (Test-Path -LiteralPath $pdc)) { throw "pdc.exe fehlt: $pdc" }
    if (-not (Test-Path -LiteralPath $sim)) { throw "PlaydateSimulator.exe fehlt: $sim" }

    $root = Split-Path -Parent $PSScriptRoot
    $srcRoot = Join-Path $root 'source'
    $buildDir = Join-Path $root 'build'
    $srcDir = Join-Path $buildDir '_shots_src'
    $outDir = Join-Path $buildDir '_shots_out'
    $destDir = Join-Path $root 'build_screenshots'
    $bundleId = 'com.selina.ringe.shots'
    $dataDir = Join-Path $sdk ("Disk\Data\" + $bundleId)
    # Großzügiges Timeout: alle Szenen + GIF-Sequenzen (inkl. QA-Serie
    # 01..19 „PLAYER + BABY + BABY-DOCK“) benötigen > 600 s im Simulator.
    $timeoutSeconds = 1200

    if (Test-Path -LiteralPath $srcDir) { Remove-Item -Recurse -Force -LiteralPath $srcDir }
    if (Test-Path -LiteralPath $outDir) { Remove-Item -Recurse -Force -LiteralPath $outDir }
    if (Test-Path -LiteralPath $destDir) { Remove-Item -Recurse -Force -LiteralPath $destDir }
    if (Test-Path -LiteralPath $dataDir) { Remove-Item -Recurse -Force -LiteralPath $dataDir }
    New-Item -ItemType Directory -Force -Path $srcDir | Out-Null
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null

    Copy-Item -Path (Join-Path $srcRoot '*') -Destination $srcDir -Recurse -Force

    $harness = Join-Path $root 'tools\screenshot_harness.lua'
    if (-not (Test-Path -LiteralPath $harness)) { throw "screenshot_harness.lua fehlt: $harness" }
    Copy-Item -LiteralPath $harness -Destination (Join-Path $srcDir 'main.lua') -Force
    Set-Content -LiteralPath (Join-Path $srcDir 'pdxinfo') -Value ("name=RingeShots`nversion=0.1`nbundleID=" + $bundleId + "`n") -Encoding ascii

    $pdxOut = Join-Path $outDir 'RingeShots.pdx'
    & $pdc $srcDir $pdxOut
    if ($LASTEXITCODE -ne 0) { throw "pdc-Build des Screenshot-PDX fehlgeschlagen (Exit $LASTEXITCODE)" }
    if (-not (Test-Path -LiteralPath $pdxOut)) { throw "Screenshot-PDX wurde nicht erzeugt: $pdxOut" }

    $proc = Start-Process -FilePath $sim -ArgumentList ('"' + $pdxOut + '"') -PassThru
    if (-not $proc.WaitForExit($timeoutSeconds * 1000)) {
        Stop-Process -Id $proc.Id -Force
        throw "Simulator-Timeout nach $timeoutSeconds s."
    }

    $bmps = Get-ChildItem -Path $dataDir -Filter '*.bmp' -ErrorAction SilentlyContinue
    if (-not $bmps -or $bmps.Count -eq 0) { throw "Keine BMPs erzeugt in $dataDir" }
    $logSrc = Join-Path $dataDir 'shot_log.txt'
    if (Test-Path -LiteralPath $logSrc) { Copy-Item -LiteralPath $logSrc -Destination (Join-Path $destDir 'shot_log.txt') -Force }
    Add-Type -AssemblyName System.Drawing
    foreach ($b in $bmps) {
        $pngPath = Join-Path $destDir ($b.BaseName + '.png')
        # BMP ebenfalls kopieren (für die GIF-Montage).
        Copy-Item -LiteralPath $b.FullName -Destination (Join-Path $destDir $b.Name) -Force
        try {
            $img = [System.Drawing.Image]::FromFile($b.FullName)
            $img.Save($pngPath, [System.Drawing.Imaging.ImageFormat]::Png)
            $img.Dispose()
        }
        catch {
            throw "BMP->PNG fehlgeschlagen für $($b.Name): $($_.Exception.Message)"
        }
    }
    Write-Output ("SHOTS_OK: " + $bmps.Count + " BMPs -> " + $bmps.Count + " PNGs in build_screenshots\")
    $exitCode = 0
}
catch {
    Write-Output ("ERROR: " + $_.Exception.Message)
    $exitCode = 1
}
finally {
    if (Test-Path -LiteralPath $srcDir) { Remove-Item -Recurse -Force -LiteralPath $srcDir -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $outDir) { Remove-Item -Recurse -Force -LiteralPath $outDir -ErrorAction SilentlyContinue }
}

exit $exitCode
