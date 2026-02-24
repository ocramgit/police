local QBCore = exports['qb-core']:GetCoreObject()

local myRole           = nil
local roundActive      = false
local spawnedVehicle   = nil
local tempBlips        = {}
local zoneBlip         = nil
local isFrozen         = false
local outOfBoundsWarn  = false
local lastPositions    = {}
local zoneData         = nil
local chaosEntities    = {}   -- props, peds e veículos de caos
local waveModeActive   = true -- recebido no assignRole
local currentWave      = 0    -- onda actual (para kills feed etc)
local barrierActive    = false -- controla a thread do muro visual

-- ── Modelos de rampas por tamanho ─────────────────────────────
local RAMP_PROPS = {
    small  = { 'prop_mp_ramp_02' },
    medium = { 'prop_mp_ramp_03', 'prop_mp_ramp_02' },
    large  = { 'prop_mp_ramp_06', 'prop_mp_ramp_03' },
}

-- ── Utilitários ──────────────────────────────────────────────

local function notify(msg, msgType, dur)
    QBCore.Functions.Notify(msg, msgType or 'primary', dur or 7000)
end

local function randomFrom(tbl)
    return tbl[math.random(#tbl)]
end

-- ── Upgrade de veículo ────────────────────────────────────────

local function upgradeVehicle(veh)
    SetVehicleModKit(veh, 0)
    for modType = 0, 49 do
        local maxMod = GetNumVehicleMods(veh, modType) - 1
        if maxMod >= 0 then SetVehicleMod(veh, modType, maxMod, false) end
    end
    ToggleVehicleMod(veh, 18, true)
    ToggleVehicleMod(veh, 22, true)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleWheelsCanBreak(veh, false)
    SetVehicleFixed(veh)
end

-- ── Spawn de veículo ──────────────────────────────────────────

local function spawnVehicle(model, coords)
    local hash = GetHashKey(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Citizen.Wait(100) end

    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        DeleteEntity(spawnedVehicle)
        spawnedVehicle = nil
    end

    local veh   = CreateVehicle(hash, coords.x, coords.y, coords.z + 0.5, coords.w, true, false)
    local plate = 'JOGO' .. math.random(1000, 9999)
    SetVehicleNumberPlateText(veh, plate)
    SetModelAsNoLongerNeeded(hash)
    upgradeVehicle(veh)

    spawnedVehicle = veh

    -- Manter desbloqueado
    Citizen.CreateThread(function()
        while roundActive do
            if DoesEntityExist(veh) then
                SetVehicleDoorsLocked(veh, 0)
            end
            Citizen.Wait(500)
        end
    end)

    TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', plate)
    TriggerServerEvent('vehiclekeys:server:setVehicleOwner',       plate)

    return veh
end

local function warpIntoCar(veh)
    if DoesEntityExist(veh) then
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
    end
end

local function giveWeaponNow(weapon, ammo)
    local ped  = PlayerPedId()
    local hash = GetHashKey(weapon)
    GiveWeaponToPed(ped, hash, ammo, false, true)
    SetCurrentPedWeapon(ped, hash, true)
end

local function removeAllWeapons()
    RemoveAllPedWeapons(PlayerPedId(), true)
end

-- ── Freeze ───────────────────────────────────────────────────

local freezeGen = 0

local function freezePlayer(active)
    isFrozen = active
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, active)
    SetEntityInvincible(ped, active)

    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        FreezeEntityPosition(spawnedVehicle, active)
        if active then
            SetVehicleEngineOn(spawnedVehicle, false, true, true)
        else
            FreezeEntityPosition(spawnedVehicle, false)
            SetVehicleEngineOn(spawnedVehicle, true, false, true)
        end
    end

    if active then
        freezeGen = freezeGen + 1
        local myGen = freezeGen
        Citizen.CreateThread(function()
            while isFrozen and freezeGen == myGen do
                DisableControlAction(0, 30,  true)
                DisableControlAction(0, 31,  true)
                DisableControlAction(0, 21,  true)
                DisableControlAction(0, 22,  true)
                DisableControlAction(0, 24,  true)
                DisableControlAction(0, 25,  true)
                DisableControlAction(0, 263, true)
                DisableControlAction(0, 71,  true)
                DisableControlAction(0, 72,  true)
                DisableControlAction(0, 59,  true)
                DisableControlAction(0, 63,  true)
                DisableControlAction(0, 75,  true)
                local veh = spawnedVehicle
                if veh and DoesEntityExist(veh) then
                    SetEntityVelocity(veh, 0.0, 0.0, 0.0)
                    FreezeEntityPosition(veh, true)
                end
                Citizen.Wait(0)
            end
            FreezeEntityPosition(PlayerPedId(), false)
            SetEntityInvincible(PlayerPedId(), false)
            if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
                FreezeEntityPosition(spawnedVehicle, false)
                SetVehicleEngineOn(spawnedVehicle, true, false, true)
            end
        end)
    end
end

-- ── Zona ─────────────────────────────────────────────────────

-- ── Barreira visual da zona (muro de marcadores) ────────────
-- Desenha 72 pilares ao longo do perímetro a cada frame.
-- Visível para o jogador como um "muro" laranja/vermelho brilhante.

local function startZoneBarrier()
    if barrierActive then return end
    barrierActive = true
    local STEPS       = 72          -- quantos pilares no círculo (a cada 5°)
    local PILLAR_H    = 15.0        -- altura de cada pilar (metros)
    local PILLAR_W    = 5.0         -- largura do marcador
    local STEP_RAD    = (math.pi * 2) / STEPS

    Citizen.CreateThread(function()
        while barrierActive do
            if not zoneData then
                Citizen.Wait(500)
            else
                local cx, cy, cz = zoneData.x, zoneData.y, zoneData.z
                local r           = zoneData.radius
                local myPos       = GetEntityCoords(PlayerPedId())
                local dist2d      = math.sqrt((myPos.x - cx)^2 + (myPos.y - cy)^2)

                -- Só renderizar pilares próximos do jogador para poupar resources
                for i = 0, STEPS - 1 do
                    local angle = i * STEP_RAD
                    local px    = cx + math.cos(angle) * r
                    local py    = cy + math.sin(angle) * r

                    local distToMarker = math.sqrt((myPos.x - px)^2 + (myPos.y - py)^2)
                    if distToMarker < 350.0 then
                        -- Cor: laranja dentro da zona, vermelho fora
                        local inside = dist2d <= r
                        local r_c = inside and 255 or 220
                        local g_c = inside and 100 or  30
                        local b_c = inside and  20 or  20
                        local a_c = inside and 120 or 180

                        -- Marker tipo 1 = cylinder
                        DrawMarker(1,
                            px, py, cz,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            PILLAR_W, PILLAR_W, PILLAR_H,
                            r_c, g_c, b_c, a_c,
                            false, true, 2, nil, nil, false)
                    end
                end

                Citizen.Wait(0)
            end
        end
    end)
end

local function showZone(x, y, z, radius)
    zoneData = { x = x, y = y, z = z, radius = radius }
    if zoneBlip then RemoveBlip(zoneBlip) end
    zoneBlip = AddBlipForRadius(x, y, z, radius)
    SetBlipColour(zoneBlip, 2)
    SetBlipAlpha(zoneBlip, 90)
    startZoneBarrier()
end

local function removeZone()
    barrierActive = false
    if zoneBlip then RemoveBlip(zoneBlip) end
    zoneBlip = nil
    zoneData = nil
end

-- ── Limpeza de caos ───────────────────────────────────────────

local function cleanupChaos()
    for _, e in ipairs(chaosEntities) do
        if DoesEntityExist(e) then
            SetEntityAsMissionEntity(e, true, true)
            NetworkRequestControlOfEntity(e)
            DeleteEntity(e)
        end
    end
    chaosEntities = {}
    rampCount     = 0
    rampList      = {}

    local myCoords = GetEntityCoords(PlayerPedId())
    local handle, veh = FindFirstVehicle()
    local found = handle ~= -1
    while found do
        if DoesEntityExist(veh) then
            local vCoords = GetEntityCoords(veh)
            local dist    = #(myCoords - vCoords)
            if dist < 500.0 and not IsVehicleSeatFree(veh, -1) == false then
                local driver = GetPedInVehicleSeat(veh, -1)
                if driver == 0 or not IsPedAPlayer(driver) then
                    SetEntityAsMissionEntity(veh, true, true)
                    NetworkRequestControlOfEntity(veh)
                    DeleteEntity(veh)
                end
            end
        end
        found, veh = FindNextVehicle(handle)
    end
    EndFindVehicle(handle)
end

-- ── Spawn de rampa numa posição de estrada ───────────────────

local rampCount   = 0
local MAX_RAMPS   = 80
local rampList    = {}

local function spawnRampOnRoad(nx, ny, nz, size)
    if rampCount >= MAX_RAMPS then
        local oldest = table.remove(rampList, 1)
        if oldest and DoesEntityExist(oldest) then DeleteEntity(oldest) end
        rampCount = rampCount - 1
    end

    local models = RAMP_PROPS[size] or RAMP_PROPS.medium
    local model  = randomFrom(models)
    local hash   = GetHashKey(model)

    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 30 do Citizen.Wait(100); t = t + 1 end
    if not HasModelLoaded(hash) then SetModelAsNoLongerNeeded(hash); return false end

    local gFound, gz = GetGroundZFor_3dCoord(nx, ny, nz + 50.0, false)
    local finalZ = gFound and gz or nz

    local prop = CreateObject(hash, nx, ny, finalZ + 0.1, true, true, false)
    if not DoesEntityExist(prop) then SetModelAsNoLongerNeeded(hash); return false end

    local headings = {0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0}
    SetEntityHeading(prop, headings[math.random(#headings)])
    PlaceObjectOnGroundProperly(prop)
    FreezeEntityPosition(prop, true)
    SetEntityCollision(prop, true, true)
    SetModelAsNoLongerNeeded(hash)

    rampList[#rampList + 1]          = prop
    chaosEntities[#chaosEntities + 1] = prop
    rampCount = rampCount + 1
    return true
end

-- ── Spawn de veículo de perseguição ───────────────────────────

local chaseCarModels = {'blista', 'issi2', 'sultan', 'banshee2', 'ruiner2', 'dominator', 'elegy2'}

local function spawnChaseVehicle()
    local coords = GetEntityCoords(PlayerPedId())
    local angle  = math.random() * math.pi * 2
    local dist   = math.random(120, 220)
    local px     = coords.x + math.cos(angle) * dist
    local py     = coords.y + math.sin(angle) * dist

    RequestCollisionAtCoord(px, py, coords.z)
    Citizen.Wait(200)
    local found, gz = GetGroundZFor_3dCoord(px, py, coords.z + 50.0, false)
    if not found then return end

    local carHash = GetHashKey(randomFrom(chaseCarModels))
    RequestModel(carHash)
    local t = 0
    while not HasModelLoaded(carHash) and t < 25 do Citizen.Wait(100); t = t + 1 end
    if not HasModelLoaded(carHash) then SetModelAsNoLongerNeeded(carHash); return end

    local veh = CreateVehicle(carHash, px, py, gz + 0.5, math.random(0, 359) * 1.0, true, false)
    SetVehicleEngineOn(veh, true, false, true)
    SetModelAsNoLongerNeeded(carHash)

    local dHash = GetHashKey('a_m_y_downtown_01')
    RequestModel(dHash)
    t = 0
    while not HasModelLoaded(dHash) and t < 20 do Citizen.Wait(100); t = t + 1 end
    if HasModelLoaded(dHash) then
        local driver = CreatePedInsideVehicle(veh, 26, dHash, -1, true, false)
        SetDriverAggressiveness(driver, 1.0)
        SetDriverAbility(driver, 1.0)
        TaskVehicleChase(driver, PlayerPedId())
        SetModelAsNoLongerNeeded(dHash)
        chaosEntities[#chaosEntities + 1] = driver
    end
    chaosEntities[#chaosEntities + 1] = veh
end

-- ── Utilitário de estrada perto ────────────────────────────────

local function roadNear(dist)
    local c = GetEntityCoords(PlayerPedId())
    local a = math.random() * math.pi * 2
    local ok, nd = GetClosestVehicleNode(c.x + math.cos(a)*dist, c.y + math.sin(a)*dist, c.z, 0, 3.0, 0)
    return (ok and nd) or nil
end

-- ── ROADBLOCKS NPC ────────────────────────────────────────────
-- Spawna barricadas de polícia NPC na zona; chamado no início para TODOS (cops e robbers)

local function spawnRoadblocks(count)
    Citizen.CreateThread(function()
        Citizen.Wait(6000)  -- esperar pelo spawn do jogador
        if not roundActive or not zoneData then return end

        local roadblockCars  = {'police2', 'police3', 'sheriff'}
        local swatHash       = GetHashKey('s_m_y_swat_01')
        RequestModel(swatHash)
        local t0 = 0
        while not HasModelLoaded(swatHash) and t0 < 20 do Citizen.Wait(100); t0 = t0 + 1 end

        notify('🚧 ' .. count .. ' Roadblocks de polícia activados na zona!', 'warning', 5000)

        for i = 1, count do
            if not roundActive then break end

            -- Ponto aleatório no raio da zona (entre 50% e 90% do raio)
            local angle    = math.random() * math.pi * 2
            local rFrac    = 0.5 + math.random() * 0.4
            local px       = zoneData.x + math.cos(angle) * zoneData.radius * rFrac
            local py       = zoneData.y + math.sin(angle) * zoneData.radius * rFrac

            local roadOk, nodePos = GetClosestVehicleNode(px, py, zoneData.z, 0, 3.0, 0)
            if not roadOk or not nodePos then goto nextRB end

            do
                local carH = GetHashKey(randomFrom(roadblockCars))
                RequestModel(carH)
                local t = 0
                while not HasModelLoaded(carH) and t < 25 do Citizen.Wait(100); t = t + 1 end
                if not HasModelLoaded(carH) then goto nextRB end

                local rbVeh = CreateVehicle(carH, nodePos.x, nodePos.y, nodePos.z + 0.5,
                    math.random(0, 359) * 1.0, true, false)
                SetVehicleEngineOn(rbVeh, false, true, true)
                FreezeEntityPosition(rbVeh, true)
                SetVehicleCanBeVisiblyDamaged(rbVeh, false)
                SetVehicleWheelsCanBreak(rbVeh, false)
                SetModelAsNoLongerNeeded(carH)
                chaosEntities[#chaosEntities + 1] = rbVeh

                -- 2 SWAT ao lado do carro
                for s = 1, 2 do
                    if HasModelLoaded(swatHash) then
                        local offsetX = nodePos.x + (s == 1 and 3.0 or -3.0)
                        local offsetY = nodePos.y + math.random(-1, 1) * 1.0
                        local swat = CreatePed(26, swatHash, offsetX, offsetY, nodePos.z, 0.0, true, false)
                        SetEntityInvincible(swat, false)
                        GiveWeaponToPed(swat, GetHashKey('weapon_carbinerifle'), 120, false, true)
                        SetPedRelationshipGroupHash(swat, GetHashKey('COP'))
                        SetPedKeepTask(swat, true)
                        -- Em guarda (CombatPed) — vai atacar o ladrão se entrar no raio
                        TaskGuardCurrentPosition(swat, 15.0, 15.0, true)
                        chaosEntities[#chaosEntities + 1] = swat
                    end
                end
            end

            ::nextRB::
            Citizen.Wait(800)
        end
        SetModelAsNoLongerNeeded(swatHash)
    end)
end

-- ── CAOS PRINCIPAL ────────────────────────────────────────────

local function startChaosZone()
    rampCount = 0
    rampList  = {}

    -- 1. Rampa especial fixa
    Citizen.CreateThread(function()
        local hash = GetHashKey('prop_mp_ramp_03')
        RequestModel(hash)
        local t = 0
        while not HasModelLoaded(hash) and t < 40 do Citizen.Wait(100); t = t + 1 end
        if HasModelLoaded(hash) then
            local prop = CreateObject(hash, 182.22, -809.06, 31.18, true, true, false)
            if DoesEntityExist(prop) then
                SetEntityHeading(prop, 158.14)
                PlaceObjectOnGroundProperly(prop)
                FreezeEntityPosition(prop, true)
                SetEntityCollision(prop, true, true)
                chaosEntities[#chaosEntities + 1] = prop
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end)

    -- 2. Tráfego extremo
    Citizen.CreateThread(function()
        while roundActive do
            SetVehicleDensityMultiplierThisFrame(5.0)
            SetRandomVehicleDensityMultiplierThisFrame(5.0)
            SetParkedVehicleDensityMultiplierThisFrame(3.0)
            SetPedDensityMultiplierThisFrame(3.0)
            SetScenarioPedDensityMultiplierThisFrame(3.0, 3.0)
            Citizen.Wait(0)
        end
        SetVehicleDensityMultiplierThisFrame(1.0)
        SetRandomVehicleDensityMultiplierThisFrame(1.0)
        SetParkedVehicleDensityMultiplierThisFrame(1.0)
        SetPedDensityMultiplierThisFrame(1.0)
    end)

    -- 3. Rampas dinâmicas
    Citizen.CreateThread(function()
        Citizen.Wait(4000)
        local startTime = GetGameTimer()

        while roundActive do
            local elapsed = (GetGameTimer() - startTime) / 1000

            local interval, batch, minDist, maxDist
            if     elapsed < 60  then interval, batch, minDist, maxDist = 30000, 1, 80, 180
            elseif elapsed < 180 then interval, batch, minDist, maxDist = 18000, 1, 60, 140
            elseif elapsed < 360 then interval, batch, minDist, maxDist = 10000, 2, 40, 100
            elseif elapsed < 540 then interval, batch, minDist, maxDist =  6000, 2, 25,  80
            else                      interval, batch, minDist, maxDist =  4000, 3, 15,  60
            end

            local sizes = {'small', 'medium', 'large'}

            for i = 1, batch do
                if not roundActive then break end
                local pedCoords = GetEntityCoords(PlayerPedId())
                local fwd   = GetEntityForwardVector(PlayerPedId())
                local fwdAng = math.atan(fwd.y, fwd.x)
                local offsetRad = math.rad(math.random(70, 290))
                local spawnAng  = fwdAng + offsetRad
                local dist      = math.random(minDist, maxDist)
                local tx        = pedCoords.x + math.cos(spawnAng) * dist
                local ty        = pedCoords.y + math.sin(spawnAng) * dist

                local roadFound, nodePos = GetClosestVehicleNode(tx, ty, pedCoords.z, 0, 3.0, 0)
                if roadFound and nodePos then
                    local sz = sizes[((rampCount) % 3) + 1]
                    spawnRampOnRoad(nodePos.x, nodePos.y, nodePos.z, sz)
                end
                Citizen.Wait(700)
            end

            Citizen.Wait(interval)
        end
    end)

    -- 4. ONDAS PROGRESSIVAS — só se waveModeActive
    if waveModeActive then
        Citizen.CreateThread(function()
            Citizen.Wait(8000)
            local waveStart = GetGameTimer()

            local function makeCar(models, dist)
                local nd = roadNear(dist or math.random(100, 200))
                if not nd then return end
                local h = GetHashKey(models[math.random(#models)])
                RequestModel(h); local t=0
                while not HasModelLoaded(h) and t<25 do Citizen.Wait(100); t=t+1 end
                if not HasModelLoaded(h) then return end
                local v = CreateVehicle(h, nd.x, nd.y, nd.z+0.5, math.random(0,359)*1.0, true, false)
                SetVehicleEngineOn(v, true, false, true); SetModelAsNoLongerNeeded(h)
                local dH = GetHashKey('a_m_y_downtown_01'); RequestModel(dH); t=0
                while not HasModelLoaded(dH) and t<15 do Citizen.Wait(100); t=t+1 end
                if HasModelLoaded(dH) then
                    local d = CreatePedInsideVehicle(v, 26, dH, -1, true, false)
                    SetDriverAggressiveness(d,1.0); SetDriverAbility(d,1.0)
                    TaskVehicleChase(d, PlayerPedId()); SetModelAsNoLongerNeeded(dH)
                    chaosEntities[#chaosEntities+1] = d
                end
                chaosEntities[#chaosEntities+1] = v
            end

            local function makeTank(models, armed)
                local nd = roadNear(math.random(150, 250))
                if not nd then return end
                local h = GetHashKey(models[math.random(#models)])
                RequestModel(h); local t=0
                while not HasModelLoaded(h) and t<40 do Citizen.Wait(100); t=t+1 end
                if not HasModelLoaded(h) then return end
                local v = CreateVehicle(h, nd.x, nd.y, nd.z+1.0, math.random(0,359)*1.0, true, false)
                SetVehicleEngineOn(v, true, false, true); SetModelAsNoLongerNeeded(h)
                local dH = GetHashKey('s_m_y_swat_01'); RequestModel(dH); t=0
                while not HasModelLoaded(dH) and t<20 do Citizen.Wait(100); t=t+1 end
                if HasModelLoaded(dH) then
                    local d = CreatePedInsideVehicle(v, 26, dH, -1, true, false)
                    if not armed then RemoveAllPedWeapons(d, true) end
                    SetDriverAggressiveness(d,1.0); SetDriverAbility(d,1.0)
                    TaskVehicleChase(d, PlayerPedId()); SetModelAsNoLongerNeeded(dH)
                    chaosEntities[#chaosEntities+1] = d
                end
                chaosEntities[#chaosEntities+1] = v
            end

            local function makeHeli()
                local c = GetEntityCoords(PlayerPedId())
                local a = math.random() * math.pi * 2
                local helis = {'buzzard', 'valkyrie', 'savage'}
                local h = GetHashKey(helis[math.random(#helis)])
                RequestModel(h); local t=0
                while not HasModelLoaded(h) and t<40 do Citizen.Wait(100); t=t+1 end
                if not HasModelLoaded(h) then return end
                local heli = CreateVehicle(h, c.x+math.cos(a)*200, c.y+math.sin(a)*200, c.z+80, 0.0, true, false)
                SetVehicleEngineOn(heli, true, false, true); SetHeliBladesFullSpeed(heli); SetModelAsNoLongerNeeded(h)
                local dH = GetHashKey('s_m_y_pilot_01'); RequestModel(dH); t=0
                while not HasModelLoaded(dH) and t<20 do Citizen.Wait(100); t=t+1 end
                if HasModelLoaded(dH) then
                    local pilot = CreatePedInsideVehicle(heli, 26, dH, -1, true, false)
                    RemoveAllPedWeapons(pilot, true); SetModelAsNoLongerNeeded(dH)
                    chaosEntities[#chaosEntities+1] = pilot
                    Citizen.CreateThread(function()
                        TaskHeliChase(pilot, PlayerPedId(), 0.0, 0.0, 40.0)
                        Citizen.Wait(15000)
                        if not roundActive or not DoesEntityExist(heli) then return end
                        TaskHeliChase(pilot, PlayerPedId(), 0.0, 0.0, -5.0)
                        notify('🚁 HELICÓPTERO EM KAMIKAZE!', 'error', 4000)
                    end)
                end
                chaosEntities[#chaosEntities+1] = heli
            end

            local function makeTruck()
                local nd = roadNear(math.random(80, 180))
                if not nd then return end
                local trucks = {'phantom', 'packer', 'hauler', 'mixer', 'flatbed'}
                local h = GetHashKey(trucks[math.random(#trucks)])
                RequestModel(h); local t=0
                while not HasModelLoaded(h) and t<30 do Citizen.Wait(100); t=t+1 end
                if not HasModelLoaded(h) then return end
                local v = CreateVehicle(h, nd.x, nd.y, nd.z+0.5, math.random(0,359)*1.0, true, false)
                SetVehicleEngineOn(v, true, false, true); SetModelAsNoLongerNeeded(h)
                local dH = GetHashKey('s_m_m_trucker_01'); RequestModel(dH); t=0
                while not HasModelLoaded(dH) and t<15 do Citizen.Wait(100); t=t+1 end
                if HasModelLoaded(dH) then
                    local d = CreatePedInsideVehicle(v, 26, dH, -1, true, false)
                    SetDriverAggressiveness(d,1.0); SetDriverAbility(d,1.0)
                    TaskVehicleChase(d, PlayerPedId()); SetModelAsNoLongerNeeded(dH)
                    chaosEntities[#chaosEntities+1] = d
                end
                chaosEntities[#chaosEntities+1] = v
            end

            local cityRageOn = false
            local function cityRage()
                if cityRageOn then return end
                cityRageOn = true
                notify('🌋 TODA A CIDADE ESTÁ ATRÁS DE TI!', 'error', 8000)
                Citizen.CreateThread(function()
                    while roundActive do
                        local me = PlayerPedId()
                        for _, p in ipairs(GetGamePool('CPed')) do
                            if p ~= me and not IsPedAPlayer(p) and not IsPedDeadOrDying(p, true) then
                                local d = #(GetEntityCoords(me) - GetEntityCoords(p))
                                if d < 80.0 then
                                    SetPedFleeAttributes(p, 0, false)
                                    SetPedCombatAttributes(p, 46, true)
                                    SetPedCombatAttributes(p, 5, true)
                                    GiveWeaponToPed(p, GetHashKey('WEAPON_BAT'), 1, false, true)
                                    TaskCombatPed(p, me, 0, 16)
                                end
                            end
                        end
                        Citizen.Wait(3000)
                    end
                end)
            end

            local light  = {'blista', 'issi2', 'prairie', 'dilettante'}
            local heavy  = {'granger', 'baller2', 'guardian', 'dubsta2', 'dominator'}
            local noGun  = {'insurgent2', 'insurgent3', 'barrage', 'insurgent'}
            local armed  = {'rhino', 'khanjali', 'apc'}

            local lastWave = -1

            -- Definições de onda: { minuto, label, cor }
            local waveDefs = {
                [2]  = { label = 'Carros Pesados',        color = 'yellow' },
                [4]  = { label = 'Tanques',               color = 'orange' },
                [6]  = { label = 'Tanques Armados',       color = 'red'    },
                [8]  = { label = 'Helicópteros',          color = 'red'    },
                [10] = { label = 'Camiões',               color = 'red'    },
                [12] = { label = '🌋 TODA A CIDADE!',    color = 'red'    },
            }

            while roundActive do
                local sec = (GetGameTimer() - waveStart) / 1000
                local min = math.floor(sec / 60)

                if min > lastWave then
                    lastWave    = min
                    currentWave = min

                    -- Notificar HUD da nova onda
                    local wDef = waveDefs[min]
                    if wDef then
                        notify('⚡ ONDA ' .. min .. ': ' .. wDef.label .. '!', min >= 6 and 'error' or 'warning', 5000)
                        SendNUIMessage({ action = 'waveUpdate', wave = min, label = wDef.label, color = wDef.color })
                    elseif min == 0 then
                        notify('⚡ ONDA 1: Carros Leves!', 'primary', 5000)
                        SendNUIMessage({ action = 'waveUpdate', wave = 1, label = 'Carros Leves', color = 'blue' })
                    end
                end

                if myRole == 'robber' then
                    if     min < 2  then makeCar(light);                           Citizen.Wait(45000)
                    elseif min < 4  then makeCar(heavy);                           Citizen.Wait(30000)
                    elseif min < 6  then makeTank(noGun, false); Citizen.Wait(3000); makeCar(heavy); Citizen.Wait(35000)
                    elseif min < 8  then makeTank(armed, true);  Citizen.Wait(3000); makeCar(heavy); Citizen.Wait(30000)
                    elseif min < 10 then makeHeli(); Citizen.Wait(3000); makeTank(armed, true);      Citizen.Wait(22000)
                    elseif min < 12 then makeTruck(); Citizen.Wait(2000); makeHeli(); Citizen.Wait(2000); makeTank(armed, true); Citizen.Wait(14000)
                    else                 cityRage(); makeTruck(); Citizen.Wait(1500); makeHeli(); Citizen.Wait(1500); makeTank(armed, true); Citizen.Wait(1500); makeCar(heavy); Citizen.Wait(8000)
                    end
                else
                    makeCar(light); Citizen.Wait(60000)
                end
            end
        end)
    else
        -- Modo sem ondas: só tráfego extremo (já activo) + pequena notificação
        notify('🚗 Modo Ondas DESACTIVADO — apenas tráfego caótico!', 'primary', 5000)
    end

    -- 5. Carros de PROTEÇÃO do ladrão — invencíveis, perseguem polícia
    if myRole == 'robber' then
        Citizen.CreateThread(function()
            Citizen.Wait(3000)
            local pModels    = {'baller2', 'granger', 'guardian', 'dubsta2', 'mesa'}
            local numProtect = math.random(5, 10)
            for i = 1, numProtect do
                if not roundActive then break end
                local nd = roadNear(math.random(30, 80))
                if not nd then goto skipP end
                do
                    local h = GetHashKey(pModels[math.random(#pModels)])
                    RequestModel(h); local t=0
                    while not HasModelLoaded(h) and t<25 do Citizen.Wait(100); t=t+1 end
                    if not HasModelLoaded(h) then goto skipP end
                    local pc = CreateVehicle(h, nd.x, nd.y, nd.z+0.5, math.random(0,359)*1.0, true, false)
                    SetVehicleEngineOn(pc, true, false, true); SetModelAsNoLongerNeeded(h)
                    SetEntityInvincible(pc, true); SetVehicleCanBeVisiblyDamaged(pc, false); SetVehicleWheelsCanBreak(pc, false)
                    local dH = GetHashKey('g_m_y_lost_02'); RequestModel(dH); t=0
                    while not HasModelLoaded(dH) and t<20 do Citizen.Wait(100); t=t+1 end
                    if HasModelLoaded(dH) then
                        local dr = CreatePedInsideVehicle(pc, 26, dH, -1, true, false)
                        RemoveAllPedWeapons(dr, true); SetEntityInvincible(dr, true)
                        SetDriverAggressiveness(dr,1.0); SetDriverAbility(dr,1.0); SetModelAsNoLongerNeeded(dH)
                        chaosEntities[#chaosEntities+1] = dr
                    end
                    chaosEntities[#chaosEntities+1] = pc
                    Citizen.CreateThread(function()
                        while roundActive and DoesEntityExist(pc) do
                            local closest, cD = 0, 999999
                            for _, p in ipairs(GetGamePool('CPed')) do
                                if p ~= PlayerPedId() and IsPedAPlayer(p) then
                                    local d2 = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(p))
                                    if d2 < cD then closest = p; cD = d2 end
                                end
                            end
                            local dp = GetPedInVehicleSeat(pc, -1)
                            if closest ~= 0 and dp ~= 0 then TaskVehicleChase(dp, closest) end
                            Citizen.Wait(5000)
                        end
                    end)
                end
                ::skipP::
                Citizen.Wait(1500)
            end
            notify('🛡️ ' .. numProtect .. ' carros de PROTEÇÃO!', 'success', 5000)
        end)
    end
end

-- ── Blips de localização ──────────────────────────────────────

local function spawnTempBlips(positions, duration, aliveCount)
    for _, b in ipairs(tempBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    tempBlips    = {}
    lastPositions = positions

    for _, pos in ipairs(positions) do
        local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
        if pos.role == 'cop' then
            SetBlipSprite(blip, 60); SetBlipColour(blip, 3)
        else
            SetBlipSprite(blip, 84); SetBlipColour(blip, 1)
        end
        SetBlipScale(blip, 1.0)
        SetBlipAsShortRange(blip, false)
        SetBlipFlashes(blip, true)
        tempBlips[#tempBlips + 1] = blip
    end

    SendNUIMessage({ action = 'updateRobbers', count = aliveCount })

    Citizen.CreateThread(function()
        Citizen.Wait(duration * 1000)
        for _, b in ipairs(tempBlips) do
            if DoesBlipExist(b) then RemoveBlip(b) end
        end
        tempBlips = {}
    end)
end

-- ── NUI ──────────────────────────────────────────────────────

local function openNUI(role, lockSeconds, roundDuration)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'open', role = role, lockSeconds = lockSeconds, roundDuration = roundDuration })
end

local function closeNUI()
    SendNUIMessage({ action = 'close' })
end

-- ── Thread: proximidade ───────────────────────────────────────

local function startProximityCheck()
    Citizen.CreateThread(function()
        while roundActive do
            Citizen.Wait(2000)
            if not roundActive or #lastPositions == 0 then goto continue end
            local myCoords = GetEntityCoords(PlayerPedId())
            local closest  = 99999
            for _, pos in ipairs(lastPositions) do
                local isEnemy = (myRole == 'cop' and pos.role == 'robber')
                             or (myRole == 'robber' and pos.role == 'cop')
                if isEnemy then
                    local d = #(vector3(myCoords.x, myCoords.y, myCoords.z) - vector3(pos.x, pos.y, pos.z))
                    if d < closest then closest = d end
                end
            end
            if     closest < 30             then SendNUIMessage({ action = 'danger', level = 2 }); notify('🚨 INIMIGO MUITO PRÓXIMO! (~' .. math.floor(closest) .. 'm)', 'error', 2500)
            elseif closest < Config.alertRange then SendNUIMessage({ action = 'danger', level = 1 })
            else                                  SendNUIMessage({ action = 'danger', level = 0 }) end
            ::continue::
        end
        SendNUIMessage({ action = 'danger', level = 0 })
    end)
end

-- ── Thread: fora da zona ──────────────────────────────────────

local function startOOBCheck()
    Citizen.CreateThread(function()
        while roundActive do
            Citizen.Wait(3000)
            if not roundActive or not zoneData then goto next end
            local coords = GetEntityCoords(PlayerPedId())
            local dist   = #(vector3(coords.x, coords.y, coords.z) - vector3(zoneData.x, zoneData.y, zoneData.z))
            if dist > zoneData.radius then
                if not outOfBoundsWarn then
                    outOfBoundsWarn = true
                    notify(('⚠️ FORA DA ZONA! Volta em %ds!'):format(Config.outOfBoundsWarnSecs), 'error', 6000)
                    Citizen.CreateThread(function()
                        local t = Config.outOfBoundsWarnSecs
                        while t > 0 and roundActive and outOfBoundsWarn do
                            Citizen.Wait(1000); t = t - 1
                            local c = GetEntityCoords(PlayerPedId())
                            local d = #(vector3(c.x, c.y, c.z) - vector3(zoneData.x, zoneData.y, zoneData.z))
                            if d <= zoneData.radius then outOfBoundsWarn = false; notify('✅ De volta à zona!', 'success', 3000); return end
                        end
                        if roundActive and outOfBoundsWarn then TriggerServerEvent('policia:outOfBounds') end
                    end)
                end
            else
                outOfBoundsWarn = false
            end
            ::next::
        end
    end)
end

-- ── Tecla G: Algemar ──────────────────────────────────────────

RegisterKeyMapping('policiaarrestar', 'Algemar Suspeito', 'keyboard', 'g')
RegisterCommand('policiaarrestar', function()
    if myRole ~= 'cop' or not roundActive or isFrozen then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then
        notify('🚗 Sai do carro para algemar!', 'error', 3000); return
    end
    TriggerServerEvent('policia:tryArrest')
end, false)

-- ── Tecla H: Helicopter Support (cops) ───────────────────────

RegisterKeyMapping('policiaheli', 'Pedir Helicóptero de Apoio', 'keyboard', 'h')
RegisterCommand('policiaheli', function()
    if myRole ~= 'cop' or not roundActive or isFrozen then return end
    TriggerServerEvent('policia:requestHeli')
end, false)

-- ── NUI Callbacks (Admin UI + Heli) ───────────────────────────

RegisterNUICallback('policia:submitConfig', function(data, cb)
    SetNuiFocus(false, false)
    TriggerServerEvent('policia:startFromUI',
        tonumber(data.numCops)  or 1,
        tonumber(data.lockSecs) or 30,
        data.waveMode ~= false)
    cb({})
end)

RegisterNUICallback('policia:closeAdminUI', function(data, cb)
    SetNuiFocus(false, false)
    cb({})
end)

-- ── Registo de eventos ────────────────────────────────────────

RegisterNetEvent('policia:setupZone')
RegisterNetEvent('policia:assignRole')
RegisterNetEvent('policia:releasePolice')
RegisterNetEvent('policia:sendClue')
RegisterNetEvent('policia:endRound')
RegisterNetEvent('policia:youWereArrested')
RegisterNetEvent('policia:openAdminUI')
RegisterNetEvent('policia:spawnHeli')
RegisterNetEvent('policia:killFeed')

-- ── Reset completo ────────────────────────────────────────────

local function fullReset()
    roundActive     = false
    myRole          = nil
    isFrozen        = false
    outOfBoundsWarn = false
    lastPositions   = {}
    waveModeActive  = true
    currentWave     = 0

    freezePlayer(false)
    closeNUI()
    removeZone()
    cleanupChaos()

    for _, b in ipairs(tempBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    tempBlips = {}

    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        DeleteEntity(spawnedVehicle); spawnedVehicle = nil
    end
    removeAllWeapons()
end

-- ── Handlers ─────────────────────────────────────────────────

AddEventHandler('policia:setupZone', function(x, y, z, radius, zoneName)
    showZone(x, y, z, radius)
    if zoneName then
        notify('📍 Zona: ' .. zoneName, 'primary', 6000)
    end
end)

AddEventHandler('policia:assignRole', function(role, carModel, lockSeconds, spawnCoords, weapon, ammo, waveMode, roadblockCount)
    myRole          = role
    roundActive     = true
    isFrozen        = false
    outOfBoundsWarn = false
    lastPositions   = {}
    chaosEntities   = {}
    waveModeActive  = (waveMode ~= false)
    currentWave     = 0

    removeAllWeapons()

    local ped = PlayerPedId()

    SetEntityCoords(ped, spawnCoords.x, spawnCoords.y, spawnCoords.z + 200.0, false, false, false, true)
    Citizen.Wait(2500)

    local roadFound, nodePos = GetClosestVehicleNode(spawnCoords.x, spawnCoords.y, spawnCoords.z, 0, 3.0, 0)

    local spawnX, spawnY, spawnZ

    if roadFound and nodePos then
        spawnX = nodePos.x
        spawnY = nodePos.y
        spawnZ = nodePos.z + 1.0
    else
        spawnX = spawnCoords.x
        spawnY = spawnCoords.y
        local ok, gz = GetGroundZFor_3dCoord(spawnCoords.x, spawnCoords.y, spawnCoords.z + 100.0, false)
        spawnZ = ok and (gz + 1.0) or spawnCoords.z
    end

    SetEntityCoords(ped, spawnX, spawnY, spawnZ, false, false, false, true)
    SetEntityHeading(ped, spawnCoords.w)
    Citizen.Wait(500)

    local roadPos = vector4(spawnX, spawnY, spawnZ, spawnCoords.w)
    local veh = spawnVehicle(carModel, roadPos)
    Citizen.Wait(500)
    warpIntoCar(veh)
    Citizen.Wait(400)
    giveWeaponNow(weapon, ammo)

    if role == 'cop' then
        notify('🚓 POLÍCIA! Preso ' .. lockSeconds .. 's. G=Algemar | H=Heli Apoio', 'error')
        freezePlayer(true)
        openNUI('cop', lockSeconds, Config.roundDuration)
    else
        notify('🔪 LADRÃO! Polícias saem em ' .. lockSeconds .. 's. FOGE!', 'warning')
        openNUI('robber', lockSeconds, Config.roundDuration)
    end

    startProximityCheck()
    startOOBCheck()

    -- Roadblocks para todos
    if roadblockCount and roadblockCount > 0 then
        spawnRoadblocks(roadblockCount)
    end

    -- Iniciar caos após 5s
    Citizen.CreateThread(function()
        Citizen.Wait(5000)
        if roundActive then
            startChaosZone()
            if waveModeActive then
                notify('🔥 CAOS + ONDAS ACTIVADAS! Boa sorte...', 'warning', 6000)
            else
                notify('🔥 CAOS ACTIVADO! (Sem ondas)', 'warning', 6000)
            end
        end
    end)

    -- Thread de reparação periódica
    Citizen.CreateThread(function()
        while roundActive do
            Citizen.Wait(30000)
            if not roundActive then break end
            local veh2 = spawnedVehicle
            if veh2 and DoesEntityExist(veh2) then
                for wheel = 0, 7 do
                    if IsVehicleTyreBurst(veh2, wheel, false) then
                        SetVehicleTyreBurst(veh2, wheel, false, 1000.0)
                        SetVehicleTyreFixed(veh2, wheel)
                    end
                end
                if GetVehicleEngineHealth(veh2) < 800.0 then SetVehicleEngineHealth(veh2, 800.0) end
                if GetVehicleBodyHealth(veh2) < 800.0    then SetVehicleBodyHealth(veh2, 800.0)   end
                SetVehicleWheelsCanBreak(veh2, false)
                notify('🔧 Veículo reparado!', 'success', 2000)
            end
        end
    end)
end)

AddEventHandler('policia:releasePolice', function()
    if myRole ~= 'cop' then return end
    freezePlayer(false)
    notify('🚨 LIBERTO! À CAÇA! (G=Algemar | H=Heli Apoio)', 'success')
    SendNUIMessage({ action = 'released' })
end)

AddEventHandler('policia:sendClue', function(positions, blipDuration, aliveCount)
    spawnTempBlips(positions, blipDuration, aliveCount)
end)

AddEventHandler('policia:youWereArrested', function()
    notify('🔒 Foste APANHADO!', 'error')
    fullReset()
end)

AddEventHandler('policia:endRound', function(reason)
    notify('🏁 RONDA TERMINADA: ' .. (reason or ''), 'primary')
    fullReset()
end)

-- ── Admin UI: abrir painel de configuração ────────────────────

AddEventHandler('policia:openAdminUI', function()
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openAdminUI' })
end)

-- ── Kill Feed ─────────────────────────────────────────────────

AddEventHandler('policia:killFeed', function(feedType, actor, victim)
    SendNUIMessage({ action = 'killFeed', feedType = feedType, actor = actor, victim = victim })
end)

-- ── Helicóptero de Apoio ──────────────────────────────────────

AddEventHandler('policia:spawnHeli', function(targetCoords, duration, heliAlt)
    Citizen.CreateThread(function()
        local me = PlayerPedId()
        local myC = GetEntityCoords(me)

        -- Posição de spawn: acima do alvo (ou acima do cop se não há alvo)
        local spawnX = targetCoords and targetCoords.x or myC.x
        local spawnY = targetCoords and targetCoords.y or myC.y
        local spawnZ = (targetCoords and targetCoords.z or myC.z) + (heliAlt or 80)

        local hHash = GetHashKey('polmav')
        RequestModel(hHash)
        local t = 0
        while not HasModelLoaded(hHash) and t < 30 do Citizen.Wait(100); t = t + 1 end
        if not HasModelLoaded(hHash) then return end

        local heli = CreateVehicle(hHash, spawnX, spawnY, spawnZ, 0.0, true, false)
        SetVehicleEngineOn(heli, true, false, true)
        SetHeliBladesFullSpeed(heli)
        SetModelAsNoLongerNeeded(hHash)

        local pilotHash = GetHashKey('s_m_y_pilot_01')
        RequestModel(pilotHash)
        t = 0
        while not HasModelLoaded(pilotHash) and t < 20 do Citizen.Wait(100); t = t + 1 end
        local pilot = nil
        if HasModelLoaded(pilotHash) then
            pilot = CreatePedInsideVehicle(heli, 26, pilotHash, -1, true, false)
            RemoveAllPedWeapons(pilot, true)
            SetModelAsNoLongerNeeded(pilotHash)
        end

        -- Holofote
        local searchlight = true
        Citizen.CreateThread(function()
            local elapsed = 0
            while roundActive and elapsed < duration and DoesEntityExist(heli) do
                if searchlight and targetCoords then
                    -- Seguir posição do alvo (posição estática fornecida pelo server)
                    SetVehicleSearchlight(heli, true, true)
                end
                Citizen.Wait(500)
                elapsed = elapsed + 0.5
            end
            SetVehicleSearchlight(heli, false, false)
        end)

        -- Fazer o heli circular sobre o alvo
        if pilot and targetCoords then
            TaskHeliChase(pilot,
                -- Não temos ped alvo aqui, circular sobre coordenada
                -- Usar TASK_HELI_MISSION com ponto fixo
                pilot, -- dummy, vamos usar TaskHeliMission
                0.0, 0.0, 40.0)
        end

        -- Holofote manual + círculo sobre alvo
        local timer = 0
        while roundActive and timer < duration and DoesEntityExist(heli) do
            if targetCoords then
                SetEntityCoords(heli,
                    targetCoords.x + math.cos(timer * 0.5) * 30,
                    targetCoords.y + math.sin(timer * 0.5) * 30,
                    targetCoords.z + (heliAlt or 80),
                    false, false, false, false)
            end
            SetVehicleSearchlight(heli, true, true)
            Citizen.Wait(1000)
            timer = timer + 1
        end

        -- Desaparecer
        SetVehicleSearchlight(heli, false, false)
        if pilot and DoesEntityExist(pilot) then
            SetEntityAsMissionEntity(pilot, true, true)
            DeleteEntity(pilot)
        end
        if DoesEntityExist(heli) then
            SetEntityAsMissionEntity(heli, true, true)
            DeleteEntity(heli)
        end
        notify('🚁 Helicóptero de apoio retirado.', 'primary', 3000)
    end)
end)

AddEventHandler('baseevents:onPlayerDied', function()
    if myRole == 'robber' and roundActive then
        TriggerServerEvent('policia:robberDied')
    end
end)
