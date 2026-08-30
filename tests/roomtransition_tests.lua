-- Tests für source/ui/roomtransition.lua (radialer Raumwechsel): der neue
-- Level-/Room-Übergang, bei dem sich der gesamte Ringaufbau eine Stufe nach
-- außen schiebt (fester Mittelpunkt 200,120), alte Puzzleobjekte sich
-- gestaffelt auflösen und neue erst am Reveal-Punkt gestaffelt aufgebaut
-- werden. Reine Präsentationslogik: deterministische Phasenwerte (oldFade,
-- oldVisible, newVisible, futureImpulse, futureWidth, figureScale),
-- Reveal-Punkt, Read-only gegenüber Gameplay.
--
-- Erwartet, dass core/config, ui/camera und ui/roomtransition per import
-- geladen wurden (siehe tools/run_tests.ps1). Ergebnis in
-- TestReport.roomTransition.

local pass = 0
local fail = 0

local function check(condition, message)
    if condition then
        pass = pass + 1
        print("PASS: " .. message)
    else
        fail = fail + 1
        print("FAIL: " .. message)
    end
end

local function approx(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 1e-6)
end

-- Startet eine echte Kamera-Transition (R1 outer 7/inner 6 -> R2 outer 6/
-- inner 5) mit kurzem Hold und der Übergangsdauer, damit RoomTransition.isActive
-- wahr wird und progress() den Fortschritt liefert.
local function startCameraTransition()
    Camera.init(7)
    Camera.beginRoomTransition(7, 6, 6, 5, 0, Config.roomTransitionDuration)
end

-- --- 1) initial idle ----------------------------------------------------------
RoomTransition.reset()
check(RoomTransition.isActive() == false, "rt: initial inaktiv")
check(RoomTransition.isNewRoomLoaded() == false, "rt: initial kein neuer Raum geladen")
check(RoomTransition.pendingRoomIndex == nil, "rt: initial kein ausstehender Raum")
check(RoomTransition.progress() == nil, "rt: initial kein Fortschritt")
check(RoomTransition.figureScale() == 1, "rt: figureScale 1 außerhalb der Transition")

-- --- 2) start/reset -------------------------------------------------------------
RoomTransition.start(2)
check(RoomTransition.active == true, "rt: start -> aktiv")
check(RoomTransition.pendingRoomIndex == 2, "rt: start -> pendingRoomIndex 2")
check(RoomTransition.isNewRoomLoaded() == false, "rt: start -> noch nicht geladen")
-- Ohne Kamera-Transition bleibt isActive false (aktiver Übergang = Kamera läuft).
check(RoomTransition.isActive() == false, "rt: ohne Kamera-Transition nicht aktiv")
RoomTransition.reset()
check(RoomTransition.active == false, "rt: reset -> inaktiv")
check(RoomTransition.pendingRoomIndex == nil, "rt: reset -> kein pending")
check(RoomTransition.isNewRoomLoaded() == false, "rt: reset -> nicht geladen")

-- --- 3) aktiver Übergang: progress/revealReached/markLoaded ----------------------
RoomTransition.reset()
RoomTransition.start(2)
startCameraTransition()
check(RoomTransition.isActive() == true, "rt: mit Kamera-Transition aktiv")
check(approx(RoomTransition.progress(), 0, 1e-9), "rt: Fortschritt 0 am Anfang")
check(RoomTransition.revealReached() == false, "rt: Reveal noch nicht erreicht (0)")
check(RoomTransition.isNewRoomLoaded() == false, "rt: neuer Raum noch nicht geladen")
Camera.update(Config.roomTransitionDuration * Config.roomTransRevealPoint)
local pMid = RoomTransition.progress()
check(pMid ~= nil and pMid >= Config.roomTransRevealPoint - 1e-6,
    "rt: Reveal-Punkt erreicht")
