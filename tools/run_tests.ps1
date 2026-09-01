<#
    run_tests.ps1 — Geometry-Tests im Playdate-Simulator ausführen.

    Ablauf:
      1. PLAYDATE_SDK_PATH prüfen.
      2. pdc.exe und PlaydateSimulator.exe prüfen.
      3. Temporäre Testverzeichnisse ausschließlich unter build/ anlegen.
      4. Projektmodule und Testdateien hineinkopieren.
      5. pdxinfo und Runner-main.lua erzeugen.
      6. Test-PDX bauen — Ausgabeverzeichnis NIE innerhalb des Quellverzeichnisses.
      7. Simulator starten und auf selbstständige Beendigung warten (Timeout).
      8. Ergebnisdatei lesen, vollständig ausgeben, letzte RESULT-Zeile auswerten.
      9. Exit 0 nur bei failed=0 UND complete=1; sonst Exit 1.

    Rückgabe: 0 = Testlauf vollständig bestanden, 1 = irgendein Fehler.
#>
$ErrorActionPreference = 'Stop'

$exitCode = 1

try {
    # --- 1) SDK-Pfad -------------------------------------------------------
    $sdk = [Environment]::GetEnvironmentVariable('PLAYDATE_SDK_PATH', 'User')
    if (-not $sdk) { $sdk = $env:PLAYDATE_SDK_PATH }
    if (-not $sdk -or -not (Test-Path -LiteralPath $sdk)) {
        throw "PLAYDATE_SDK_PATH fehlt oder ungültig: '$sdk'"
    }

    # --- 2) Werkzeuge ------------------------------------------------------
    $pdc = Join-Path $sdk 'bin\pdc.exe'
    $sim = Join-Path $sdk 'bin\PlaydateSimulator.exe'
    if (-not (Test-Path -LiteralPath $pdc)) { throw "pdc.exe fehlt: $pdc" }
    if (-not (Test-Path -LiteralPath $sim)) { throw "PlaydateSimulator.exe fehlt: $sim" }

    # --- 3) Pfade und temporäre Verzeichnisse ------------------------------
    $root = Split-Path -Parent $PSScriptRoot
    $buildDir = Join-Path $root 'build'
    $srcDir = Join-Path $buildDir '_tests_src'
    $outDir = Join-Path $buildDir '_tests_out'
    $bundleId = 'com.selina.ringe.test'
    $resultFile = Join-Path $sdk ("Disk\Data\" + $bundleId + "\test_results.txt")
    $timeoutSeconds = 30

    if (Test-Path -LiteralPath $srcDir) { Remove-Item -Recurse -Force -LiteralPath $srcDir }
    if (Test-Path -LiteralPath $outDir) { Remove-Item -Recurse -Force -LiteralPath $outDir }
    New-Item -ItemType Directory -Force -Path (Join-Path $srcDir 'core') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $srcDir 'world') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $srcDir 'data') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $srcDir 'ui') | Out-Null
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    # --- 4) Dateien kopieren -----------------------------------------------
    $srcConfig = Join-Path $root 'source\core\config.lua'
    $srcGeometry = Join-Path $root 'source\core\geometry.lua'
    $srcState = Join-Path $root 'source\core\state.lua'
    $srcUndo = Join-Path $root 'source\core\undo.lua'
    $srcAudio = Join-Path $root 'source\core\audio.lua'
    $srcSave = Join-Path $root 'source\core\save.lua'
    $srcSysmenu = Join-Path $root 'source\core\sysmenu.lua'
    $srcTextui = Join-Path $root 'source\core\textui.lua'
    $srcTutorial = Join-Path $root 'source\core\tutorial.lua'
    $srcPlayer = Join-Path $root 'source\world\player.lua'
    $srcRoom = Join-Path $root 'source\world\room.lua'
    $srcBridge = Join-Path $root 'source\world\bridge.lua'
    $srcGate = Join-Path $root 'source\world\gate.lua'
    $srcBaby = Join-Path $root 'source\world\baby.lua'
    $srcSwitch = Join-Path $root 'source\world\switch.lua'
    $srcLevels = Join-Path $root 'source\data\levels.lua'
    $srcRender = Join-Path $root 'source\ui\render.lua'
    $srcCamera = Join-Path $root 'source\ui\camera.lua'
    $srcRoomTransition = Join-Path $root 'source\ui\roomtransition.lua'
    $srcPhase7 = Join-Path $root 'source\ui\phase7.lua'
    $srcRoomReveal = Join-Path $root 'source\ui\roomreveal.lua'
    $srcMenu = Join-Path $root 'source\ui\menu.lua'
    $srcTransition = Join-Path $root 'source\ui\transition.lua'
    $srcTestsGeometry = Join-Path $root 'tests\geometry_tests.lua'
    $srcTestsState = Join-Path $root 'tests\state_tests.lua'
    $srcTestsUndo = Join-Path $root 'tests\undo_tests.lua'
    $srcTestsPlayer = Join-Path $root 'tests\player_tests.lua'
    $srcTestsMovement = Join-Path $root 'tests\movement_tests.lua'
    $srcTestsConnection = Join-Path $root 'tests\connection_tests.lua'
    $srcTestsIntegration = Join-Path $root 'tests\integration_tests.lua'
    $srcTestsSwitch = Join-Path $root 'tests\switch_tests.lua'
    $srcTestsRender = Join-Path $root 'tests\render_tests.lua'
    $srcTestsDockAssist = Join-Path $root 'tests\dock_assist_tests.lua'
    $srcTestsCamera = Join-Path $root 'tests\camera_tests.lua'
    $srcTestsAudio = Join-Path $root 'tests\audio_tests.lua'
    $srcTestsMenu = Join-Path $root 'tests\menu_tests.lua'
    $srcTestsSave = Join-Path $root 'tests\save_tests.lua'
    $srcTestsSystemMenu = Join-Path $root 'tests\system_menu_tests.lua'
    $srcTestsInput = Join-Path $root 'tests\input_tests.lua'
    $srcTestsProgression = Join-Path $root 'tests\progression_tests.lua'
    $srcTestsTransition = Join-Path $root 'tests\transition_tests.lua'
    $srcTestsRoomTransition = Join-Path $root 'tests\roomtransition_tests.lua'
    $srcTestsSwitchTraversal = Join-Path $root 'tests\switch_traversal_tests.lua'
    $srcTestsBaby = Join-Path $root 'tests\baby_tests.lua'
    $srcTestsRoom3 = Join-Path $root 'tests\room3_tests.lua'
    $srcTestsRoom4 = Join-Path $root 'tests\room4_tests.lua'
    $srcTestsTutorial = Join-Path $root 'tests\tutorial_tests.lua'
    $srcTestsPhase7 = Join-Path $root 'tests\phase7_tests.lua'
    $srcTestsRoom78 = Join-Path $root 'tests\room78_transition_test.lua'
    $srcTestsLevel8Full = Join-Path $root 'tests\level8_full_solution_test.lua'
    $srcTestsLevel8TopLeft = Join-Path $root 'tests\level8_top_left_check.lua'
    $srcTestsLevel9Full = Join-Path $root 'tests\level9_full_solution_test.lua'
    $srcTestsLevel8FinalState = Join-Path $root 'tests\level8_final_state_check.lua'
    $srcTestsLevel8D2Variant = Join-Path $root 'tests\level8_d2_variant_check.lua'
    if (-not (Test-Path -LiteralPath $srcConfig)) { throw "config.lua fehlt: $srcConfig" }
    if (-not (Test-Path -LiteralPath $srcGeometry)) { throw "geometry.lua fehlt: $srcGeometry" }
    if (-not (Test-Path -LiteralPath $srcState)) { throw "state.lua fehlt: $srcState" }
    if (-not (Test-Path -LiteralPath $srcUndo)) { throw "undo.lua fehlt: $srcUndo" }
    if (-not (Test-Path -LiteralPath $srcPlayer)) { throw "player.lua fehlt: $srcPlayer" }
    if (-not (Test-Path -LiteralPath $srcRoom)) { throw "room.lua fehlt: $srcRoom" }
    if (-not (Test-Path -LiteralPath $srcTestsGeometry)) { throw "geometry_tests.lua fehlt: $srcTestsGeometry" }
    if (-not (Test-Path -LiteralPath $srcTestsState)) { throw "state_tests.lua fehlt: $srcTestsState" }
    if (-not (Test-Path -LiteralPath $srcTestsUndo)) { throw "undo_tests.lua fehlt: $srcTestsUndo" }
    if (-not (Test-Path -LiteralPath $srcTestsPlayer)) { throw "player_tests.lua fehlt: $srcTestsPlayer" }
    if (-not (Test-Path -LiteralPath $srcTestsMovement)) { throw "movement_tests.lua fehlt: $srcTestsMovement" }
    if (-not (Test-Path -LiteralPath $srcBridge)) { throw "bridge.lua fehlt: $srcBridge" }
    if (-not (Test-Path -LiteralPath $srcGate)) { throw "gate.lua fehlt: $srcGate" }
    if (-not (Test-Path -LiteralPath $srcBaby)) { throw "baby.lua fehlt: $srcBaby" }
    if (-not (Test-Path -LiteralPath $srcSwitch)) { throw "switch.lua fehlt: $srcSwitch" }
    if (-not (Test-Path -LiteralPath $srcLevels)) { throw "levels.lua fehlt: $srcLevels" }
    if (-not (Test-Path -LiteralPath $srcTestsConnection)) { throw "connection_tests.lua fehlt: $srcTestsConnection" }
    if (-not (Test-Path -LiteralPath $srcTestsIntegration)) { throw "integration_tests.lua fehlt: $srcTestsIntegration" }
    if (-not (Test-Path -LiteralPath $srcTestsSwitch)) { throw "switch_tests.lua fehlt: $srcTestsSwitch" }
    if (-not (Test-Path -LiteralPath $srcRender)) { throw "render.lua fehlt: $srcRender" }
    if (-not (Test-Path -LiteralPath $srcCamera)) { throw "camera.lua fehlt: $srcCamera" }
    if (-not (Test-Path -LiteralPath $srcMenu)) { throw "menu.lua fehlt: $srcMenu" }
    if (-not (Test-Path -LiteralPath $srcTestsRender)) { throw "render_tests.lua fehlt: $srcTestsRender" }
    if (-not (Test-Path -LiteralPath $srcTestsDockAssist)) { throw "dock_assist_tests.lua fehlt: $srcTestsDockAssist" }
    if (-not (Test-Path -LiteralPath $srcTestsCamera)) { throw "camera_tests.lua fehlt: $srcTestsCamera" }
    if (-not (Test-Path -LiteralPath $srcAudio)) { throw "audio.lua fehlt: $srcAudio" }
    if (-not (Test-Path -LiteralPath $srcSave)) { throw "save.lua fehlt: $srcSave" }
    if (-not (Test-Path -LiteralPath $srcTestsAudio)) { throw "audio_tests.lua fehlt: $srcTestsAudio" }
    if (-not (Test-Path -LiteralPath $srcTestsMenu)) { throw "menu_tests.lua fehlt: $srcTestsMenu" }
    if (-not (Test-Path -LiteralPath $srcTestsSave)) { throw "save_tests.lua fehlt: $srcTestsSave" }
    if (-not (Test-Path -LiteralPath $srcSysmenu)) { throw "sysmenu.lua fehlt: $srcSysmenu" }
    if (-not (Test-Path -LiteralPath $srcTextui)) { throw "textui.lua fehlt: $srcTextui" }
    if (-not (Test-Path -LiteralPath $srcTutorial)) { throw "tutorial.lua fehlt: $srcTutorial" }
    if (-not (Test-Path -LiteralPath $srcTestsSystemMenu)) { throw "system_menu_tests.lua fehlt: $srcTestsSystemMenu" }
    if (-not (Test-Path -LiteralPath $srcTestsInput)) { throw "input_tests.lua fehlt: $srcTestsInput" }
    if (-not (Test-Path -LiteralPath $srcTestsProgression)) { throw "progression_tests.lua fehlt: $srcTestsProgression" }
    if (-not (Test-Path -LiteralPath $srcTransition)) { throw "transition.lua fehlt: $srcTransition" }
    if (-not (Test-Path -LiteralPath $srcRoomTransition)) { throw "roomtransition.lua fehlt: $srcRoomTransition" }
    if (-not (Test-Path -LiteralPath $srcTestsRoomTransition)) { throw "roomtransition_tests.lua fehlt: $srcTestsRoomTransition" }
    if (-not (Test-Path -LiteralPath $srcTestsTransition)) { throw "transition_tests.lua fehlt: $srcTestsTransition" }
    if (-not (Test-Path -LiteralPath $srcTestsSwitchTraversal)) { throw "switch_traversal_tests.lua fehlt: $srcTestsSwitchTraversal" }
    if (-not (Test-Path -LiteralPath $srcTestsBaby)) { throw "baby_tests.lua fehlt: $srcTestsBaby" }
    if (-not (Test-Path -LiteralPath $srcTestsRoom3)) { throw "room3_tests.lua fehlt: $srcTestsRoom3" }
    if (-not (Test-Path -LiteralPath $srcTestsRoom4)) { throw "room4_tests.lua fehlt: $srcTestsRoom4" }
    if (-not (Test-Path -LiteralPath $srcTestsTutorial)) { throw "tutorial_tests.lua fehlt: $srcTestsTutorial" }
    Copy-Item -LiteralPath $srcConfig -Destination (Join-Path $srcDir 'core\config.lua') -Force
    Copy-Item -LiteralPath $srcGeometry -Destination (Join-Path $srcDir 'core\geometry.lua') -Force
    Copy-Item -LiteralPath $srcState -Destination (Join-Path $srcDir 'core\state.lua') -Force
    Copy-Item -LiteralPath $srcUndo -Destination (Join-Path $srcDir 'core\undo.lua') -Force
    Copy-Item -LiteralPath $srcAudio -Destination (Join-Path $srcDir 'core\audio.lua') -Force
    Copy-Item -LiteralPath $srcSave -Destination (Join-Path $srcDir 'core\save.lua') -Force
    Copy-Item -LiteralPath $srcSysmenu -Destination (Join-Path $srcDir 'core\sysmenu.lua') -Force
    Copy-Item -LiteralPath $srcTextui -Destination (Join-Path $srcDir 'core\textui.lua') -Force
    Copy-Item -LiteralPath $srcTutorial -Destination (Join-Path $srcDir 'core\tutorial.lua') -Force
    # Font mit Umlauten (TextUI nutzt sie; fehlt sie, fällt TextUI auf die
    # System-Font zurück — Tests sind trotzdem robust).
    New-Item -ItemType Directory -Force -Path (Join-Path $srcDir 'font') | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'source\font\Roobert-11-Medium.fnt') -Destination (Join-Path $srcDir 'font\Roobert-11-Medium.fnt') -Force
    Copy-Item -LiteralPath (Join-Path $root 'source\font\Roobert-11-Medium-table-22-22.png') -Destination (Join-Path $srcDir 'font\Roobert-11-Medium-table-22-22.png') -Force
    Copy-Item -LiteralPath $srcPlayer -Destination (Join-Path $srcDir 'world\player.lua') -Force
    Copy-Item -LiteralPath $srcRoom -Destination (Join-Path $srcDir 'world\room.lua') -Force
    Copy-Item -LiteralPath $srcTestsGeometry -Destination (Join-Path $srcDir 'geometry_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsState -Destination (Join-Path $srcDir 'state_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsUndo -Destination (Join-Path $srcDir 'undo_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsPlayer -Destination (Join-Path $srcDir 'player_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsMovement -Destination (Join-Path $srcDir 'movement_tests.lua') -Force
    Copy-Item -LiteralPath $srcBridge -Destination (Join-Path $srcDir 'world\bridge.lua') -Force
    Copy-Item -LiteralPath $srcGate -Destination (Join-Path $srcDir 'world\gate.lua') -Force
    Copy-Item -LiteralPath $srcBaby -Destination (Join-Path $srcDir 'world\baby.lua') -Force
    Copy-Item -LiteralPath $srcSwitch -Destination (Join-Path $srcDir 'world\switch.lua') -Force
    Copy-Item -LiteralPath $srcLevels -Destination (Join-Path $srcDir 'data\levels.lua') -Force
    Copy-Item -LiteralPath $srcTestsConnection -Destination (Join-Path $srcDir 'connection_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsIntegration -Destination (Join-Path $srcDir 'integration_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsSwitch -Destination (Join-Path $srcDir 'switch_tests.lua') -Force
    Copy-Item -LiteralPath $srcRender -Destination (Join-Path $srcDir 'ui\render.lua') -Force
    Copy-Item -LiteralPath $srcCamera -Destination (Join-Path $srcDir 'ui\camera.lua') -Force
    Copy-Item -LiteralPath $srcRoomTransition -Destination (Join-Path $srcDir 'ui\roomtransition.lua') -Force
    Copy-Item -LiteralPath $srcPhase7 -Destination (Join-Path $srcDir 'ui\phase7.lua') -Force
    Copy-Item -LiteralPath $srcRoomReveal -Destination (Join-Path $srcDir 'ui\roomreveal.lua') -Force
    Copy-Item -LiteralPath $srcMenu -Destination (Join-Path $srcDir 'ui\menu.lua') -Force
    Copy-Item -LiteralPath $srcTransition -Destination (Join-Path $srcDir 'ui\transition.lua') -Force
    Copy-Item -LiteralPath $srcTestsRender -Destination (Join-Path $srcDir 'render_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsDockAssist -Destination (Join-Path $srcDir 'dock_assist_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsCamera -Destination (Join-Path $srcDir 'camera_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsAudio -Destination (Join-Path $srcDir 'audio_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsMenu -Destination (Join-Path $srcDir 'menu_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsSave -Destination (Join-Path $srcDir 'save_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsSystemMenu -Destination (Join-Path $srcDir 'system_menu_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsInput -Destination (Join-Path $srcDir 'input_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsProgression -Destination (Join-Path $srcDir 'progression_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsTransition -Destination (Join-Path $srcDir 'transition_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsRoomTransition -Destination (Join-Path $srcDir 'roomtransition_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsSwitchTraversal -Destination (Join-Path $srcDir 'switch_traversal_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsBaby -Destination (Join-Path $srcDir 'baby_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsRoom3 -Destination (Join-Path $srcDir 'room3_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsRoom4 -Destination (Join-Path $srcDir 'room4_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsTutorial -Destination (Join-Path $srcDir 'tutorial_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsPhase7 -Destination (Join-Path $srcDir 'phase7_tests.lua') -Force
    Copy-Item -LiteralPath $srcTestsRoom78 -Destination (Join-Path $srcDir 'room78_transition_test.lua') -Force
    Copy-Item -LiteralPath $srcTestsLevel8Full -Destination (Join-Path $srcDir 'level8_full_solution_test.lua') -Force
    Copy-Item -LiteralPath $srcTestsLevel8TopLeft -Destination (Join-Path $srcDir 'level8_top_left_check.lua') -Force
    Copy-Item -LiteralPath $srcTestsLevel9Full -Destination (Join-Path $srcDir 'level9_full_solution_test.lua') -Force
    Copy-Item -LiteralPath $srcTestsLevel8FinalState -Destination (Join-Path $srcDir 'level8_final_state_check.lua') -Force
    Copy-Item -LiteralPath $srcTestsLevel8D2Variant -Destination (Join-Path $srcDir 'level8_d2_variant_check.lua') -Force
    Copy-Item -LiteralPath (Join-Path $root 'build\_l9debug.lua') -Destination (Join-Path $srcDir '_l9debug.lua') -Force

    # --- 5) pdxinfo und Runner-main.lua ------------------------------------
    Set-Content -LiteralPath (Join-Path $srcDir 'pdxinfo') -Value ("name=Ringetests`nversion=0.1`nbundleID=" + $bundleId + "`n") -Encoding ascii
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
    -- Wie main.lua: CoreLibs/graphics bindet die Grafikmethoden (fillCircleAtPoint,
    -- drawArc usw.) auf playdate.graphics. Ohne diesen Import sind Render.drawRoom-
    -- Aufrufe im Testumfeld nil (Probe bestätigt).
    import("CoreLibs/graphics")
    import("core/config")
    import("core/geometry")
    import("core/state")
    import("core/undo")
    import("core/audio")
    import("core/save")
    import("core/sysmenu")
    import("core/textui")
    import("core/tutorial")
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
    import("ui/phase7")
    import("ui/roomreveal")
    import("ui/menu")
    import("ui/transition")
    import("geometry_tests")
    import("state_tests")
    import("undo_tests")
    import("player_tests")
    import("movement_tests")
    import("connection_tests")
    import("integration_tests")
    import("switch_tests")
    import("render_tests")
    import("dock_assist_tests")
    import("camera_tests")
    import("audio_tests")
    import("menu_tests")
    import("save_tests")
    import("system_menu_tests")
    import("input_tests")
    import("progression_tests")
    import("transition_tests")
    import("roomtransition_tests")
    import("switch_traversal_tests")
    import("baby_tests")
    import("room3_tests")
    import("room4_tests")
    import("tutorial_tests")
    import("phase7_tests")
    import("room78_transition_test")
    import("level8_full_solution_test")
    import("level8_top_left_check")
    import("level9_full_solution_test")
    import("level8_final_state_check")
    import("level8_d2_variant_check")
end)
if ok and TestReport.geometry and TestReport.state and TestReport.undo and TestReport.player and TestReport.movement and TestReport.connection and TestReport.integration and TestReport.switch and TestReport.render and TestReport.dockAssist and TestReport.camera and TestReport.audio and TestReport.menu and TestReport.save and TestReport.systemMenu and TestReport.input and TestReport.progression and TestReport.transition and TestReport.roomTransition and TestReport.switchTraversal and TestReport.baby and TestReport.room3 and TestReport.room4 and TestReport.tutorial and TestReport.phase7 and TestReport.room78Transition and TestReport.level8Full and TestReport.level8TopLeft and TestReport.level9Full and TestReport.level8FinalState and TestReport.level8D2Variant then
    local totalPass = TestReport.geometry.pass + TestReport.state.pass + TestReport.undo.pass + TestReport.player.pass + TestReport.movement.pass + TestReport.connection.pass + TestReport.integration.pass + TestReport.switch.pass + TestReport.render.pass + TestReport.dockAssist.pass + TestReport.camera.pass + TestReport.audio.pass + TestReport.menu.pass + TestReport.save.pass + TestReport.systemMenu.pass + TestReport.input.pass + TestReport.progression.pass + TestReport.transition.pass + TestReport.roomTransition.pass + TestReport.switchTraversal.pass + TestReport.baby.pass + TestReport.room3.pass + TestReport.room4.pass + TestReport.tutorial.pass + TestReport.phase7.pass + TestReport.room78Transition.pass + TestReport.level8Full.pass + TestReport.level8TopLeft.pass + TestReport.level9Full.pass + TestReport.level8FinalState.pass + TestReport.level8D2Variant.pass
    local totalFail = TestReport.geometry.fail + TestReport.state.fail + TestReport.undo.fail + TestReport.player.fail + TestReport.movement.fail + TestReport.connection.fail + TestReport.integration.fail + TestReport.switch.fail + TestReport.render.fail + TestReport.dockAssist.fail + TestReport.camera.fail + TestReport.audio.fail + TestReport.menu.fail + TestReport.save.fail + TestReport.systemMenu.fail + TestReport.input.fail + TestReport.progression.fail + TestReport.transition.fail + TestReport.roomTransition.fail + TestReport.switchTraversal.fail + TestReport.baby.fail + TestReport.room3.fail + TestReport.room4.fail + TestReport.tutorial.fail + TestReport.phase7.fail + TestReport.room78Transition.fail + TestReport.level8Full.fail + TestReport.level8TopLeft.fail + TestReport.level9Full.fail + TestReport.level8FinalState.fail + TestReport.level8D2Variant.fail
    print("RESULT passed=" .. totalPass .. " failed=" .. totalFail .. " complete=1")
else
    if not ok then
        print("TESTS_RUN_ERROR: " .. tostring(err))
    else
        print("MISSING_TEST_RESULTS: geometry=" .. tostring(TestReport.geometry ~= nil) .. " state=" .. tostring(TestReport.state ~= nil) .. " undo=" .. tostring(TestReport.undo ~= nil) .. " player=" .. tostring(TestReport.player ~= nil) .. " movement=" .. tostring(TestReport.movement ~= nil) .. " connection=" .. tostring(TestReport.connection ~= nil) .. " integration=" .. tostring(TestReport.integration ~= nil) .. " switch=" .. tostring(TestReport.switch ~= nil) .. " render=" .. tostring(TestReport.render ~= nil) .. " dockAssist=" .. tostring(TestReport.dockAssist ~= nil) .. " camera=" .. tostring(TestReport.camera ~= nil) .. " audio=" .. tostring(TestReport.audio ~= nil) .. " menu=" .. tostring(TestReport.menu ~= nil) .. " save=" .. tostring(TestReport.save ~= nil) .. " systemMenu=" .. tostring(TestReport.systemMenu ~= nil) .. " input=" .. tostring(TestReport.input ~= nil) .. " progression=" .. tostring(TestReport.progression ~= nil) .. " transition=" .. tostring(TestReport.transition ~= nil) .. " roomTransition=" .. tostring(TestReport.roomTransition ~= nil) .. " switchTraversal=" .. tostring(TestReport.switchTraversal ~= nil) .. " baby=" .. tostring(TestReport.baby ~= nil) .. " room3=" .. tostring(TestReport.room3 ~= nil) .. " room4=" .. tostring(TestReport.room4 ~= nil) .. " tutorial=" .. tostring(TestReport.tutorial ~= nil) .. " phase7=" .. tostring(TestReport.phase7 ~= nil) .. " room78Transition=" .. tostring(TestReport.room78Transition ~= nil) .. " level9Full=" .. tostring(TestReport.level9Full ~= nil) .. " level8FinalState=" .. tostring(TestReport.level8FinalState ~= nil) .. " level8D2Variant=" .. tostring(TestReport.level8D2Variant ~= nil))
    end
end
if logFile then
    logFile:flush()
    logFile:close()
end
playdate.simulator.exit()
'@
    Set-Content -LiteralPath (Join-Path $srcDir 'main.lua') -Value $runner -Encoding ascii

    # --- 6) alte Ergebnisdatei löschen -------------------------------------
    # Kurzer Retry: direkt nach einem Simulator-Exit kann das Dateihandle noch
    # kurz gesperrt sein (Windows gibt es verzögert frei) -> transienter
    # "Zugriff verweigert" ohne Fehlschlag des Testlaufs.
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

    # --- 7) Build (Ausgabe außerhalb des Quellverzeichnisses) ---------------
    $pdxOut = Join-Path $outDir 'RingeTests.pdx'
    & $pdc $srcDir $pdxOut
    if ($LASTEXITCODE -ne 0) {
        throw "pdc-Build des Test-PDX fehlgeschlagen (Exit $LASTEXITCODE)"
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
        throw "Keine gültige RESULT-Zeile gefunden."
    }
    if ($resultLine -notmatch 'failed=0' -or $resultLine -notmatch 'complete=1') {
        throw "Testlauf nicht vollständig bestanden: $resultLine"
    }
    Write-Output ("TESTS_OK: " + $resultLine)
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