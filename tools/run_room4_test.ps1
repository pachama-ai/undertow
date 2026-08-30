<#
    run_room4_test.ps1 ??? FOKUSSIERTER Level-4-Test (nur tests/room4_tests.lua).

    Baut ein eigenes Test-PDX ausschlie??lich mit dem Raum-4-Test und wertet
    TestReport.room4 aus. Bewusst KEINE komplette Testsuite ??? f??r die
    Isolation eines einzelnen Level-Rebuilds.

    Ablauf:
      1. PLAYDATE_SDK_PATH pr??fen.
      2. pdc.exe und PlaydateSimulator.exe pr??fen.
      3. Tempor??re Verzeichnisse ausschlie??lich unter build/ anlegen.
      4. Projektmodule + tests/room4_tests.lua hineinkopieren.
      5. pdxinfo und Runner-main.lua erzeugen (importiert nur room4_tests).
      6. Test-PDX bauen ??? Ausgabeverzeichnis NIE innerhalb des Quellverzeichnisses.
      7. Simulator starten und auf selbstst??ndige Beendigung warten (Timeout).
      8. Ergebnisdatei lesen, vollst??ndig ausgeben, RESULT-Zeile auswerten.
      9. Exit 0 nur bei failed=0 UND complete=1; sonst Exit 1.
#>
$ErrorActionPreference = 'Stop'

$exitCode = 1