check(RoomTransition.revealReached() == true, "rt: revealReached true")
RoomTransition.markLoaded()
check(RoomTransition.isNewRoomLoaded() == true, "rt: markLoaded -> geladen")
-- Nach Kamera-Ende: isActive false (reset macht main.lua).
Camera.update(Config.roomTransitionDuration)
check(Camera.isTransitioning() == false, "rt: Kamera-Transition beendet")
check(RoomTransition.isActive() == false, "rt: nach Kamera-Ende nicht aktiv")
RoomTransition.reset()

-- --- 4) eased() ----------------------------------------------------------------
RoomTransition.reset()
RoomTransition.start(2)
startCameraTransition()
check(approx(RoomTransition.eased(), 0, 1e-9), "rt: eased 0 am Anfang")
Camera.update(Config.roomTransitionDuration * 0.25) -- elapsed 0.2125, progress 0.25
local e1 = RoomTransition.eased()
check(e1 ~= nil and e1 > 0 and e1 < 1, "rt: eased zwischen 0 und 1")
local function ss(t) return t * t * (3 - 2 * t) end
check(approx(e1, ss(0.25), 1e-6), "rt: eased = Smoothstep(0.25)")
Camera.update(Config.roomTransitionDuration * 0.5) -- progress 0.75
local e2 = RoomTransition.eased()
check(approx(e2, ss(0.75), 1e-6), "rt: eased = Smoothstep(0.75)")
check(e2 > e1, "rt: eased monoton steigend (Ease-In-Out, kein Overshoot)")
Camera.update(Config.roomTransitionDuration) -- Transition beendet
check(Camera.isTransitioning() == false, "rt: eased Ende -> Kamera fertig")
check(RoomTransition.eased() == nil, "rt: eased nil nach Kamera-Ende")
RoomTransition.reset()

-- --- 5) oldFade: 1 -> 0 über das Dissolve-Fenster --------------------------------
RoomTransition.reset()
local DS = Config.roomTransDissolveStart
local DE = Config.roomTransDissolveEnd
check(approx(RoomTransition.oldFade(0), 1, 1e-9), "rt: oldFade 1 vor Dissolve")
check(approx(RoomTransition.oldFade(DS), 1, 1e-9), "rt: oldFade 1 am Dissolve-Start")
check(approx(RoomTransition.oldFade(DE), 0, 1e-9), "rt: oldFade 0 am Dissolve-Ende")
check(approx(RoomTransition.oldFade(1), 0, 1e-9), "rt: oldFade 0 danach")
local mid = (DS + DE) / 2
check(approx(RoomTransition.oldFade(mid), 0.5, 1e-6), "rt: oldFade 0.5 in der Mitte")
check(approx(RoomTransition.oldFade(DS - 0.01), 1, 1e-9), "rt: oldFade außerhalb vor = 1")
check(approx(RoomTransition.oldFade(DE + 0.01), 0, 1e-9), "rt: oldFade außerhalb nach = 0")

-- --- 6) oldVisible: gestaffelt, deterministisch, kein gemeinsames Verschwinden ---
-- Verschiedene Seeds verschwinden zu verschiedenen Punkten im Fenster.
local ts = {}
for _, seed in ipairs({ "S1", "D1", "B1", "T", "P1", "player" }) do
    local a = 0
    for i = 0, 100 do
        local p = DS + (DE - DS) * (i / 100)
        if RoomTransition.oldVisible(p, seed) then
            a = p
        end
    end
    ts[seed] = a
