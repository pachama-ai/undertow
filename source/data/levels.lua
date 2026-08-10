-- Ein Raum:
-- rings = { outer = <Ringnummer>, inner = <Ringnummer> }
-- start = { ring = "outer", angle = 0 }
-- switches = { { id, ring, angle, symbol, onA, onB, state } }
--   state ist "A" oder "B" beim Start.
--   onA/onB sind IDs von Blenden oder Brücken.
--   In Zustand A ist onA aktiv (Brücke ausgefahren / Blende offen),
--   onB inaktiv. In Zustand B umgekehrt. Immer genau eines.
-- shutters = { { id, ring, angle } }        -- Blende, Bogenbreite aus config
-- bridges  = { { id, angle, free } }        -- verbindet outer und inner
--   free = true bedeutet dauerhaft ausgefahren, von keinem Schalter gesteuert.
-- gate     = { id = "T", angle, free }      -- Kernbrücke, sitzt auf dem inneren Ring
-- symbol: 1 = Punkt, 2 = zwei Punkte, 3 = Strich

-- Alle sechs Räume, exakt in dieser Reihenfolge.
Levels = {

    -------------------------------------------------------------------- 1
    {
        name = "Ein Anlauf",
        rings = { outer = 7, inner = 6 },
        start = { ring = "outer", angle = 0 },

        switches = {
            { id="S1", ring="outer", angle=90, symbol=1, onA="B1", onB="D1", state="B" },
        },

        shutters = {
            { id="D1", ring="outer", angle=315 },
        },

        bridges = {
            { id="B1", angle=270, free=false },
        },

        gate = { id="T", angle=180, free=true },
    },

    -------------------------------------------------------------------- 2
    {
        name = "Die ganze Runde",
        rings = { outer = 6, inner = 5 },
        start = { ring = "outer", angle = 0 },

        switches = {
            { id="S1", ring="outer", angle=45,  symbol=1, onA="B1", onB="D1", state="B" },
            { id="S2", ring="outer", angle=315, symbol=2, onA="T",  onB="D2", state="B" },
        },

        shutters = {
            { id="D1", ring="inner", angle=225 },
            { id="D2", ring="inner", angle=90 },
        },

        bridges = {
            { id="B1", angle=135, free=false },
        },

        gate = { id="T", angle=180, free=false },
    },

    -------------------------------------------------------------------- 3
    {
        name = "Der lange Weg",
        rings = { outer = 5, inner = 4 },
        start = { ring = "outer", angle = 0 },

        switches = {
            { id="S1", ring="outer", angle=45, symbol=1, onA="T", onB="D1", state="B" },
        },

        shutters = {
            { id="D1", ring="inner", angle=315 },
        },

        bridges = {
            { id="B0", angle=270, free=true },
        },

        gate = { id="T", angle=0, free=false },
    },

    -------------------------------------------------------------------- 4
    {
        name = "Der Umbau",
        rings = { outer = 4, inner = 3 },
        start = { ring = "outer", angle = 0 },

        switches = {
            { id="S1", ring="outer", angle=45,  symbol=1, onA="T",  onB="B2", state="B" },
            { id="S2", ring="inner", angle=135, symbol=2, onA="D1", onB="D2", state="B" },
        },

        shutters = {
            { id="D1", ring="inner", angle=315 },
            { id="D2", ring="inner", angle=45 },
        },

        bridges = {
            { id="B0", angle=90,  free=true },
            { id="B2", angle=180, free=false },
        },

        gate = { id="T", angle=0, free=false },
    },

    -------------------------------------------------------------------- 5
    {
        name = "Fernwirkung",
        rings = { outer = 3, inner = 2 },
        start = { ring = "outer", angle = 0 },

        switches = {
            { id="S1", ring="outer", angle=270, symbol=1, onA="T",  onB="D2", state="B" },
            { id="S2", ring="inner", angle=180, symbol=2, onA="D1", onB="B1", state="B" },
        },

        shutters = {
            { id="D1", ring="outer", angle=180 },
            { id="D2", ring="inner", angle=315 },
        },

        bridges = {
            { id="B0", angle=90,  free=true },
            { id="B1", angle=225, free=false },
        },

        gate = { id="T", angle=0, free=false },
    },

    -------------------------------------------------------------------- 6
    {
        name = "Die Umkehr",
        rings = { outer = 2, inner = 1 },
        start = { ring = "outer", angle = 0 },

        switches = {
            { id="S1", ring="outer", angle=180, symbol=1, onA="B1", onB="D2", state="A" },
            { id="S2", ring="inner", angle=90,  symbol=2, onA="D1", onB="T",  state="A" },
        },

        shutters = {
            { id="D1", ring="outer", angle=270 },
            { id="D2", ring="inner", angle=315 },
        },

        bridges = {
            { id="B0", angle=45,  free=true },
            { id="B1", angle=135, free=false },
        },

        gate = { id="T", angle=0, free=false },
    },

}