try {
    # --- 1) SDK-Pfad -------------------------------------------------------
    $sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
    if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
    if (-not $sdk -or -not (Test-Path -LiteralPath $sdk)) {
        throw "PLAYDATE_SDK_PATH fehlt oder ung??ltig: '$sdk'"
    }

    # --- 2) Werkzeuge ------------------------------------------------------
    $pdc = Join-Path $sdk 'bin\pdc.exe'
    $sim = Join-Path $sdk 'bin\PlaydateSimulator.exe'
    if (-not (Test-Path -LiteralPath $pdc)) { throw "pdc.exe fehlt: $pdc" }
    if (-not (Test-Path -LiteralPath $sim)) { throw "PlaydateSimulator.exe fehlt: $sim" }

    # --- 3) Pfade und tempor??re Verzeichnisse ------------------------------
    $root = Split-Path -Parent $PSScriptRoot
    $buildDir = Join-Path $root 'build'
    $srcDir = Join-Path $buildDir '_room4_src'
    $outDir = Join-Path $buildDir '_room4_out'
    $bundleId = 'com.selina.ringe.test4'
    $resultFile = Join-Path $sdk ("Disk\Data\" + $bundleId + "\test_results.txt")
    $timeoutSeconds = 30

    if (Test-Path -LiteralPath $srcDir) { Remove-Item -Recurse -Force -LiteralPath $srcDir }
    if (Test-Path -LiteralPath $outDir) { Remove-Item -Recurse -Force -LiteralPath $outDir }
    New-Item -ItemType Directory -Force -Path (Join-Path $srcDir 'core') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $srcDir 'world') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $srcDir 'data') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $srcDir 'ui') | Out-Null
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    # --- 4) Dateien kopieren (alle Projektmodule + nur der Raum-4-Test) ----
    $srcModules = @(
        'core\config.lua', 'core\geometry.lua', 'core\state.lua', 'core\undo.lua',
        'core\audio.lua', 'core\save.lua', 'core\sysmenu.lua',
        'world\player.lua', 'world\room.lua', 'world\bridge.lua', 'world\gate.lua',
        'world\baby.lua', 'world\switch.lua',
        'data\levels.lua',
        'ui\render.lua', 'ui\camera.lua', 'ui\roomtransition.lua', 'ui\menu.lua',
        'ui\transition.lua'
    )
    foreach ($m in $srcModules) {
        $from = Join-Path $root ("source\" + $m)
        if (-not (Test-Path -LiteralPath $from)) { throw "Modul fehlt: $from" }
        Copy-Item -LiteralPath $from -Destination (Join-Path $srcDir $m) -Force
    }
    $srcTest = Join-Path $root 'tests\room4_tests.lua'
    if (-not (Test-Path -LiteralPath $srcTest)) { throw "room4_tests.lua fehlt: $srcTest" }
    Copy-Item -LiteralPath $srcTest -Destination (Join-Path $srcDir 'room4_tests.lua') -Force

    # --- 5) pdxinfo und Runner-main.lua ------------------------------------
    Set-Content -LiteralPath (Join-Path $srcDir 'pdxinfo') -Value ("name=Room4Test`nversion=0.1`nbundleID=" + $bundleId + "`n") -Encoding ascii
    $runner = @'
local logFile, logErr = playdate.file.open("test_results.txt", playdate.file.kFileWrite)
if not logFile then
    print("LOG_OPEN_ERROR: " .. tostring(logErr))
end
local origPrint = print
print = function(...)
    local n = select("#", ...)
    local parts = {}
    for i = 1, n do
        parts[i] = tostring(select(i, ...))
    end
    local text = table.concat(parts, "\t")
    origPrint(text)
    if logFile then
        logFile:write(text .. "\n")
    end
end
TestReport = {}
local ok, err = pcall(function()
    import("CoreLibs/graphics")
    import("core/config")
    import("core/geometry")
    import("core/state")
    import("core/undo")
    import("core/audio")
    import("core/save")
    import("core/sysmenu")
    import("world/player")
    import("world/room")
    import("world/bridge")
    import("world/gate")
    import("world/baby")
    import("world/switch")
    import("data/levels")
    import("ui/render")
    import("ui/camera")
    import("ui/roomtransition")
    import("ui/menu")
    import("ui/transition")
    import("room4_tests")
end)
if ok and TestReport.room4 then
    print("RESULT passed=" .. TestReport.room4.pass .. " failed=" .. TestReport.room4.fail .. " complete=1")
else
    if not ok then
        print("TESTS_RUN_ERROR: " .. tostring(err))
    else
        print("MISSING_TEST_RESULTS: room4=" .. tostring(TestReport.room4 ~= nil))
    end
end
if logFile then
    logFile:flush()
    logFile:close()
end
playdate.simulator.exit()
'@
    Set-Content -LiteralPath (Join-Path $srcDir 'main.lua') -Value $runner -Encoding ascii

    # --- 6) alte Ergebnisdatei l??schen -------------------------------------
    if (Test-Path -LiteralPath $resultFile) {
        $removed = $false
        for ($i = 0; $i -lt 5 -and -not $removed; $i++) {
            try {
                Remove-Item -LiteralPath $resultFile -Force -ErrorAction Stop
                $removed = $true
            } catch {
                Start-Sleep -Milliseconds 200
            }
        }
        if (-not $removed) {
            throw "Alte Ergebnisdatei konnte nicht entfernt werden: $resultFile"
        }
    }

    # --- 7) Build (Ausgabe au??erhalb des Quellverzeichnisses) ---------------
    $pdxOut = Join-Path $outDir 'Room4Test.pdx'
    & $pdc $srcDir $pdxOut
    if ($LASTEXITCODE -ne 0) {
        throw "pdc-Build des ROOM-4-TEST-PDX fehlgeschlagen (Exit $LASTEXITCODE)"
    }
    if (-not (Test-Path -LiteralPath $pdxOut)) {
        throw "Test-PDX wurde nicht erzeugt: $pdxOut"
    }

    # --- 8) Simulator starten und warten -----------------------------------
    $proc = Start-Process -FilePath $sim -ArgumentList ('"' + $pdxOut + '"') -PassThru
    if (-not $proc.WaitForExit($timeoutSeconds * 1000)) {
        Stop-Process -Id $proc.Id -Force
        throw "Simulator-Timeout nach $timeoutSeconds s."
    }

    # --- 9) Ergebnisdatei lesen und auswerten ------------------------------
    if (-not (Test-Path -LiteralPath $resultFile)) {
        throw "Ergebnisdatei fehlt: $resultFile"
    }
    $lines = Get-Content -LiteralPath $resultFile
    $lines | ForEach-Object { Write-Output $_ }

    $resultLine = $lines | Where-Object { $_ -match '^RESULT passed=\d+ failed=\d+ complete=\d+$' } | Select-Object -Last 1
    if (-not $resultLine) {
        throw "Keine g??ltige RESULT-Zeile gefunden."
    }
    if ($resultLine -notmatch 'failed=0' -or $resultLine -notmatch 'complete=1') {
        throw "Testlauf nicht vollst??ndig bestanden: $resultLine"
    }
    Write-Output ("TESTS_OK: " + $resultLine)
    $exitCode = 0
} catch {
    Write-Output ("ERROR: " + $_.Exception.Message)
    Write-Output ("STACK: " + $_.ScriptStackTrace)
}

exit $exitCode

