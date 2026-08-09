-- Abnahme-Tests für source/core/geometry.lua (globale Tabelle Geometry).
-- Ausführung über tools/run_tests.ps1 im Playdate-Simulator; der Runner
-- importiert Geometry, bevor diese Datei importiert wird.
-- Keine externen Testbibliotheken. Ausgabe über print().

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

local function approxEqual(a, b, tolerance)
    return math.abs(a - b) <= (tolerance or 0.0001)
end

-- --- norm() ---
check(Geometry.norm(0) == 0, "norm(0) == 0")
check(Geometry.norm(360) == 0, "norm(360) == 0")
check(Geometry.norm(720) == 0, "norm(720) == 0")
check(Geometry.norm(-360) == 0, "norm(-360) == 0")
check(Geometry.norm(-10) == 350, "norm(-10) == 350")
check(Geometry.norm(370) == 10, "norm(370) == 10")
check(Geometry.norm(10.5) == 10.5, "norm(10.5) == 10.5 (Fließkomma)")

-- --- delta() ---
check(Geometry.delta(10, 20) == 10, "delta(10,20) == 10")
check(Geometry.delta(350, 10) == 20, "delta(350,10) == 20")
check(Geometry.delta(10, 350) == -20, "delta(10,350) == -20")
check(Geometry.delta(90, 45) == -45, "delta(90,45) == -45")
check(Geometry.delta(45, 90) == 45, "delta(45,90) == 45")
check(Geometry.delta(0, 180) == 180, "delta(0,180) == 180")
check(Geometry.delta(180, 0) == 180, "delta(180,0) == 180")

-- --- inArc() ---
check(Geometry.inArc(355, 350, 20) == true, "inArc(355,350,20) == true")
check(Geometry.inArc(0, 350, 20) == true, "inArc(0,350,20) == true")
check(Geometry.inArc(10, 350, 20) == true, "inArc(10,350,20) == true")
check(Geometry.inArc(20, 350, 20) == false, "inArc(20,350,20) == false")
check(Geometry.inArc(340, 350, 20) == false, "inArc(340,350,20) == false")
check(Geometry.inArc(350, 350, 20) == true, "inArc(350,350,20) == true (Startrand)")
check(Geometry.inArc(10, 350, 20) == true, "inArc(10,350,20) == true (Endrand)")
check(Geometry.inArc(350, 350, 0) == true, "inArc(350,350,0) == true (width=0)")
check(Geometry.inArc(351, 350, 0) == false, "inArc(351,350,0) == false (width=0)")
check(Geometry.inArc(123, 350, 360) == true, "inArc(123,350,360) == true (Vollkreis)")

-- --- crossed(fromAngle, delta, targetAngle) ---
-- 0°-Grenze
check(Geometry.crossed(350, 20, 0) == 1, "crossed(350,20,0) == 1")
check(Geometry.crossed(10, -20, 0) == -1, "crossed(10,-20,0) == -1")
-- normale Bewegungen
check(Geometry.crossed(80, 20, 90) == 1, "crossed(80,20,90) == 1")
check(Geometry.crossed(100, -20, 90) == -1, "crossed(100,-20,90) == -1")
check(Geometry.crossed(80, 5, 90) == 0, "crossed(80,5,90) == 0")
-- Startpunkt ausgeschlossen, Endpunkt eingeschlossen
check(Geometry.crossed(90, 10, 90) == 0, "crossed(90,10,90) == 0 (Startpunkt)")
check(Geometry.crossed(90, 0, 90) == 0, "crossed(90,0,90) == 0 (delta 0)")
check(Geometry.crossed(80, 10, 90) == 1, "crossed(80,10,90) == 1 (Endpunkt erreicht)")
-- große Bewegungen > 180°
check(Geometry.crossed(10, 240, 100) == 1, "crossed(10,240,100) == 1")
check(Geometry.crossed(10, 240, 200) == 1, "crossed(10,240,200) == 1")
check(Geometry.crossed(250, 120, 350) == 1, "crossed(250,120,350) == 1")
check(Geometry.crossed(10, -120, 350) == -1, "crossed(10,-120,350) == -1")
-- volle Umdrehungen
check(Geometry.crossed(10, 360, 100) == 1, "crossed(10,360,100) == 1 (+360)")
check(Geometry.crossed(10, -360, 100) == -1, "crossed(10,-360,100) == -1 (-360)")
check(Geometry.crossed(10, 720, 100) == 1, "crossed(10,720,100) == 1 (+720)")
check(Geometry.crossed(10, -720, 100) == -1, "crossed(10,-720,100) == -1 (-720)")
-- Start == Ziel mit voller Runde: erneut überstrichen
check(Geometry.crossed(10, 360, 10) == 1, "crossed(10,360,10) == 1 (+360 auf Start)")
check(Geometry.crossed(10, -360, 10) == -1, "crossed(10,-360,10) == -1 (-360 auf Start)")

-- --- polar() ---
do
    local x, y = Geometry.polar(200, 120, 100, 0)
    check(approxEqual(x, 200) and approxEqual(y, 20), "polar(...,0) -> 200,20")
    x, y = Geometry.polar(200, 120, 100, 90)
    check(approxEqual(x, 300) and approxEqual(y, 120), "polar(...,90) -> 300,120")
    x, y = Geometry.polar(200, 120, 100, 180)
    check(approxEqual(x, 200) and approxEqual(y, 220), "polar(...,180) -> 200,220")
    x, y = Geometry.polar(200, 120, 100, 270)
    check(approxEqual(x, 100) and approxEqual(y, 120), "polar(...,270) -> 100,120")
end

TestReport.geometry = { pass = pass, fail = fail }