-- Datenvalidator: nur lesend, verändert die Daten nicht.
-- Abnahme-/Entwicklungslogik, keine Spielmechanik.
-- Gibt die Anzahl gefundener Datenfehler zurück; 0 = konsistent.
function Levels.validate()
    local errorCount = 0

    local function report(roomIndex, roomName, id, rule)
        errorCount = errorCount + 1
        local idPart = ""
        if id then
            idPart = " (ID: " .. id .. ")"
        end
        print("Raum " .. roomIndex .. ' "' .. roomName .. '": ' .. rule .. idPart)
    end

    if #Levels ~= 6 then
        errorCount = errorCount + 1
        print("Levels: Anzahl der Räume ist " .. #Levels .. " statt 6")
    end

    for roomIndex, room in ipairs(Levels) do
        local roomName = room.name or "<ohne Name>"
        local before = errorCount

        -- Struktur des Raums
        if room.name == nil then
            report(roomIndex, roomName, nil, "Raum hat kein name")
        end
        if type(room.rings) ~= "table" then
            report(roomIndex, roomName, nil, "Raum hat kein rings")
        else
            if room.rings.outer == nil then report(roomIndex, roomName, nil, "rings.outer fehlt") end
            if room.rings.inner == nil then report(roomIndex, roomName, nil, "rings.inner fehlt") end
        end
        if type(room.start) ~= "table" then
            report(roomIndex, roomName, nil, "Raum hat kein start")
        else
            if room.start.ring ~= "outer" then report(roomIndex, roomName, nil, 'start.ring ist nicht "outer"') end
            if room.start.angle ~= 0 then report(roomIndex, roomName, nil, "start.angle ist nicht 0") end
        end

        -- Elemente sammeln (Blenden, Brücken, Tor)
        local elements = {}          -- id -> { kind = "shutter"|"bridge"|"gate", free = bool|nil }
        local controlCount = {}      -- id -> Anzahl der Steuerreferenzen (onA + onB)
        local switchIds = {}

        local function registerElement(id, kind, free)
            if elements[id] then
                report(roomIndex, roomName, id, "Element-ID doppelt vergeben")
            end
            elements[id] = { kind = kind, free = free }
        end

        for _, s in ipairs(room.shutters or {}) do
            if s.id == nil or s.ring == nil or s.angle == nil then
                report(roomIndex, roomName, s.id, "Blende unvollständig (id/ring/angle)")
            else
                registerElement(s.id, "shutter", nil)
            end
        end

        for _, b in ipairs(room.bridges or {}) do
            if b.id == nil or b.angle == nil or b.free == nil then
                report(roomIndex, roomName, b.id, "Brücke unvollständig (id/angle/free)")
            else
                registerElement(b.id, "bridge", b.free)
            end
        end

        if type(room.gate) == "table" then
            if room.gate.id == nil or room.gate.angle == nil or room.gate.free == nil then
                report(roomIndex, roomName, "gate", "Tor unvollständig (id/angle/free)")
            else
                registerElement(room.gate.id, "gate", room.gate.free)
            end
        else
            report(roomIndex, roomName, nil, "Raum hat kein gate")
        end

        for _, sw in ipairs(room.switches or {}) do
            local swId = sw.id or "<ohne id>"
            if switchIds[swId] then
                report(roomIndex, roomName, swId, "Schalter-ID doppelt")
            end
            switchIds[swId] = true

            if sw.id == nil or sw.ring == nil or sw.angle == nil or sw.symbol == nil
                or sw.onA == nil or sw.onB == nil or sw.state == nil then
                report(roomIndex, roomName, swId, "Schalter unvollständig (id/ring/angle/symbol/onA/onB/state)")
            end
            if sw.symbol ~= 1 and sw.symbol ~= 2 and sw.symbol ~= 3 then
                report(roomIndex, roomName, swId, "symbol ist nicht 1/2/3")
            end
            if sw.state ~= "A" and sw.state ~= "B" then
                report(roomIndex, roomName, swId, 'state ist nicht "A"/"B"')
            end
            if sw.ring ~= "outer" and sw.ring ~= "inner" then
                report(roomIndex, roomName, swId, 'ring ist nicht "outer"/"inner"')
            end

            -- F: onA ~= onB
            if sw.onA ~= nil and sw.onB ~= nil and sw.onA == sw.onB then
                report(roomIndex, roomName, swId, "onA und onB sind gleich")
            end

            -- A: Referenzen existieren
            if sw.onA ~= nil and not elements[sw.onA] then
                report(roomIndex, roomName, sw.onA, "onA verweist auf nicht existierendes Element")
            end
            if sw.onB ~= nil and not elements[sw.onB] then
                report(roomIndex, roomName, sw.onB, "onB verweist auf nicht existierendes Element")
            end

            -- Steuerungszählung (B/C/D/E)
            if sw.onA ~= nil then controlCount[sw.onA] = (controlCount[sw.onA] or 0) + 1 end
            if sw.onB ~= nil then controlCount[sw.onB] = (controlCount[sw.onB] or 0) + 1 end
        end

        -- B: kein Element von mehr als einem Schalter gesteuert
        for id, count in pairs(controlCount) do
            if count > 1 then
                report(roomIndex, roomName, id, "Element wird von mehr als einem Schalter gesteuert")
            end
        end

        -- C/D/E: Steuerung pro Element
        for id, el in pairs(elements) do
            local controlled = controlCount[id] or 0
            if el.kind == "shutter" then
                if controlled ~= 1 then
                    report(roomIndex, roomName, id, "Blende wird nicht genau von einem Schalter gesteuert")
                end
            elseif el.kind == "bridge" then
                if el.free == true then
                    if controlled ~= 0 then
                        report(roomIndex, roomName, id, "Freie Brücke wird von einem Schalter gesteuert")
                    end
                elseif controlled ~= 1 then
                    report(roomIndex, roomName, id, "Nicht-freie Brücke wird nicht genau von einem Schalter gesteuert")
                end
            elseif el.kind == "gate" then
                if el.free == true then
                    if controlled ~= 0 then
                        report(roomIndex, roomName, id, "Freies Tor wird von einem Schalter gesteuert")
                    end
                elseif controlled ~= 1 then
                    report(roomIndex, roomName, id, "Nicht-freies Tor wird nicht genau von einem Schalter gesteuert")
                end
            end
        end

        if errorCount == before then
            print("Raum " .. roomIndex .. ": OK")
        end
    end

    return errorCount
end

return Levels