end
local distinct = {}
for seed, t in pairs(ts) do distinct[#distinct + 1] = t end
local unique = true
for i = 1, #distinct do
    for j = i + 1, #distinct do
        if distinct[i] == distinct[j] then unique = false end
    end
end
check(#distinct > 1 and unique, "rt: oldVisible gestaffelt (Seeds verschieden)")
check(RoomTransition.oldVisible(DS, "S1") == true, "rt: oldVisible vor Fenster immer sichtbar")
check(RoomTransition.oldVisible(DE, "S1") == false, "rt: oldVisible am Fenster-Ende weg")
-- Monotonie: früher sichtbar -> später nie wieder sichtbar.
local mono = true
for i = 0, 99 do
    local p1 = DS + (DE - DS) * (i / 100)
    local p2 = DS + (DE - DS) * ((i + 1) / 100)
    if RoomTransition.oldVisible(p2, "S1") and not RoomTransition.oldVisible(p1, "S1") then
        mono = false
    end
end
check(mono, "rt: oldVisible monoton (kein Wiederauftauchen)")
-- Deterministisch: gleicher Seed, gleiches Verhalten.
check(RoomTransition.oldVisible(0.4, "B1") == RoomTransition.oldVisible(0.4, "B1"),
    "rt: oldVisible deterministisch")

-- --- 7) newVisible: gestaffelt im Kategorie-Fenster -------------------------------
local BS = Config.roomTransBridgeStart
local BE = Config.roomTransBridgeEnd
check(RoomTransition.newVisible(BS - 0.01, BS, BE, "B1") == false,
    "rt: newVisible vor Fenster unsichtbar")
check(RoomTransition.newVisible(BE, BS, BE, "B1") == true,
    "rt: newVisible am Fenster-Ende sichtbar")
check(RoomTransition.newVisible(1, BS, BE, "B1") == true,
    "rt: newVisible nach Fenster sichtbar")
-- Staffelung: verschiedene Seeds erscheinen zu verschiedenen Punkten.
local appears = {}
for _, seed in ipairs({ "S1", "D1", "B1", "T", "P1", "player" }) do
    local a = BE
    for i = 0, 100 do
        local p = BS + (BE - BS) * (i / 100)
        if RoomTransition.newVisible(p, BS, BE, seed) then
            a = p
            break
        end
    end
    appears[seed] = a
end
local aDistinct = {}
for seed, t in pairs(appears) do aDistinct[#aDistinct + 1] = t end
local aUnique = true
for i = 1, #aDistinct do
    for j = i + 1, #aDistinct do
        if aDistinct[i] == aDistinct[j] then aUnique = false end
    end
end
check(#aDistinct > 1 and aUnique, "rt: newVisible gestaffelt (Seeds verschieden)")

-- --- 8) futureImpulse: einmaliger Impuls, klingt ab --------------------------------
RoomTransition.reset()
RoomTransition.start(2)
startCameraTransition()
check(approx(RoomTransition.futureImpulse(0), Config.roomTransImpulsePx, 1e-9),
    "rt: futureImpulse max am Anfang")
local w = Config.roomTransImpulseWindow
check(RoomTransition.futureImpulse(w * 0.5) > 0
    and RoomTransition.futureImpulse(w * 0.5) < Config.roomTransImpulsePx,
    "rt: futureImpulse klingt ab")
check(approx(RoomTransition.futureImpulse(w), 0, 1e-9), "rt: futureImpulse 0 am Fenster-Ende")
check(approx(RoomTransition.futureImpulse(1), 0, 1e-9), "rt: futureImpulse 0 danach")
-- Außerhalb der Transition: 0 (kein Impuls, kein Puls).
RoomTransition.reset()
check(approx(RoomTransition.futureImpulse(), 0, 1e-9), "rt: futureImpulse 0 außerhalb")
RoomTransition.reset()

-- --- 9) futureWidth: wächst von Future-Linie zur vollen Bahnbreite ------------------
RoomTransition.reset()
RoomTransition.start(2)
startCameraTransition()
check(approx(RoomTransition.futureWidth(0), Config.futureRingLineWidth, 1e-6),
    "rt: futureWidth = Future-Linie am Anfang")
check(approx(RoomTransition.futureWidth(1), Config.trackWidth, 1e-6),
    "rt: futureWidth = Bahnbreite am Ende")
local midW = RoomTransition.futureWidth(0.5)
check(midW > Config.futureRingLineWidth and midW < Config.trackWidth,
    "rt: futureWidth wächst monoton dazwischen")
RoomTransition.reset()
check(approx(RoomTransition.futureWidth(0), Config.futureRingLineWidth, 1e-6),
    "rt: futureWidth außerhalb = Future-Linie")
RoomTransition.reset()

-- --- 10) figureScale: alte Phase subtil, neue Phase Landing --------------------------
RoomTransition.reset()
RoomTransition.start(2)
startCameraTransition()
-- Alte Phase (neuer Raum nicht geladen): subtile Ausbuchtung <= Bulge.
local bulgeMax = 0
for i = 0, 100 do
    local p = Config.roomTransRevealPoint * (i / 100)
    Camera.init(7)
    startCameraTransition()
    Camera.update(Config.roomTransitionDuration * p)
    -- progress ablesen und scale für die alte Phase berechnen
    local s = 1 + Config.roomTransFigureBulge * math.sin(math.pi * math.min(1, p / Config.roomTransRevealPoint))
    if s - 1 > bulgeMax then bulgeMax = s - 1 end
end
check(bulgeMax <= Config.roomTransFigureBulge + 1e-9,
    "rt: figureScale alte Phase max. Bulge (subtile 1-2 px)")
-- Neue Phase: markLoaded -> wächst von ScaleMin auf 1.
Camera.init(7)
startCameraTransition()
Camera.update(Config.roomTransitionDuration * Config.roomTransRevealPoint)
RoomTransition.markLoaded()
check(RoomTransition.isNewRoomLoaded() == true, "rt: figureScale Test markLoaded")
check(approx(RoomTransition.figureScale(), Config.roomTransFigureScaleMin, 1e-6),
    "rt: figureScale neue Phase = ScaleMin am Anfang")
Camera.update(Config.roomTransitionDuration * (Config.roomTransFigureEnd - Config.roomTransRevealPoint))
check(approx(RoomTransition.figureScale(), 1, 1e-6),
    "rt: figureScale neue Phase = 1 am Landing-Ende")
RoomTransition.reset()
check(RoomTransition.figureScale() == 1, "rt: figureScale nach reset = 1")

-- --- 11) Figuren-Kontinuität (Player/Baby werden KONTINUIERLICH radial
--         transformiert, kein Sprung/Despawn/Respawn) ----------------------
-- GLOBALE FIGURENREGEL (kontinuierlich): Während der GESAMTEN Transition
-- bleibt der WINKEL einer Figur KONSTANT — ihr EIGENER Winkel aus dem
-- Übergang (playerTransitionAngle / babyTransitionAngle). Keine tangentiale
-- Interpolation, kein autonomes Wandern, keine Bewegung zu
-- playerStartAngle/babyStartAngle. NUR der Radius transformiert — kontinuier-
-- lich von der Startposition (Kernrand des alten Raums / alter Ring) zur
-- Zielposition (finaler Radius des neuen Rings) mit derselben Transition-
-- funktion wie die Welt (eased Kamera-Fortschritt). KEIN Sprung am Reveal-
-- Punkt, kein Teleport am Ende. Der finale State-Handoff zur neuen Start-
-- position erfolgt erst NACH der Transition (dann liefert playerPosAndAngle
-- nil und das normale Rendering übernimmt die State-Position).
RoomTransition.reset()
check(RoomTransition.playerPosAndAngle() == nil, "rt-figur: inaktiv -> nil")
-- Realfall (Kernbrücken-Abschluss): Player startet am Kernrand des alten
-- Raums (Ring "center", alter Raum 1 -> Kernradius 37), Ziel = finaler neuer
-- Außenring (Ring 6 -> 104). Winkel bleibt der eigene (0).
RoomTransition.start(2)
RoomTransition.oldRoomIndex = 1
RoomTransition.captureFigures({ ring = "center", angle = 0 }, { ring = 6, angle = 180 }, nil, nil)
startCameraTransition()
local x0, y0, a0 = RoomTransition.playerPosAndAngle()
check(x0 ~= nil and y0 ~= nil, "rt-figur: Position während Transition vorhanden")
check(approx(y0, 120 - Config.coreRadius, 1e-6),
    "rt-figur: p=0 -> Kernrand des alten Raums (Winkel 0 -> oben)")
check(approx(a0, 0, 1e-6), "rt-figur: Winkel p=0 = eigener Winkel (0)")
-- Mitte: der Radius wandert kontinuierlich nach außen (eased Smoothstep),
-- der Winkel bleibt stabil (0). Kein tangentiales Wandern.
Camera.update(Config.roomTransitionDuration * 0.5)
local xm, ym, am = RoomTransition.playerPosAndAngle()
check(xm ~= nil and ym ~= nil, "rt-figur: Position in der Mitte vorhanden")
check(approx(am, 0, 1e-6), "rt-figur: Winkel in der Mitte konstant (KEIN Wandern)")
check(approx(xm, 200, 1e-6), "rt-figur: keine tangentiale Bewegung (x konstant)")
local rMid = Config.coreRadius + (Config.outerRadius - Config.coreRadius) * 0.5 -- smoothstep(0.5)=0.5
check(approx(ym, 120 - rMid, 1e-6),
    "rt-figur: Radius in der Mitte = eased Interpolation (gleiche Funktion wie die Welt)")
-- Reveal-Punkt: KEIN Sprung — die Figur folgt weiter derselben kontinuier-
-- lichen Radius-Kurve (markLoaded ändert die Position NICHT).
RoomTransition.markLoaded()
local xr, yr, ar = RoomTransition.playerPosAndAngle()
check(approx(ar, 0, 1e-6), "rt-figur: nach Reveal Winkel weiterhin konstant (0)")
check(approx(yr, ym, 1e-6),
    "rt-figur: nach Reveal KEIN Sprung (gleiche kontinuierliche Position)")
-- Nahe Ende: der Radius erreicht den finalen neuen Ring (104 oben); der
-- Winkel bleibt der EIGENE (0) — der neue Winkel (180) wird NIE interpoliert.
Camera.update(Config.roomTransitionDuration * 0.49)
local x1, y1, a1 = RoomTransition.playerPosAndAngle()
check(x1 ~= nil, "rt-figur: Position am Ende vorhanden (kein Verschwinden)")
check(approx(y1, 120 - Config.outerRadius, 1.5),
    "rt-figur: p~1 -> finaler neuer Ring (104 px oben), Winkel 0")
check(approx(a1, 0, 1e-6),
    "rt-figur: Winkel am Ende = EIGENER Winkel (nie Richtung neuer Winkel)")
-- Baby ohne erfasste Daten: nil (kein Baby im Übergang).
check(RoomTransition.babyPosAndAngle() == nil, "rt-figur: Baby ohne Daten -> nil")
-- Baby mit Daten: kontinuierlich, Winkel konstant (BabyFrom-Winkel), nur
-- radial — kein Despawn/Respawn, exakt dieselbe Radius-Kurve wie der Player.
RoomTransition.reset()
RoomTransition.start(2)
RoomTransition.oldRoomIndex = 1
RoomTransition.captureFigures({ ring = "center", angle = 90 }, { ring = 6, angle = 90 },
    { ring = "center", angle = 200 }, { ring = 6, angle = 20 })
startCameraTransition()
local bx, by, ba = RoomTransition.babyPosAndAngle()
check(bx ~= nil and by ~= nil, "rt-figur: Baby-Position während Transition vorhanden")
check(approx(ba, 200, 1e-6), "rt-figur: Baby-Winkel konstant (eigener Winkel 200)")
-- Baby bei Winkel 200 (unten): y = 120 - radius*cos(200°).
local cosBaby <const> = math.cos(math.rad(200))
check(approx(by, 120 - Config.coreRadius * cosBaby, 1e-3), "rt-figur: Baby p=0 am Kernrand")
Camera.update(Config.roomTransitionDuration * 0.5)
bx, by, ba = RoomTransition.babyPosAndAngle()
check(bx ~= nil and by ~= nil, "rt-figur: Baby in der Mitte weiterhin vorhanden")
check(approx(ba, 200, 1e-6), "rt-figur: Baby-Winkel in der Mitte konstant (kein Wandern)")
check(approx(by, 120 - rMid * cosBaby, 1e-3),
    "rt-figur: Baby-Radius in der Mitte = gleiche Kurve wie der Player")
-- Nach dem Reveal bleibt der Baby-Winkel ebenfalls konstant (200, nicht 20)
-- und die Position springt NICHT (gleiche kontinuierliche Kurve wie zuvor).
RoomTransition.markLoaded()
bx, by, ba = RoomTransition.babyPosAndAngle()
check(bx ~= nil and by ~= nil, "rt-figur: Baby nach Reveal vorhanden")
check(approx(ba, 200, 1e-6), "rt-figur: Baby-Winkel nach Reveal konstant (kein Wandern)")
check(approx(by, 120 - rMid * cosBaby, 1e-3),
    "rt-figur: Baby nach Reveal KEIN Sprung (kontinuierlich)")
RoomTransition.reset()

-- --- 12) Read-only: kein Gameplay-State-Zugriff --------------------------------------
RoomTransition.reset()
local trappedModules = { "State", "Undo", "Room", "Bridge", "Save", "Levels" }
local function withTrap(globalName, fn)
    local real = _G[globalName]
    _G[globalName] = setmetatable({}, {
        __index = function()
            error("trap: " .. globalName .. " während RoomTransition berührt")
        end,
    })
    local okTrap = pcall(fn)
    _G[globalName] = real
    return okTrap
end
for _, name in ipairs(trappedModules) do
    local okTrap = withTrap(name, function()
        RoomTransition.reset()
        RoomTransition.start(2)
        startCameraTransition()
        Camera.update(0.3)
        RoomTransition.progress()
        RoomTransition.eased()
        RoomTransition.oldFade()
        RoomTransition.oldVisible(0.4, "S1")
        RoomTransition.newVisible(0.7, 0.66, 0.78, "S1")
        RoomTransition.futureImpulse()
        RoomTransition.futureWidth()
        RoomTransition.figureScale()
        RoomTransition.revealReached()
        RoomTransition.reset()
    end)
    check(okTrap, "rt: " .. name .. " bleibt unberührt (Trap nicht ausgelöst)")
end

-- --- ringNameForRoom: tatsächliche Ringnummer -> Ringname des Zielraums ----
-- Beim radialen Raumwechsel schieben sich die Ringe eine Stufe nach außen
-- (alter Innenring = neuer Außenring). Die tatsächliche Ausgangs-Ringnummer
-- wird über die Ringnummern des neuen Raums auf den Ring-NAMEN aufgelöst —
-- Player und Baby behalten dadurch ihre echte Position (kein Levelstart-
-- Teleport). "center" (Kernbrücken-Abschluss) hat keinen Ring -> nil.
do
    local roomL2 = { rings = { outer = 6, inner = 5 } }
    local roomL1 = { rings = { outer = 7, inner = 6 } }
    -- L1 inner (6) wird L2 outer (6).
    check(RoomTransition.ringNameForRoom(6, roomL2) == "outer",
        "ringmap: L1 inner 6 -> L2 outer (Ringnummer 6)")
    -- L2 inner (5) bleibt inner (kein nächster Ring nötig, Name stimmt).
    check(RoomTransition.ringNameForRoom(5, roomL2) == "inner",
        "ringmap: L2 inner 5 -> inner")
    -- L1 outer (7) passt nicht in L2 (6/5) -> nil (Levelstart-Ring behalten).
    check(RoomTransition.ringNameForRoom(7, roomL2) == nil,
        "ringmap: unbekannte Nummer -> nil")
    -- L1 inner (6) -> L1 inner (gleicher Raum, Ringnummer 6).
    check(RoomTransition.ringNameForRoom(6, roomL1) == "inner",
        "ringmap: Ringnummer 6 in L1 (7/6) -> inner")
    -- "center" (Kernbrücken-Abschluss): kein Ring.
    check(RoomTransition.ringNameForRoom("center", roomL2) == nil,
        "ringmap: center -> nil (Levelstart-Ring behalten)")
    check(RoomTransition.ringNameForRoom(nil, roomL2) == nil,
        "ringmap: nil -> nil")
    check(RoomTransition.ringNameForRoom(6, nil) == nil,
        "ringmap: ohne Zielraum -> nil")
end

TestReport.roomTransition = { pass = pass, fail = fail }
