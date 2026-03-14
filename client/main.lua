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
local activeRobbers    = {}    -- Guarda lista de ladroes enviada pelo server
local isHeliCop        = false -- flag: este cop está no helicóptero
local xrayBlips        = {}    -- blips persistentes do X-ray

-- Boost (Nitro)
local boostCooldown    = 0
local boostActive      = false

-- Novos poderes
local radarPulseCooldown = 0
local radarPulseBlips    = {}
local oilSlickCooldown   = 0
local decoyBlipCooldown  = 0
local repairKitCooldown  = 0
local activeCops         = {}   -- Guarda lista de cops enviada pelo server

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

local function upgradeVehicle(veh, isCop)
    SetVehicleModKit(veh, 0)
    for modType = 0, 49 do
        local maxMod = GetNumVehicleMods(veh, modType) - 1
        if maxMod >= 0 then SetVehicleMod(veh, modType, maxMod, false) end
    end
    ToggleVehicleMod(veh, 18, true)
    ToggleVehicleMod(veh, 22, true)
    
    -- TXAdmin Boost (Aceleração e Força extremas)
    SetVehicleEnginePowerMultiplier(veh, 20.0)
    SetVehicleEngineTorqueMultiplier(veh, 20.0)

    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)

    if isCop then
        SetVehicleWheelsCanBreak(veh, false)
        SetVehicleTyresCanBurst(veh, false)  -- Cops: Pneus invencíveis
        SetEntityInvincible(veh, true)
        SetVehicleCanBeVisiblyDamaged(veh, false)
    else
        SetVehicleWheelsCanBreak(veh, true)
        SetVehicleTyresCanBurst(veh, true)   -- Ladrão: Pneus normais
    end
    
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
    upgradeVehicle(veh, myRole == 'cop')

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
            -- Parar todos os tasks do NPC antes de eliminar
            if IsEntityAPed(e) then
                ClearPedTasksImmediately(e)
                SetPedFleeAttributes(e, 0, true)
                SetBlockingOfNonTemporaryEvents(e, true)
            elseif IsEntityAVehicle(e) then
                local driver = GetPedInVehicleSeat(e, -1)
                if driver ~= 0 and DoesEntityExist(driver) then
                    ClearPedTasksImmediately(driver)
                    SetBlockingOfNonTemporaryEvents(driver, true)
                end
            end
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
        -- NPC mais inteligente
        SetPedCombatAttributes(driver, 46, true)  -- fight to death
        SetPedCombatAttributes(driver, 5, true)   -- can fight in vehicle
        SetPedCombatMovement(driver, 3)            -- offensive
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
        Citizen.Wait(6000)
        if not roundActive or not zoneData then return end

        -- Props de barricada real de polícia
        local barrierModels = {
            'prop_mp_barrier_01a',
            'prop_mp_barrier_02a',
            'prop_barrier_work_07a',
            'prop_barrier_work_03a',
        }
        local coneModels    = { 'prop_mp_cone_02', 'prop_mp_cone_01' }
        local roadblockCars = {'police2', 'police3', 'sheriff', 'policet'}
        local swatHash      = GetHashKey('s_m_y_swat_01')

        RequestModel(swatHash)
        local t0 = 0
        while not HasModelLoaded(swatHash) and t0 < 20 do Citizen.Wait(100); t0 = t0 + 1 end

        notify('🚧 Estradas cortadas com barricadas de polícia!', 'warning', 5000)

        for i = 1, count do
            if not roundActive then break end

            -- Ponto dentro da zona (distribuído por ângulos regulares + ruído)
            local angle  = (i / count) * math.pi * 2 + math.random() * 0.6
            local rFrac  = 0.35 + math.random() * 0.55
            local px     = zoneData.x + math.cos(angle) * zoneData.radius * rFrac
            local py     = zoneData.y + math.sin(angle) * zoneData.radius * rFrac

            local roadOk, nodePos = GetClosestVehicleNode(px, py, zoneData.z, 0, 3.0, 0)
            if not roadOk or not nodePos then goto nextRB end

            do
                local heading = math.random(0, 359) * 1.0

                -- Carro de polícia bloqueando
                local carH = GetHashKey(randomFrom(roadblockCars))
                RequestModel(carH)
                local t = 0
                while not HasModelLoaded(carH) and t < 25 do Citizen.Wait(100); t = t + 1 end
                if HasModelLoaded(carH) then
                    local rbVeh = CreateVehicle(carH, nodePos.x, nodePos.y, nodePos.z + 0.5, heading, true, false)
                    SetVehicleEngineOn(rbVeh, false, true, true)
                    FreezeEntityPosition(rbVeh, true)
                    SetVehicleCanBeVisiblyDamaged(rbVeh, false)
                    SetVehicleWheelsCanBreak(rbVeh, false)
                    SetModelAsNoLongerNeeded(carH)
                    chaosEntities[#chaosEntities + 1] = rbVeh
                end

                -- 3-5 barreiras de polícia em linha
                local barrierH = GetHashKey(randomFrom(barrierModels))
                RequestModel(barrierH)
                t = 0
                while not HasModelLoaded(barrierH) and t < 20 do Citizen.Wait(100); t = t + 1 end
                if HasModelLoaded(barrierH) then
                    local perpRad = math.rad(heading + 90)
                    local numBarriers = math.random(3, 5)
                    for b = 1, numBarriers do
                        local offsetMult = (b - math.ceil(numBarriers / 2)) * 1.8
                        local bx = nodePos.x + math.cos(perpRad) * offsetMult
                        local by = nodePos.y + math.sin(perpRad) * offsetMult
                        local barrier = CreateObject(barrierH, bx, by, nodePos.z, true, true, false)
                        if DoesEntityExist(barrier) then
                            SetEntityHeading(barrier, heading)
                            PlaceObjectOnGroundProperly(barrier)
                            FreezeEntityPosition(barrier, true)
                            SetEntityCollision(barrier, true, true)
                            chaosEntities[#chaosEntities + 1] = barrier
                        end
                    end
                    SetModelAsNoLongerNeeded(barrierH)
                end

                -- Cones extras
                local coneH = GetHashKey(randomFrom(coneModels))
                RequestModel(coneH)
                t = 0
                while not HasModelLoaded(coneH) and t < 15 do Citizen.Wait(100); t = t + 1 end
                if HasModelLoaded(coneH) then
                    local perpRad = math.rad(heading + 90)
                    for c = 1, 2 do
                        local sign = (c == 1) and 3.5 or -3.5
                        local cone = CreateObject(coneH,
                            nodePos.x + math.cos(perpRad) * sign,
                            nodePos.y + math.sin(perpRad) * sign,
                            nodePos.z, true, true, false)
                        if DoesEntityExist(cone) then
                            PlaceObjectOnGroundProperly(cone)
                            FreezeEntityPosition(cone, true)
                            chaosEntities[#chaosEntities + 1] = cone
                        end
                    end
                    SetModelAsNoLongerNeeded(coneH)
                end

                -- 2 SWAT a guardar
                for s = 1, 2 do
                    if HasModelLoaded(swatHash) then
                        local perpRad = math.rad(heading + 90)
                        local sign    = (s == 1) and 1.0 or -1.0
                        local ox      = nodePos.x + math.cos(perpRad) * sign * 3.0
                        local oy      = nodePos.y + math.sin(perpRad) * sign * 3.0
                        local swat    = CreatePed(26, swatHash, ox, oy, nodePos.z, 0.0, true, false)
                        SetEntityInvincible(swat, false)
                        SetPedRelationshipGroupHash(swat, GetHashKey('COP'))
                        SetPedKeepTask(swat, true)
                        if myRole == 'robber' then
                            GiveWeaponToPed(swat, GetHashKey('weapon_carbinerifle'), 120, false, true)
                            TaskGuardCurrentPosition(swat, 15.0, 15.0, true)
                        else
                            RemoveAllPedWeapons(swat, true)
                            -- Substitui o 'TaskStandGuard' crashável
                            TaskWanderStandard(swat, 10.0, 10)
                        end
                        chaosEntities[#chaosEntities + 1] = swat
                    end
                end
            end

            ::nextRB::
            Citizen.Wait(300)  -- spawn rápido para cobrir mais estradas
        end
        SetModelAsNoLongerNeeded(swatHash)
    end)
end

-- ── TURRET DE BAZUCA (cop only) — tecla U ─────────────────────────

local turretCooldown = 0
local robberTurretCooldown = 0

local function isPoliceCar(veh)
    local model = GetEntityModel(veh)
    for _, carName in ipairs(Config.policeCars) do
        if GetHashKey(carName) == model then return true end
    end
    return false
end

local function placeTurret(ownerRole)
    if not roundActive or isFrozen then return end
    
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        notify('❌ Tens de sair do carro para instalar a Turret!', 'error', 3000)
        return
    end

    local now = GetGameTimer()
    if ownerRole == 'cop' then
        if now < turretCooldown then
            local remaining = math.ceil((turretCooldown - now) / 1000)
            notify('⏳ Aguarda ' .. remaining .. 's para colocar outra!', 'error', 3000)
            return
        end
        turretCooldown = now + (Config.turretCooldown * 1000) -- 5s cooldown
    elseif ownerRole == 'robber' then
        if now < robberTurretCooldown then
            local remaining = math.ceil((robberTurretCooldown - now) / 1000)
            notify('⏳ Aguarda ' .. remaining .. 's para a tua próxima Turret!', 'error', 3000)
            return
        end
        robberTurretCooldown = now + (Config.turretCooldown * 1000) -- 5s cooldown
    end

    local pos = GetEntityCoords(ped)
    local fwd = GetEntityForwardVector(ped)
    local spX = pos.x + fwd.x * 2.0
    local spY = pos.y + fwd.y * 2.0

    local propHash = GetHashKey('prop_minigun_01')
    RequestModel(propHash)
    local t = 0
    while not HasModelLoaded(propHash) and t < 20 do Citizen.Wait(100); t = t + 1 end

    if HasModelLoaded(propHash) then
        -- Colocar Turret 8 metros acima do chão no ar
        local airZ = pos.z + 8.0
        local turretProp = CreateObject(propHash, spX, spY, airZ, true, true, false)
        if DoesEntityExist(turretProp) then
            -- Não colocamos OnGroundProperly para ela flutuar intencionalmente
            SetEntityHeading(turretProp, GetEntityHeading(ped))
            FreezeEntityPosition(turretProp, true)
            SetEntityCollision(turretProp, true, true)
            chaosEntities[#chaosEntities + 1] = turretProp

            notify('💥 Turret Aérea de Bazuca Armada!', 'success', 3000)

            Citizen.CreateThread(function()
                -- Criar um Ped "Oculto" dentro da Turret para servir de Atirador Nível Máximo (Aimbot)
                local gunnerHash = GetHashKey('s_m_y_swat_01')
                RequestModel(gunnerHash)
                local t2 = 0
                while not HasModelLoaded(gunnerHash) and t2 < 100 do Citizen.Wait(100); t2 = t2 + 1 end
                if not HasModelLoaded(gunnerHash) then return end

                local gunner = CreatePed(26, gunnerHash, spX, spY, airZ, GetEntityHeading(ped), true, false)
                SetEntityAsMissionEntity(gunner, true, true)
                SetEntityVisible(gunner, false, false) -- 100% Oculto
                SetEntityCollision(gunner, false, false) -- Sem bater em carros
                SetEntityInvincible(gunner, true)
                FreezeEntityPosition(gunner, true)

                -- Dar Lança Rockets ao Fantasma e Precisão 100%
                SetPedCombatAttributes(gunner, 46, true)
                SetPedCombatAttributes(gunner, 5, true)
                SetPedAccuracy(gunner, 100)
                SetPedShootRate(gunner, 1000)
                local rpgHash = GetHashKey('weapon_rpg')
                GiveWeaponToPed(gunner, rpgHash, 9999, false, true)
                SetCurrentPedWeapon(gunner, rpgHash, true)
                
                chaosEntities[#chaosEntities + 1] = gunner

                local turretPos = GetEntityCoords(turretProp)
                local lastShot = 0
                
                -- Loop de radar do Operador Fantasma
                while roundActive and DoesEntityExist(turretProp) and DoesEntityExist(gunner) do
                    Citizen.Wait(500)
                    local currentNow = GetGameTimer()
                    if currentNow - lastShot > 2500 then -- Cooldown de 2.5s por missel
                        local bestPed = nil
                        local bestDist = 400.0
                        
                        -- Encontrar alvo
                        for _, pid in ipairs(GetActivePlayers()) do
                            local enemyPed = GetPlayerPed(pid)
                            if enemyPed ~= PlayerPedId() and DoesEntityExist(enemyPed) and not IsPedDeadOrDying(enemyPed, true) then
                                local svrId = GetPlayerServerId(pid)
                                local isRobber = activeRobbers[tonumber(svrId)] or activeRobbers[tostring(svrId)]
                                
                                local validTarget = false
                                if ownerRole == 'cop' and isRobber then
                                    validTarget = true
                                elseif ownerRole == 'robber' and not isRobber then
                                    validTarget = true
                                end

                                if validTarget then
                                    local enemyCoords = GetEntityCoords(enemyPed)
                                    local d = #(turretPos - enemyCoords)
                                    -- Usa validação extra de linha de visão nativa do GTA
                                    if d < bestDist and HasEntityClearLosToEntity(gunner, enemyPed, 17) then
                                        bestDist = d
                                        bestPed = enemyPed
                                    end
                                end
                            end
                        end

                        if bestPed then
                            -- Limpar Tasks antigas e obrigar disparo agressivo!
                            ClearPedTasks(gunner)
                            TaskShootAtEntity(gunner, bestPed, 2000, GetHashKey('FIRING_PATTERN_FULL_AUTO'))
                            lastShot = currentNow
                        else
                            ClearPedTasks(gunner)
                        end
                    end
                end
                
                -- Se a turret quebrar ou o jogo acabar, apaga o boneco fantasma
                if DoesEntityExist(gunner) then DeleteEntity(gunner) end
            end)
        end
        SetModelAsNoLongerNeeded(propHash)
    end
end

RegisterKeyMapping('policiaturret', 'Colocar Turret de Bazuca (Polícia)', 'keyboard', 'u')
RegisterCommand('policiaturret', function()
    if myRole ~= 'cop' then return end
    placeTurret('cop')
end, false)

RegisterKeyMapping('ladraoturret', 'Colocar Turret de Bazuca (Ladrão)', 'keyboard', 'y')
RegisterCommand('ladraoturret', function()
    if myRole ~= 'robber' then return end
    placeTurret('robber')
end, false)

-- ── HELICÓPTERO DE ATAQUE LIGEIRO removido — agora usa H para Heli de Apoio (ver policiaheli abaixo) ──

-- ── CHOQUE EMP (cop only) — tecla E ──────────────────────────────

local empCooldown = 0

RegisterKeyMapping('policiaemp', 'Choque EMP (Polícia)', 'keyboard', 'e')
RegisterCommand('policiaemp', function()
    if myRole ~= 'cop' or not roundActive or isFrozen then return end
    
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(veh) then
        notify('❌ Precisas de estar dentro do teu carro de polícia!', 'error', 3000)
        return
    end

    local now = GetGameTimer()
    if now < empCooldown then
        local remaining = math.ceil((empCooldown - now) / 1000)
        notify('⏳ EMP em cooldown (' .. remaining .. 's) !', 'error', 3000)
        return
    end

    empCooldown = now + 10000 -- 10s cooldown
    notify('⚡ Disparo EMP activado!', 'success', 3000)

    local hit = false
    local myCoords = GetEntityCoords(veh)
    for _, pid in ipairs(GetActivePlayers()) do
        local enemyPed = GetPlayerPed(pid)
        if enemyPed ~= ped and DoesEntityExist(enemyPed) then
            local svrId = GetPlayerServerId(pid)
            if activeRobbers[tonumber(svrId)] or activeRobbers[tostring(svrId)] then
                local eC = GetEntityCoords(enemyPed)
                local dist = #(myCoords - eC)
                if dist < 45.0 then
                    local eVeh = GetVehiclePedIsIn(enemyPed, false)
                    if DoesEntityExist(eVeh) then
                        hit = true
                        TriggerServerEvent('policia:triggerEMP', svrId)
                        break
                    end
                end
            end
        end
    end
    
    if hit then
        notify('⚡ Carro do Ladrão atingido! Motor congelado por 4 Segundos!', 'success', 5000)
    else
        notify('💨 EMP falhou. Ninguém no raio!', 'error', 3000)
    end
end, false)

RegisterNetEvent('policia:receiveEMP')
AddEventHandler('policia:receiveEMP', function()
    if myRole == 'robber' then
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if DoesEntityExist(veh) then
            notify('💥 SOFRESTE UM CHOQUE EMP! O motor parou durante 4 Segundos!', 'error', 5000)
            SetVehicleEngineOn(veh, false, true, true)
            SetVehicleEngineHealth(veh, -0.0)

            -- Som nativo de alarme interior como aviso em vez de explosão
            PlaySoundFrontend(-1, "Beep_Red", "DLC_HEIST_HACKING_SNAKE_SOUNDS", true)
            
            -- Motor fica a zero, veículo fica inerte... Retoma lentamente com o regen do "SetVehicleEngineHealth a 1000" do loop global
        end
    end
end)

-- ── CORTINA DE FUMO (robber only) — tecla X ──────────────────────

local smokeCooldown = 0

RegisterKeyMapping('ladracaosmoke', 'Cortina de Fumo (Ladrão)', 'keyboard', 'x')
RegisterCommand('ladracaosmoke', function()
    if myRole ~= 'robber' or not roundActive or isFrozen then return end
    
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(veh) then return end

    local now = GetGameTimer()
    if now < smokeCooldown then
        local remaining = math.ceil((smokeCooldown - now) / 1000)
        notify('⏳ Fumo em cooldown (' .. remaining .. 's) !', 'error', 3000)
        return
    end

    smokeCooldown = now + 40000 -- 40s cooldown
    notify('💨 Cortina de Fumo activa!', 'success', 4000)

    Citizen.CreateThread(function()
        local ticks = 0
        while ticks < 8 and DoesEntityExist(veh) do
            local c = GetEntityCoords(veh)
            local offset = GetOffsetFromEntityInWorldCoords(veh, 0.0, -3.0, -0.5)
            AddExplosion(offset.x, offset.y, offset.z, 24, 0.0, false, false, 0.0)
            AddExplosion(offset.x, offset.y, offset.z, 23, 0.0, false, false, 0.0)
            Citizen.Wait(500)
            ticks = ticks + 1
        end
    end)
end, false)



-- ── CAOS PRINCIPAL ────────────────────────────────────────────

local function startChaosZone()
    rampCount = 0
    rampList  = {}

    -- 1. Tráfego extremo
    Citizen.CreateThread(function()
        while roundActive do
            SetVehicleDensityMultiplierThisFrame(10.0)
            SetRandomVehicleDensityMultiplierThisFrame(10.0)
            SetParkedVehicleDensityMultiplierThisFrame(5.0)
            SetPedDensityMultiplierThisFrame(5.0)
            SetScenarioPedDensityMultiplierThisFrame(5.0, 5.0)
            Citizen.Wait(0)
        end
        SetVehicleDensityMultiplierThisFrame(1.0)
        SetRandomVehicleDensityMultiplierThisFrame(1.0)
        SetParkedVehicleDensityMultiplierThisFrame(1.0)
        SetPedDensityMultiplierThisFrame(1.0)
    end)

    -- 2. Limpeza de entidades distantes (performance)
    Citizen.CreateThread(function()
        while roundActive do
            Citizen.Wait(20000)  -- verifica a cada 20s
            if not roundActive then break end
            local myPos    = GetEntityCoords(PlayerPedId())
            local MAX_DIST = 350.0
            local newList  = {}
            for _, e in ipairs(chaosEntities) do
                if DoesEntityExist(e) then
                    local d = #(myPos - GetEntityCoords(e))
                    if d > MAX_DIST then
                        -- Parar task antes de apagar
                        if IsEntityAPed(e) then
                            ClearPedTasksImmediately(e)
                        end
                        SetEntityAsMissionEntity(e, true, true)
                        DeleteEntity(e)
                    else
                        newList[#newList + 1] = e
                    end
                end
            end
            chaosEntities = newList
        end
    end)

    -- 3. ONDAS PROGRESSIVAS — só se waveModeActive
    if waveModeActive then
        Citizen.CreateThread(function()
            Citizen.Wait(8000)
            local waveStart = GetGameTimer()

            -- ── Spawn helpers ───────────────────────────────────

            -- Spawn genérico de veículo com driver perseguidor
            local function spawnChaser(models, dist, driverModel, aggressive)
                local nd = roadNear(dist or math.random(100, 200))
                if not nd then return end
                local h = GetHashKey(models[math.random(#models)])
                RequestModel(h); local t=0
                while not HasModelLoaded(h) and t<30 do Citizen.Wait(100); t=t+1 end
                if not HasModelLoaded(h) then SetModelAsNoLongerNeeded(h); return end
                local v = CreateVehicle(h, nd.x, nd.y, nd.z+0.5, math.random(0,359)*1.0, true, false)
                SetVehicleEngineOn(v, true, false, true)
                SetModelAsNoLongerNeeded(h)
                local dH = GetHashKey(driverModel or 'a_m_y_downtown_01'); RequestModel(dH); t=0
                while not HasModelLoaded(dH) and t<20 do Citizen.Wait(100); t=t+1 end
                if HasModelLoaded(dH) then
                    local d = CreatePedInsideVehicle(v, 26, dH, -1, true, false)
                    SetDriverAggressiveness(d, aggressive or 1.0)
                    SetDriverAbility(d, 1.0)
                    SetPedCombatAttributes(d, 46, true)
                    SetPedCombatAttributes(d, 5, true)
                    SetPedCombatMovement(d, 3)
                    TaskVehicleChase(d, PlayerPedId())
                    SetModelAsNoLongerNeeded(dH)
                    chaosEntities[#chaosEntities+1] = d
                end
                chaosEntities[#chaosEntities+1] = v
                return v
            end

            -- Helicóptero: normal = dispara mísseis | kamikaze = colide com o ladrão
            local function spawnHeli(kamikaze)
                local c = GetEntityCoords(PlayerPedId())
                local a = math.random() * math.pi * 2
                -- Modelos: normal usa buzzard/valkyrie (armados), kamikaze qualquer
                local heliModel = kamikaze
                    and randomFrom({'buzzard', 'annihilator', 'savage'})
                    or  randomFrom({'buzzard2', 'valkyrie', 'hunter'})
                local h = GetHashKey(heliModel)
                RequestModel(h); local t = 0
                while not HasModelLoaded(h) and t < 40 do Citizen.Wait(100); t = t + 1 end
                if not HasModelLoaded(h) then SetModelAsNoLongerNeeded(h); return end

                local spawnDist = kamikaze and 300 or 250
                local heli = CreateVehicle(h,
                    c.x + math.cos(a) * spawnDist,
                    c.y + math.sin(a) * spawnDist,
                    c.z + 80, 0.0, true, false)
                SetVehicleEngineOn(heli, true, false, true)
                SetHeliBladesFullSpeed(heli)
                SetModelAsNoLongerNeeded(h)

                local dH = GetHashKey('s_m_y_pilot_01')
                RequestModel(dH); t = 0
                while not HasModelLoaded(dH) and t < 20 do Citizen.Wait(100); t = t + 1 end
                if HasModelLoaded(dH) then
                    local pilot = CreatePedInsideVehicle(heli, 26, dH, -1, true, false)
                    SetModelAsNoLongerNeeded(dH)
                    chaosEntities[#chaosEntities + 1] = pilot

                    if kamikaze then
                        -- Kamikaze: mergulha diretamente no carro do ladrão
                        notify('🚁 HELI KAMIKAZE EM APROXIMAÇÃO!', 'error', 4000)
                        Citizen.CreateThread(function()
                            -- 1ª fase: aproxima-se rapidamente
                            TaskHeliChase(pilot, PlayerPedId(), 0.0, 0.0, 20.0)
                            Citizen.Wait(6000)
                            if not roundActive or not DoesEntityExist(heli) then return end
                            -- 2ª fase: mergulho suicida direto ao alvo
                            local target = spawnedVehicle and DoesEntityExist(spawnedVehicle)
                                and spawnedVehicle or PlayerPedId()
                            TaskHeliChase(pilot, PlayerPedId(), 0.0, 0.0, -25.0)
                            Citizen.Wait(2000)
                            if not roundActive or not DoesEntityExist(heli) then return end
                            -- 3ª fase: descontrolo total → colidir e explodir
                            SetVehicleOutOfControl(heli, true, true)
                            Citizen.Wait(3000)
                            if DoesEntityExist(heli) then
                                local hp = GetEntityCoords(heli)
                                AddExplosion(hp.x, hp.y, hp.z, 2, 5.0, true, false, 1.0)
                                SetEntityAsMissionEntity(heli, true, true)
                                DeleteEntity(heli)
                            end
                        end)
                    else
                        -- Normal: persegue e dispara mísseis homming
                        local rocketHash = GetHashKey('weapon_hominglauncher')
                        GiveWeaponToPed(pilot, rocketHash, 20, false, true)
                        TaskHeliChase(pilot, PlayerPedId(), 0.0, 0.0, 35.0)
                        Citizen.CreateThread(function()
                            Citizen.Wait(5000)
                            while roundActive and DoesEntityExist(heli) and DoesEntityExist(pilot) do
                                local target = spawnedVehicle and DoesEntityExist(spawnedVehicle)
                                    and spawnedVehicle or GetVehiclePedIsIn(PlayerPedId(), false)
                                if DoesEntityExist(target) then
                                    TaskShootAtEntity(pilot, target, 3000, GetHashKey('FIRING_PATTERN_BURST_FIRE'))
                                end
                                Citizen.Wait(8000)
                            end
                        end)
                    end
                end
                chaosEntities[#chaosEntities + 1] = heli
            end

            -- Avião de carga a baixa altitude (passa por cima assustando)
            local function spawnCargoBomber()
                local c = GetEntityCoords(PlayerPedId())
                local a = math.random() * math.pi * 2
                local planeModels = {'titan', 'cargoplane', 'militaryjet'}
                local h = GetHashKey(planeModels[math.random(#planeModels)])
                RequestModel(h); local t=0
                while not HasModelLoaded(h) and t<40 do Citizen.Wait(100); t=t+1 end
                if not HasModelLoaded(h) then SetModelAsNoLongerNeeded(h); return end
                local plane = CreateVehicle(h,
                    c.x + math.cos(a)*600, c.y + math.sin(a)*600, c.z + 120,
                    math.deg(a) + 180, true, false)
                SetVehicleEngineOn(plane, true, false, true)
                SetModelAsNoLongerNeeded(h)
                local dH = GetHashKey('s_m_y_pilot_01'); RequestModel(dH); t=0
                while not HasModelLoaded(dH) and t<20 do Citizen.Wait(100); t=t+1 end
                if HasModelLoaded(dH) then
                    local pilot = CreatePedInsideVehicle(plane, 26, dH, -1, true, false)
                    SetModelAsNoLongerNeeded(dH)
                    TaskPlaneMission(pilot, plane, 0,
                        c.x - math.cos(a)*800, c.y - math.sin(a)*800, c.z + 80,
                        6, 120.0, 0.0, 0.0, 100.0, -1.0)
                    chaosEntities[#chaosEntities+1] = pilot
                end
                chaosEntities[#chaosEntities+1] = plane
                Citizen.CreateThread(function()
                    Citizen.Wait(30000)
                    if DoesEntityExist(plane) then
                        SetEntityAsMissionEntity(plane, true, true)
                        DeleteEntity(plane)
                    end
                end)
            end

            -- Autocarro / veículo enorme em rota de colisão
            local function spawnBus()
                local nd = roadNear(math.random(60, 140))
                if not nd then return end
                local buses = {'bus', 'airbus', 'coach', 'trash', 'riot', 'brickade'}
                local h = GetHashKey(buses[math.random(#buses)])
                RequestModel(h); local t=0
                while not HasModelLoaded(h) and t<30 do Citizen.Wait(100); t=t+1 end
                if not HasModelLoaded(h) then SetModelAsNoLongerNeeded(h); return end
                local v = CreateVehicle(h, nd.x, nd.y, nd.z+0.5, math.random(0,359)*1.0, true, false)
                SetVehicleEngineOn(v, true, false, true)
                SetModelAsNoLongerNeeded(h)
                local dH = GetHashKey('s_m_m_труcker_01' ~= nil and 's_m_m_trucker_01' or 'a_m_m_tourist_01')
                dH = GetHashKey('s_m_m_trucker_01'); RequestModel(dH); t=0
                while not HasModelLoaded(dH) and t<15 do Citizen.Wait(100); t=t+1 end
                if HasModelLoaded(dH) then
                    local d = CreatePedInsideVehicle(v, 26, dH, -1, true, false)
                    SetDriverAggressiveness(d, 1.0); SetDriverAbility(d, 1.0)
                    TaskVehicleChase(d, PlayerPedId())
                    SetModelAsNoLongerNeeded(dH)
                    chaosEntities[#chaosEntities+1] = d
                end
                chaosEntities[#chaosEntities+1] = v
            end

            -- Camião industrial
            local function spawnTruck()
                local trucks = {'phantom', 'packer', 'hauler', 'mixer', 'flatbed', 'firetruk', 'tiptruck', 'dump'}
                spawnChaser(trucks, math.random(80, 180), 's_m_m_trucker_01', 1.0)
            end

            -- Tanque / veículo blindado
            local function spawnTank(armed)
                local nd = roadNear(math.random(150, 280))
                if not nd then return end
                local tanks = armed and {'rhino', 'khanjali', 'apc'} or {'insurgent2', 'insurgent3', 'barrage', 'insurgent'}
                local h = GetHashKey(tanks[math.random(#tanks)])
                RequestModel(h); local t=0
                while not HasModelLoaded(h) and t<40 do Citizen.Wait(100); t=t+1 end
                if not HasModelLoaded(h) then SetModelAsNoLongerNeeded(h); return end
                local v = CreateVehicle(h, nd.x, nd.y, nd.z+1.0, math.random(0,359)*1.0, true, false)
                SetVehicleEngineOn(v, true, false, true); SetModelAsNoLongerNeeded(h)
                local dH = GetHashKey('s_m_y_swat_01'); RequestModel(dH); t=0
                while not HasModelLoaded(dH) and t<20 do Citizen.Wait(100); t=t+1 end
                if HasModelLoaded(dH) then
                    local d = CreatePedInsideVehicle(v, 26, dH, -1, true, false)
                    if not armed then RemoveAllPedWeapons(d, true) end
                    SetDriverAggressiveness(d, 1.0); SetDriverAbility(d, 1.0)
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
                        Citizen.Wait(2000)
                    end
                end)
            end

            -- ── Definições de ondas por minuto ──────────────────
            local light  = {'blista', 'issi2', 'prairie', 'dilettante'}
            local medium = {'sultan', 'elegy2', 'banshee2', 'ruiner2', 'dominator'}
            local heavy  = {'granger', 'baller2', 'guardian', 'dubsta2', 'mesa3'}

            local waveDefs = {
                [0]  = { label = 'Perseguição Leve',        color = 'blue'   },
                [1]  = { label = 'Carros Rápidos',          color = 'blue'   },
                [2]  = { label = 'Carros Pesados',          color = 'yellow' },
                [3]  = { label = 'Polícia Pesada',          color = 'yellow' },
                [4]  = { label = 'Blindados',               color = 'orange' },
                [5]  = { label = 'Blindados + Helis',       color = 'orange' },
                [6]  = { label = 'Tanques ARMADOS',         color = 'red'    },
                [7]  = { label = 'AVIÕES DE CARGA',         color = 'red'    },
                [8]  = { label = 'Camiões + Helis',         color = 'red'    },
                [9]  = { label = 'Autocarros + Tanques',    color = 'red'    },
                [10] = { label = 'CAOS MÁXIMO',             color = 'red'    },
                [11] = { label = '🌋 CIDADE TOTAL',         color = 'red'    },
            }

            local lastWave  = -1

            while roundActive do
                local sec = (GetGameTimer() - waveStart) / 1000
                local min = math.floor(sec / Config.waveInterval)  -- usa 30s por onda

                -- Anunciar nova onda
                if min ~= lastWave then
                    lastWave    = min
                    currentWave = min
                    local def = waveDefs[min] or waveDefs[11]
                    local wNum = math.min(min + 1, 12)
                    notify('⚡ ONDA ' .. wNum .. ': ' .. def.label .. '!',
                        min >= 5 and 'error' or 'warning', 5000)
                    SendNUIMessage({ action = 'waveUpdate', wave = wNum, label = def.label, color = def.color })
                end

                if myRole == 'robber' then
                    -- CAP: máx 40 entidades chaos antes de pausar spawns
                    local aliveCount = 0
                    for _, e in ipairs(chaosEntities) do
                        if DoesEntityExist(e) then aliveCount = aliveCount + 1 end
                    end
                    if aliveCount > 40 then Citizen.Wait(3000) end

                    if min == 0 then
                        -- Min 0: 5s calmos (era 10s) para sair da zona de spawn
                        Citizen.Wait(5000)

                    elseif min == 1 then
                        -- Min 1: perseguição leve imediata
                        spawnChaser(light, 150, 'a_m_y_downtown_01')
                        Citizen.Wait(4000)

                    elseif min == 2 then
                        -- Min 2: 3 carros leves/médios
                        spawnChaser(light, 150, 'a_m_y_downtown_01')
                        Citizen.Wait(1000)
                        spawnChaser(medium, 170, 'a_m_y_downtown_01')
                        Citizen.Wait(1000)
                        spawnChaser(light, 130, 'a_m_y_downtown_01')
                        Citizen.Wait(4000)

                    elseif min == 3 then
                        -- Min 3: 3 carros de polícia + 2 leves
                        local police = {'police', 'police2', 'police3', 'fbi'}
                        spawnChaser(police, 160, 's_m_y_cop_01')
                        Citizen.Wait(1000)
                        spawnChaser(police, 180, 's_m_y_cop_01')
                        Citizen.Wait(1000)
                        spawnChaser(police, 140, 's_m_y_cop_01')
                        Citizen.Wait(1000)
                        spawnChaser(light, 140, 'a_m_y_downtown_01')
                        Citizen.Wait(1000)
                        spawnChaser(medium, 160, 'a_m_y_downtown_01')
                        Citizen.Wait(4000)

                    elseif min == 4 then
                        -- Min 4: 3 carros pesados
                        spawnChaser(heavy, 150, 'a_m_m_business_01')
                        Citizen.Wait(1500)
                        spawnChaser(heavy, 170, 'a_m_m_business_01')
                        Citizen.Wait(1500)
                        spawnChaser(heavy, 180, 'a_m_m_business_01')
                        Citizen.Wait(6000)

                    elseif min == 5 then
                        -- Min 5: 2 blindados (sem armas) + 2 pesados
                        spawnTank(false)
                        Citizen.Wait(1500)
                        spawnChaser(heavy, 150, 'a_m_m_business_01')
                        Citizen.Wait(1500)
                        spawnTank(false)
                        Citizen.Wait(1500)
                        spawnChaser(heavy, 170, 'a_m_m_business_01')
                        Citizen.Wait(5000)

                    elseif min == 6 then
                        -- Min 6: 1 heli + 2 pesados SWAT
                        spawnHeli(false)
                        Citizen.Wait(1500)
                        spawnChaser(heavy, 150, 's_m_y_swat_01')
                        Citizen.Wait(1500)
                        spawnChaser(heavy, 160, 's_m_y_swat_01')
                        Citizen.Wait(5000)

                    elseif min == 7 then
                        -- Min 7: 2 tanques armados + heli
                        spawnTank(true)
                        Citizen.Wait(1500)
                        spawnTank(true)
                        Citizen.Wait(1500)
                        spawnHeli(false)
                        Citizen.Wait(5000)

                    elseif min == 8 then
                        -- Min 8: heli kamikaze + tanque + pesado
                        spawnHeli(true)
                        Citizen.Wait(1500)
                        spawnTank(true)
                        Citizen.Wait(1500)
                        spawnChaser(heavy, 150, 's_m_y_swat_01')
                        Citizen.Wait(5000)

                    elseif min == 9 then
                        -- Min 9: camião + heli kamikaze + tanque
                        spawnTruck()
                        Citizen.Wait(1500)
                        spawnHeli(true)
                        Citizen.Wait(1500)
                        spawnTank(true)
                        Citizen.Wait(4000)

                    else
                        -- Min 10+: CAOS MÁXIMO — cityRage + tudo em loop apertado
                        cityRage()
                        spawnTank(true)
                        Citizen.Wait(1500)
                        spawnHeli(true)
                        Citizen.Wait(1500)
                        spawnBus()
                        Citizen.Wait(1500)
                        spawnTank(true)
                        Citizen.Wait(4000)
                    end
                else
                    -- Cops: apenas aguardam, não spawnamos nada contra eles
                    Citizen.Wait(10000)
                end
            end
        end)
    else
        notify('🚗 Modo Ondas DESACTIVADO — apenas tráfego caótico!', 'primary', 5000)
    end

    -- 5. Carros de PROTEÇÃO do ladrão — invencíveis, perseguem polícia
    if myRole == 'robber' then
        Citizen.CreateThread(function()
            Citizen.Wait(3000)
            local pModels    = {'baller2', 'granger', 'guardian', 'dubsta2', 'mesa'}
            local numProtect = math.random(2, 3)
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

-- ══ Thread: fora da zona ═ BORDAS SÓLIDAS (rebote + dano) ════

local function startOOBCheck()
    Citizen.CreateThread(function()
        while roundActive do
            if not roundActive or not zoneData then 
                Citizen.Wait(300)
                goto next 
            end

            do
                local ped    = PlayerPedId()
                local coords = GetEntityCoords(ped)
                local dist2d = math.sqrt((coords.x - zoneData.x)^2 + (coords.y - zoneData.y)^2)
                local radius = zoneData.radius

                -- Se perto da borda, check frame a frame para bloquear precisamente
                if dist2d > radius * 0.90 then
                    Citizen.Wait(0)
                else
                    Citizen.Wait(300)
                end

                -- Camada 1: aviso quando está perto da borda
                if dist2d > radius - Config.zoneBounce.warnDist then
                    SendNUIMessage({ action = 'borderWarn', near = true })
                else
                    SendNUIMessage({ action = 'borderWarn', near = false })
                end

                -- Camada 2: Bloqueio físico abrupto se ultrapassar 98%
                if dist2d > radius * 0.98 then
                    local safeDist = radius * 0.95
                    local dirX   = coords.x - zoneData.x
                    local dirY   = coords.y - zoneData.y
                    local dirLen = math.sqrt(dirX^2 + dirY^2)
                    if dirLen < 1.0 then dirLen = 1.0 end
                    local nx = dirX / dirLen
                    local ny = dirY / dirLen

                    local safeX = zoneData.x + nx * safeDist
                    local safeY = zoneData.y + ny * safeDist
                    
                    -- FIX: Usar ground Z para não flutuar
                    local gFound, gZ = GetGroundZFor_3dCoord(safeX, safeY, coords.z + 50.0, false)
                    local safeZ = gFound and (gZ + 0.5) or coords.z

                    local veh = GetVehiclePedIsIn(ped, false)
                    if DoesEntityExist(veh) then
                        SetEntityVelocity(veh, 0.0, 0.0, 0.0)
                        SetEntityCoords(veh, safeX, safeY, safeZ, false, false, false, true)
                        SetVehicleOnGroundProperly(veh)
                        local eh = GetVehicleEngineHealth(veh)
                        if myRole == 'robber' then
                            SetVehicleEngineHealth(veh, math.max(eh - 20.0, 1000.0))
                        end
                    else
                        ClearPedTasksImmediately(ped)
                        SetEntityCoords(ped, safeX, safeY, safeZ, false, false, false, true)
                    end

                    if not outOfBoundsWarn then
                        outOfBoundsWarn = true
                        PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET', true)
                        notify('⛔ ZONA BLOQUEADA! Parede Intransponível!', 'error', 3000)
                        Citizen.CreateThread(function()
                            Citizen.Wait(4000)
                            outOfBoundsWarn = false
                        end)
                    end
                end
            end
            ::next::
        end
        SendNUIMessage({ action = 'borderWarn', near = false })
    end)
end


-- ── Tecla G: Algemar ──────────────────────────────────────────

RegisterKeyMapping('policiaarrestar', 'Algemar / Arrastar Suspeito', 'keyboard', 'g')
RegisterCommand('policiaarrestar', function()
    if myRole ~= 'cop' or not roundActive or isFrozen then return end

    local copPed = PlayerPedId()
    if IsPedInAnyVehicle(copPed, false) then
        notify('❌ Tens de sair do carro para algemar!', 'error', 3000)
        return
    end

    local copCoords = GetEntityCoords(copPed)
    local bestPlayer = -1
    local bestDistance = 9999.0

    for _, playerId in ipairs(GetActivePlayers()) do
        local pPed = GetPlayerPed(playerId)
        if pPed ~= copPed and DoesEntityExist(pPed) and not IsPedDeadOrDying(pPed, true) then
            local dist = #(copCoords - GetEntityCoords(pPed))
            if dist < bestDistance then
                bestDistance = dist
                bestPlayer = GetPlayerServerId(playerId)
            end
        end
    end

    if bestPlayer ~= -1 and bestDistance <= 6.0 then
        TriggerServerEvent('policia:tryArrestClientDistance', bestPlayer, bestDistance)
    else
        notify('❌ Nenhum suspeito ao alcance!', 'error', 3000)
    end
end, false)

-- ── /flip — Endireitar o carro manualmente ────────────────────

RegisterCommand('flip', function()
    if not roundActive then
        notify('❌ Sem ronda activa!', 'error', 3000)
        return
    end
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if not DoesEntityExist(veh) then
        notify('❌ Tens de estar num veículo!', 'error', 3000)
        return
    end
    local pos = GetEntityCoords(veh)
    SetEntityRotation(veh, 0.0, 0.0, GetEntityHeading(veh), 1, true)
    SetEntityCoords(veh, pos.x, pos.y, pos.z + 1.5, false, false, false, true)
    SetVehicleOnGroundProperly(veh)
    notify('🔄 Carro endireitado!', 'success', 3000)
end, false)

-- ══ Tecla H: Helicóptero de Apoio (cops) ══════════════════════

local heliCooldown  = 0
local HELI_TOTAL_CD = Config.heliSupport.cooldown  -- 90s

RegisterKeyMapping('policiaheli', 'Pedir Helicóptero de Apoio', 'keyboard', 'h')
RegisterCommand('policiaheli', function()
    if myRole ~= 'cop' or not roundActive or isFrozen then return end
    local now = GetGameTimer()
    if now < heliCooldown then
        local remaining = math.ceil((heliCooldown - now) / 1000)
        notify('⏳ Heli em cooldown! Espera ' .. remaining .. 's', 'error', 3000)
        return
    end
    heliCooldown = now + (HELI_TOTAL_CD * 1000)
    TriggerServerEvent('policia:requestHeli')
    notify('🚁 Heli de apoio chamado!', 'success', 4000)
    -- Cooldown visual no HUD (barra)
    Citizen.CreateThread(function()
        local elapsed = 0
        while elapsed < HELI_TOTAL_CD and roundActive do
            Citizen.Wait(1000)
            elapsed = elapsed + 1
            SendNUIMessage({ action = 'heliCooldown', total = HELI_TOTAL_CD, remaining = HELI_TOTAL_CD - elapsed })
        end
        SendNUIMessage({ action = 'heliCooldown', total = HELI_TOTAL_CD, remaining = 0 })
    end)
end, false)

-- ══ Tecla N: Drone de Reconhecimento (cops) ═════════════════════

local droneCooldown = 0
local droneActive   = false
local droneBlips    = {}

RegisterKeyMapping('policiadrone', 'Drone de Reconhecimento', 'keyboard', 'n')
RegisterCommand('policiadrone', function()
    if myRole ~= 'cop' or not roundActive or isFrozen then return end
    if droneActive then
        notify('❌ Drone já está activo!', 'error', 2000)
        return
    end
    local now = GetGameTimer()
    if now < droneCooldown then
        local remaining = math.ceil((droneCooldown - now) / 1000)
        notify('⏳ Drone em cooldown! Espera ' .. remaining .. 's', 'error', 3000)
        return
    end
    droneActive = true
    droneCooldown = now + 45000  -- 45s cooldown for 30s usage
    notify('📡 DRONE ACTIVADO! A escanear por 30s...', 'success', 4000)

    TriggerServerEvent('policia:startServerDrone')
end, false)

RegisterNetEvent('policia:updateDroneBlips')
AddEventHandler('policia:updateDroneBlips', function(positions)
    for _, b in ipairs(droneBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    droneBlips = {}
    
    for _, pos in ipairs(positions) do
        local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
        SetBlipSprite(blip, 84)
        SetBlipColour(blip, 1)
        SetBlipScale(blip, 1.2)
        SetBlipFlashes(blip, false)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('LADRÃO (DRONE)')
        EndTextCommandSetBlipName(blip)
        droneBlips[#droneBlips + 1] = blip
    end

    local myPos = GetEntityCoords(PlayerPedId())
    DrawMarker(28,
        myPos.x, myPos.y, myPos.z + 50.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        200.0, 200.0, 200.0,
        0, 200, 255, 40,
        false, true, 2, nil, nil, false)
end)

RegisterNetEvent('policia:stopDroneBlips')
AddEventHandler('policia:stopDroneBlips', function()
    for _, b in ipairs(droneBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    droneBlips = {}
    droneActive = false
    notify('📡 Drone desactivado.', 'primary', 3000)
end)

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

-- ── Registo de eventos Múltiplos ──────────────────────────────

RegisterNetEvent('policia:syncRoles')
AddEventHandler('policia:syncRoles', function(svrCops, svrRobbers)
    activeRobbers = {}
    activeCops = {}
    if svrRobbers then
        for k, v in pairs(svrRobbers) do
            activeRobbers[tonumber(k)] = v
        end
    end
    if svrCops then
        for k, v in pairs(svrCops) do
            activeCops[tonumber(k)] = v
        end
    end
end)

RegisterNetEvent('policia:setupZone')
RegisterNetEvent('policia:assignRole')
RegisterNetEvent('policia:releasePolice')
RegisterNetEvent('policia:sendClue')
RegisterNetEvent('policia:endRound')
RegisterNetEvent('policia:youWereArrested')
RegisterNetEvent('policia:openAdminUI')
RegisterNetEvent('policia:spawnHeli')
RegisterNetEvent('policia:killFeed')
RegisterNetEvent('policia:forceLeaveVehicle')

-- Forçar ladrão a sair do carro (animacão drag)
AddEventHandler('policia:forceLeaveVehicle', function()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if DoesEntityExist(veh) then
        -- Flag 16 = lançado pela janela / arrastado para fora
        TaskLeaveVehicle(PlayerPedId(), veh, 16)
    end
end)

-- ── Reset completo ────────────────────────────────────────────

local function fullReset()
    roundActive     = false
    myRole          = nil
    isFrozen        = false
    outOfBoundsWarn = false
    lastPositions   = {}
    waveModeActive  = true
    currentWave     = 0
    spikeStripsLeft = 0
    heliCooldown    = 0
    droneCooldown   = 0
    droneActive     = false
    isHeliCop       = false
    boostCooldown   = 0
    boostActive     = false
    radarPulseCooldown = 0
    oilSlickCooldown   = 0
    decoyBlipCooldown  = 0
    repairKitCooldown  = 0

    -- Limpar X-ray blips
    for _, b in ipairs(xrayBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    xrayBlips = {}
    
    -- Limpar radar pulse blips
    for _, b in ipairs(radarPulseBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    radarPulseBlips = {}

    SetEntityProofs(PlayerPedId(), false, false, false, false, false, false, false, false)

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

AddEventHandler('policia:assignRole', function(role, carModel, lockSeconds, spawnCoords, weapon, ammo, waveMode, roadblockCount, heliCopFlag)
    myRole          = role
    roundActive     = true
    isFrozen        = false
    outOfBoundsWarn = false
    lastPositions   = {}
    chaosEntities   = {}
    waveModeActive  = (waveMode ~= false)
    currentWave     = 0
    isHeliCop       = heliCopFlag or false

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
    
    -- Se é HeliCop, spawnar helicóptero armado em vez de carro
    if isHeliCop then
        local heliHash = GetHashKey(carModel)
        RequestModel(heliHash)
        local ht = 0
        while not HasModelLoaded(heliHash) and ht < 50 do Citizen.Wait(100); ht = ht + 1 end
        if HasModelLoaded(heliHash) then
            if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
                DeleteEntity(spawnedVehicle)
                spawnedVehicle = nil
            end
            local heli = CreateVehicle(heliHash, spawnX, spawnY, spawnZ + 30.0, spawnCoords.w, true, false)
            SetVehicleEngineOn(heli, true, false, true)
            SetHeliBladesFullSpeed(heli)
            SetEntityInvincible(heli, true)
            SetVehicleCanBeVisiblyDamaged(heli, false)
            SetEntityAsMissionEntity(heli, true, true)
            SetModelAsNoLongerNeeded(heliHash)
            spawnedVehicle = heli
            
            -- Manter desbloqueado
            Citizen.CreateThread(function()
                while roundActive do
                    if DoesEntityExist(heli) then
                        SetVehicleDoorsLocked(heli, 0)
                    end
                    Citizen.Wait(500)
                end
            end)
            
            Citizen.Wait(500)
            TaskWarpPedIntoVehicle(ped, heli, -1)
        end
    else
        local veh = spawnVehicle(carModel, roadPos)
        Citizen.Wait(500)
        warpIntoCar(veh)
    end
    Citizen.Wait(400)
    giveWeaponNow(weapon, ammo)

    if role == 'cop' then
        if isHeliCop then
            notify('🚁 HELI-COP! Pilota o helicóptero armado! Visão X-Ray activa!', 'error')
            freezePlayer(true)
            openNUI('cop', lockSeconds, Config.roundDuration)
        else
            notify('🚓 POLÍCIA! Preso ' .. lockSeconds .. 's. G=Algemar | H=Heli Apoio', 'error')
            freezePlayer(true)
            openNUI('cop', lockSeconds, Config.roundDuration)
        end
    else
        notify('🔪 LADRÃO! Polícias saem em ' .. lockSeconds .. 's. FOGE!', 'warning')
        openNUI('robber', lockSeconds, Config.roundDuration)
    end

    startProximityCheck()
    startOOBCheck()

    -- Tornar os jogadores à prova de bala e imortais totalmente
    SetEntityProofs(ped, true, false, false, false, false, false, false, false)
    SetEntityInvincible(ped, true)

    -- Munição infinita para polícia
    if role == 'cop' then
        Citizen.CreateThread(function()
            local weapHash = GetHashKey(weapon)
            local ped      = PlayerPedId()
            SetPedInfiniteAmmoClip(ped, true)
            while roundActive and myRole == 'cop' do
                GiveWeaponToPed(ped, weapHash, ammo, false, false)
                Citizen.Wait(30000)
            end
        end)
    end



    -- Inicializar spike strips para cops
    if role == 'cop' then
        spikeStripsLeft = Config.spikeStripsPerCop
        SendNUIMessage({ action = 'spikeCount', count = spikeStripsLeft })
    end

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

    -- Reparação periódica e invencibilidade do motor
    Citizen.CreateThread(function()
        while roundActive do
            Citizen.Wait(500)
            if not roundActive then break end
            local veh2 = spawnedVehicle
            if veh2 and DoesEntityExist(veh2) then
                if myRole == 'cop' then
                    if GetVehicleEngineHealth(veh2) < 1000.0 then SetVehicleEngineHealth(veh2, 1000.0) end
                    if GetVehicleBodyHealth(veh2) < 1000.0 then SetVehicleBodyHealth(veh2, 1000.0) end
                    SetVehicleFixed(veh2)
                else
                    -- Ladrão: Motor/Tanque indestrutível, pneus/chassi vulneráveis
                    if GetVehicleEngineHealth(veh2) < 1000.0 then SetVehicleEngineHealth(veh2, 1000.0) end
                    if GetVehiclePetrolTankHealth(veh2) < 1000.0 then SetVehiclePetrolTankHealth(veh2, 1000.0) end
                end
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
        local myC    = GetEntityCoords(PlayerPedId())
        local myPed  = PlayerPedId()
        local DURATION = duration or Config.heliSupport.duration

        -- Tentar buzzard2 primeiro (armas menos loud), fallback para buzzard
        local hHash = GetHashKey('buzzard2')
        RequestModel(hHash)
        local t = 0
        while not HasModelLoaded(hHash) and t < 100 do Citizen.Wait(100); t = t + 1 end
        if not HasModelLoaded(hHash) then
            hHash = GetHashKey('buzzard')
            RequestModel(hHash)
            t = 0
            while not HasModelLoaded(hHash) and t < 100 do Citizen.Wait(100); t = t + 1 end
            if not HasModelLoaded(hHash) then
                notify('❌ O Helicóptero demorou demasiado tempo a carregar. Tenta de novo.', 'error', 4000)
                return
            end
        end

        local spawnX = myC.x - 60.0
        local spawnY = myC.y - 60.0
        local spawnZ = myC.z + (heliAlt or Config.heliSupport.heliAlt)

        local heli = CreateVehicle(hHash, spawnX, spawnY, spawnZ, 0.0, true, false)
        if not DoesEntityExist(heli) then
            notify('❌ Erro crítico: O motor recusou spawn do veículo Heli.', 'error', 4000)
            return
        end
        SetEntityAsMissionEntity(heli, true, true)
        SetVehicleEngineOn(heli, true, false, true)
        SetHeliBladesFullSpeed(heli)
        SetModelAsNoLongerNeeded(hHash)

        -- Blip de imediato (caso o piloto demore, o heli já aparece)
        local hBlip = AddBlipForEntity(heli)
        SetBlipSprite(hBlip, 422)
        SetBlipColour(hBlip, 3)
        SetBlipScale(hBlip, 1.3)
        SetBlipAsShortRange(hBlip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Heli de Apoio')
        EndTextCommandSetBlipName(hBlip)

        -- Piloto
        local pilotHash = GetHashKey('s_m_y_swat_01') -- Ped Swat, carrega 100% mais rápido que pilot_01
        RequestModel(pilotHash)
        t = 0
        while not HasModelLoaded(pilotHash) and t < 100 do Citizen.Wait(100); t = t + 1 end
        if not HasModelLoaded(pilotHash) then 
            notify('❌ Erro: O GTA não conseguiu spawnar o Piloto.', 'error', 4000)
            if DoesEntityExist(heli) then DeleteEntity(heli) end; return 
        end

        local pilot = CreatePedInsideVehicle(heli, 26, pilotHash, -1, true, false)
        if not DoesEntityExist(pilot) then 
            notify('❌ Erro: Piloto falhou ao sentar no Heli.', 'error', 4000)
            if DoesEntityExist(heli) then DeleteEntity(heli) end; return 
        end
        SetEntityAsMissionEntity(pilot, true, true)
        SetModelAsNoLongerNeeded(pilotHash)

        SetPedCombatAttributes(pilot, 46, true)
        SetPedCombatAttributes(pilot, 5, true)
        SetPedAccuracy(pilot, 100)
        GiveWeaponToPed(pilot, GetHashKey('weapon_microsmg'), 1000, false, true)

        -- Holofote sempre activo
        Citizen.CreateThread(function()
            while roundActive and DoesEntityExist(heli) do
                SetVehicleSearchlight(heli, true, true)
                Citizen.Wait(500)
            end
        end)

        -- Loop de controlo a cada 3s: KAMIKAZE nos últimos 6s
        local elapsed = 0
        local isKamikaze = false
        while roundActive and elapsed < DURATION and DoesEntityExist(heli) and DoesEntityExist(pilot) do
            local bestPed  = nil
            local bestDist = 9999.0
            for _, pid in ipairs(GetActivePlayers()) do
                local p = GetPlayerPed(pid)
                if p ~= myPed and DoesEntityExist(p) and not IsPedDeadOrDying(p, true) then
                    local svrId = GetPlayerServerId(pid)
                    if activeRobbers[tonumber(svrId)] or activeRobbers[tostring(svrId)] then
                        local d = #(GetEntityCoords(heli) - GetEntityCoords(p))
                        if d < bestDist then bestDist = d; bestPed = p end
                    end
                end
            end

            local targetPed = bestPed or myPed

            if targetPed and DoesEntityExist(targetPed) then
                if DURATION - elapsed <= 6 and not isKamikaze and bestPed then
                    isKamikaze = true
                    notify('🚁 HELI DE APOIO EM MODO KAMIKAZE!', 'error', 5000)
                    
                    -- Limpar ordens antigas e forçar Kamikaze bruto em direção ao alvo
                    ClearPedTasks(pilot)
                    TaskVehicleDriveToCoord(pilot, heli, GetEntityCoords(targetPed), 150.0, 0, GetEntityModel(heli), 2883621, 1.0, true)
                    
                    Citizen.CreateThread(function()
                        Citizen.Wait(2000)
                        if DoesEntityExist(heli) then 
                            SetVehicleEngineHealth(heli, -4000)
                            SetVehicleOutOfControl(heli, true, true)
                        end
                        Citizen.Wait(3500)
                        if DoesEntityExist(heli) then
                            local hp = GetEntityCoords(heli)
                            AddExplosion(hp.x, hp.y, hp.z, 32, 10.0, true, false, 1.0)
                            if DoesBlipExist(hBlip) then RemoveBlip(hBlip) end
                            SetEntityAsMissionEntity(heli, true, true)
                            DeleteEntity(heli)
                        end
                    end)
                elseif not isKamikaze then
                    -- IA Nativa Completa: Pilotar como combate aéreo e atirar à queima-roupa com as miniguns do veículo
                    TaskHeliMission(pilot, heli, 0, targetPed, 0.0, 0.0, 0.0, 9, 30.0, 30.0, -1.0, 0, 10, -1.0, 0)
                end
            else
                -- Caso não encontre alvo (bestPed) tenta vaguear em busca e voltar ao myPed (policia dono do heli)
                TaskHeliMission(pilot, heli, 0, myPed, 0.0, 0.0, 0.0, 4, 50.0, 25.0, -1.0, 0, 10, -1.0, 0)
            end

            Citizen.Wait(3000)
            elapsed = elapsed + 3
        end

        -- Limpar de forma limpa caso termine o tempo
        if not isKamikaze then
            if DoesBlipExist(hBlip) then RemoveBlip(hBlip) end
            SetVehicleSearchlight(heli, false, false)
            if DoesEntityExist(pilot) then
                ClearPedTasksImmediately(pilot)
                SetEntityAsMissionEntity(pilot, true, true)
                DeleteEntity(pilot)
            end
            if DoesEntityExist(heli) then
                SetEntityAsMissionEntity(heli, true, true)
                DeleteEntity(heli)
            end
            notify('🚁 Helicóptero de apoio retirado.', 'primary', 3000)
        end
    end)
end)

-- ══════════════════════════════════════════════════════════════════
-- ── NOVOS PODERES E SISTEMAS ─────────────────────────────────────
-- ══════════════════════════════════════════════════════════════════

-- ── X-RAY VISION (HeliCop only) ──────────────────────────────────
RegisterNetEvent('policia:xrayUpdate')
AddEventHandler('policia:xrayUpdate', function(positions)
    if not isHeliCop or myRole ~= 'cop' then return end
    
    -- Limpar blips antigos
    for _, b in ipairs(xrayBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    xrayBlips = {}
    
    for _, pos in ipairs(positions) do
        local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
        SetBlipSprite(blip, 84)
        SetBlipColour(blip, 1)
        SetBlipScale(blip, 1.3)
        SetBlipFlashes(blip, false)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('LADRÃO [X-RAY] ' .. (pos.name or ''))
        EndTextCommandSetBlipName(blip)
        xrayBlips[#xrayBlips + 1] = blip
    end
end)

-- ── BOOST (NITRO) — Tecla B — ambos os roles ──────────────────────
RegisterKeyMapping('policiaboost', 'Boost (Nitro)', 'keyboard', 'b')
RegisterCommand('policiaboost', function()
    if not roundActive or isFrozen or boostActive then return end
    if not myRole then return end
    
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(veh) then
        notify('❌ Precisas de estar num veículo!', 'error', 2000)
        return
    end
    
    local now = GetGameTimer()
    if now < boostCooldown then
        local remaining = math.ceil((boostCooldown - now) / 1000)
        notify('⏳ Boost em cooldown (' .. remaining .. 's)!', 'error', 2000)
        return
    end
    
    boostActive = true
    boostCooldown = now + (Config.boost.cooldown * 1000)
    notify('🚀 BOOST ACTIVADO!', 'success', 2000)
    
    -- Aplicar boost
    SetVehicleEnginePowerMultiplier(veh, 20.0 * Config.boost.multiplier)
    SetVehicleEngineTorqueMultiplier(veh, 20.0 * Config.boost.multiplier)
    
    -- Efeito visual: shake
    ShakeGameplayCam('ROAD_VIBRATION_SHAKE', 0.3)
    PlaySoundFrontend(-1, 'FLIGHT_WIND', 'FBI_01_SOUNDS', true)
    
    -- Cooldown visual no HUD
    SendNUIMessage({ action = 'boostActive', duration = Config.boost.duration })
    
    Citizen.CreateThread(function()
        Citizen.Wait(Config.boost.duration * 1000)
        boostActive = false
        if DoesEntityExist(veh) then
            SetVehicleEnginePowerMultiplier(veh, 20.0)
            SetVehicleEngineTorqueMultiplier(veh, 20.0)
        end
        StopGameplayCamShaking(true)
        notify('💨 Boost terminado.', 'primary', 1500)
        
        -- Barra de cooldown no HUD
        local cdLeft = Config.boost.cooldown
        while cdLeft > 0 and roundActive do
            SendNUIMessage({ action = 'boostCooldown', total = Config.boost.cooldown, remaining = cdLeft })
            Citizen.Wait(1000)
            cdLeft = cdLeft - 1
        end
        SendNUIMessage({ action = 'boostCooldown', total = Config.boost.cooldown, remaining = 0 })
    end)
end, false)

-- ── RADAR PULSE (cop only) — Tecla J — 5s de visão, 30s CD ──────
RegisterKeyMapping('policiaradar', 'Radar Pulse (Polícia)', 'keyboard', 'j')
RegisterCommand('policiaradar', function()
    if myRole ~= 'cop' or not roundActive or isFrozen then return end
    if isHeliCop then
        notify('❌ HeliCop já tem X-Ray permanente!', 'error', 2000)
        return
    end
    
    local now = GetGameTimer()
    if now < radarPulseCooldown then
        local remaining = math.ceil((radarPulseCooldown - now) / 1000)
        notify('⏳ Radar em cooldown (' .. remaining .. 's)!', 'error', 2000)
        return
    end
    
    radarPulseCooldown = now + 30000
    notify('📡 RADAR PULSE! Ladrões visíveis por 5s!', 'success', 3000)
    PlaySoundFrontend(-1, 'PICK_UP_SOUND', 'HUD_LIQUOR_STORE_SOUNDSET', true)
    
    TriggerServerEvent('policia:requestRadarPulse')
end, false)

RegisterNetEvent('policia:radarPulseResult')
AddEventHandler('policia:radarPulseResult', function(positions)
    -- Limpar blips antigos
    for _, b in ipairs(radarPulseBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    radarPulseBlips = {}
    
    for _, pos in ipairs(positions) do
        local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
        SetBlipSprite(blip, 84)
        SetBlipColour(blip, 1)
        SetBlipScale(blip, 1.2)
        SetBlipFlashes(blip, true)
        SetBlipAsShortRange(blip, false)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('LADRÃO (RADAR)')
        EndTextCommandSetBlipName(blip)
        radarPulseBlips[#radarPulseBlips + 1] = blip
    end
    
    -- Auto waypoint ao mais próximo
    if #positions > 0 then
        local myPos = GetEntityCoords(PlayerPedId())
        local bestDist = 999999
        local bestPos = positions[1]
        for _, pos in ipairs(positions) do
            local d = #(myPos - vector3(pos.x, pos.y, pos.z))
            if d < bestDist then bestDist = d; bestPos = pos end
        end
        SetNewWaypoint(bestPos.x, bestPos.y)
    end
    
    -- Remover após 5s
    Citizen.CreateThread(function()
        Citizen.Wait(5000)
        for _, b in ipairs(radarPulseBlips) do
            if DoesBlipExist(b) then RemoveBlip(b) end
        end
        radarPulseBlips = {}
    end)
end)

-- ── SPIKE STRIP (cop only) — Tecla K ────────────────────────────
RegisterKeyMapping('policiaspike', 'Colocar Spike Strip (Polícia)', 'keyboard', 'k')
RegisterCommand('policiaspike', function()
    if myRole ~= 'cop' or not roundActive or isFrozen then return end
    if isHeliCop then
        notify('❌ HeliCop não pode colocar spikes!', 'error', 2000)
        return
    end
    
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local fwd = GetEntityForwardVector(ped)
    local spX = pos.x + fwd.x * 5.0
    local spY = pos.y + fwd.y * 5.0
    
    local propHash = GetHashKey('p_ld_stinger_s')
    RequestModel(propHash)
    local t = 0
    while not HasModelLoaded(propHash) and t < 20 do Citizen.Wait(100); t = t + 1 end
    if not HasModelLoaded(propHash) then
        notify('❌ Erro ao carregar spike strip!', 'error', 2000)
        return
    end
    
    local gFound, gZ = GetGroundZFor_3dCoord(spX, spY, pos.z + 10.0, false)
    local finalZ = gFound and gZ or pos.z
    
    local spike = CreateObject(propHash, spX, spY, finalZ, true, true, false)
    if DoesEntityExist(spike) then
        SetEntityHeading(spike, GetEntityHeading(ped))
        PlaceObjectOnGroundProperly(spike)
        FreezeEntityPosition(spike, true)
        SetModelAsNoLongerNeeded(propHash)
        chaosEntities[#chaosEntities + 1] = spike
        notify('🔩 Spike Strip colocada!', 'success', 3000)
        
        -- Thread para detectar veículos que passam por cima
        Citizen.CreateThread(function()
            local spikePos = GetEntityCoords(spike)
            while roundActive and DoesEntityExist(spike) do
                for _, pid in ipairs(GetActivePlayers()) do
                    local pPed = GetPlayerPed(pid)
                    if pPed ~= PlayerPedId() and DoesEntityExist(pPed) then
                        local svrId = GetPlayerServerId(pid)
                        if activeRobbers[tonumber(svrId)] or activeRobbers[tostring(svrId)] then
                            local pVeh = GetVehiclePedIsIn(pPed, false)
                            if DoesEntityExist(pVeh) then
                                local vPos = GetEntityCoords(pVeh)
                                if #(spikePos - vPos) < 4.0 then
                                    -- Rebentar pneus!
                                    for wheel = 0, 7 do
                                        SetVehicleTyreBurst(pVeh, wheel, true, 1000.0)
                                    end
                                    notify('🔩 Spike Strip atingiu um ladrão!', 'success', 3000)
                                    -- Remover spike após uso
                                    if DoesEntityExist(spike) then DeleteEntity(spike) end
                                    return
                                end
                            end
                        end
                    end
                end
                Citizen.Wait(200)
            end
        end)
    end
end, false)

-- ── OIL SLICK (robber only) — Tecla J ────────────────────────────
RegisterKeyMapping('ladraooil', 'Mancha de Óleo (Ladrão)', 'keyboard', 'j')
RegisterCommand('ladraooil', function()
    if myRole ~= 'robber' or not roundActive or isFrozen then return end
    
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(veh) then
        notify('❌ Precisas de estar no carro!', 'error', 2000)
        return
    end
    
    local now = GetGameTimer()
    if now < oilSlickCooldown then
        local remaining = math.ceil((oilSlickCooldown - now) / 1000)
        notify('⏳ Óleo em cooldown (' .. remaining .. 's)!', 'error', 2000)
        return
    end
    
    oilSlickCooldown = now + 25000  -- 25s cooldown
    notify('🛢️ Mancha de Óleo lançada!', 'success', 3000)
    
    Citizen.CreateThread(function()
        local drops = 0
        while drops < 6 and DoesEntityExist(veh) and roundActive do
            local offset = GetOffsetFromEntityInWorldCoords(veh, 0.0, -4.0, -0.5)
            -- Usar explosão tipo "slippery" (tipo 24 = sem dano, fumo)
            AddExplosion(offset.x, offset.y, offset.z, 24, 0.0, false, false, 0.0)
            
            -- Criar prop visual de óleo
            local oilHash = GetHashKey('prop_mp_cone_01')
            RequestModel(oilHash)
            local t = 0
            while not HasModelLoaded(oilHash) and t < 10 do Citizen.Wait(100); t = t + 1 end
            if HasModelLoaded(oilHash) then
                local oil = CreateObject(oilHash, offset.x, offset.y, offset.z - 0.5, true, true, false)
                if DoesEntityExist(oil) then
                    PlaceObjectOnGroundProperly(oil)
                    FreezeEntityPosition(oil, true)
                    SetEntityAlpha(oil, 100, false) -- Semi-transparente
                    chaosEntities[#chaosEntities + 1] = oil
                    -- Auto-delete após 15s
                    Citizen.CreateThread(function()
                        Citizen.Wait(15000)
                        if DoesEntityExist(oil) then DeleteEntity(oil) end
                    end)
                end
                SetModelAsNoLongerNeeded(oilHash)
            end
            
            Citizen.Wait(400)
            drops = drops + 1
        end
    end)
end, false)

-- ── DECOY BLIP (robber only) — Tecla K ──────────────────────────
RegisterKeyMapping('ladraodecoy', 'Blip Falso (Ladrão)', 'keyboard', 'k')
RegisterCommand('ladraodecoy', function()
    if myRole ~= 'robber' or not roundActive or isFrozen then return end
    
    local now = GetGameTimer()
    if now < decoyBlipCooldown then
        local remaining = math.ceil((decoyBlipCooldown - now) / 1000)
        notify('⏳ Decoy em cooldown (' .. remaining .. 's)!', 'error', 2000)
        return
    end
    
    decoyBlipCooldown = now + 45000  -- 45s cooldown
    
    -- Colocar blip falso numa posição aleatória dentro da zona
    local fakeAngle = math.random() * math.pi * 2
    local fakeDist = math.random(200, 600)
    local myPos = GetEntityCoords(PlayerPedId())
    local fakeX = myPos.x + math.cos(fakeAngle) * fakeDist
    local fakeY = myPos.y + math.sin(fakeAngle) * fakeDist
    
    -- Manter dentro da zona
    if zoneData then
        local dx = fakeX - zoneData.x
        local dy = fakeY - zoneData.y
        local dist = math.sqrt(dx*dx + dy*dy)
        if dist > zoneData.radius * 0.8 then
            fakeX = zoneData.x + (dx / dist) * zoneData.radius * 0.7
            fakeY = zoneData.y + (dy / dist) * zoneData.radius * 0.7
        end
    end
    
    local decoyBlip = AddBlipForCoord(fakeX, fakeY, myPos.z)
    SetBlipSprite(decoyBlip, 84)
    SetBlipColour(decoyBlip, 1)
    SetBlipScale(decoyBlip, 1.0)
    SetBlipFlashes(decoyBlip, true)
    SetBlipAsShortRange(decoyBlip, false)
    
    notify('🎭 BLIP FALSO colocado por 15s!', 'success', 3000)
    PlaySoundFrontend(-1, 'PICK_UP_SOUND', 'HUD_LIQUOR_STORE_SOUNDSET', true)
    
    Citizen.CreateThread(function()
        Citizen.Wait(15000)
        if DoesBlipExist(decoyBlip) then RemoveBlip(decoyBlip) end
    end)
end, false)

-- ── REPAIR KIT (robber only) — Tecla Z ──────────────────────────
RegisterKeyMapping('ladraorepair', 'Kit de Reparação (Ladrão)', 'keyboard', 'z')
RegisterCommand('ladraorepair', function()
    if myRole ~= 'robber' or not roundActive or isFrozen then return end
    
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not DoesEntityExist(veh) then
        notify('❌ Precisas de estar no carro!', 'error', 2000)
        return
    end
    
    local now = GetGameTimer()
    if now < repairKitCooldown then
        local remaining = math.ceil((repairKitCooldown - now) / 1000)
        notify('⏳ Reparação em cooldown (' .. remaining .. 's)!', 'error', 2000)
        return
    end
    
    repairKitCooldown = now + 60000  -- 60s cooldown
    
    SetVehicleFixed(veh)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    -- Reparar pneus
    for wheel = 0, 7 do
        if IsVehicleTyreBurst(veh, wheel, false) then
            SetVehicleTyreFixed(veh, wheel)
        end
    end
    
    notify('🔧 Carro REPARADO!', 'success', 3000)
    PlaySoundFrontend(-1, 'PICK_UP_SOUND', 'HUD_LIQUOR_STORE_SOUNDSET', true)
end, false)

-- ══ NAME TAGS — LADRÃO / POLÍCIA acima da cabeça ═══════════════
-- Mostra "LADRÃO" em vermelho (para cops) ou "POLÍCIA" em azul (para robbers)
-- quando estão perto um do outro (< Config.nameTagRange)

local function DrawText3D(x, y, z, text, r, g, b)
    SetTextScale(0.40, 0.40)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(r, g, b, 255)
    SetTextOutline()
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z + 1.1, 0)
    DrawText(0.0, 0.0)
    ClearDrawOrigin()
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if roundActive and myRole then
            local myPed = PlayerPedId()
            local myPos = GetEntityCoords(myPed)
            
            for _, pid in ipairs(GetActivePlayers()) do
                local pPed = GetPlayerPed(pid)
                if pPed ~= myPed and DoesEntityExist(pPed) then
                    local pPos = GetEntityCoords(pPed)
                    local dist = #(myPos - pPos)
                    
                    if dist < Config.nameTagRange then
                        local svrId = GetPlayerServerId(pid)
                        local isRobber = activeRobbers[tonumber(svrId)] or activeRobbers[tostring(svrId)]
                        local isCop = activeCops[tonumber(svrId)] or activeCops[tostring(svrId)]
                        
                        if myRole == 'cop' and isRobber then
                            -- Cop vê "LADRÃO" em vermelho acima do robber
                            DrawText3D(pPos.x, pPos.y, pPos.z, '🔪 LADRÃO', 255, 30, 30)
                        elseif myRole == 'robber' and isCop then
                            -- Robber vê "POLÍCIA" em azul acima do cop
                            DrawText3D(pPos.x, pPos.y, pPos.z, '🚓 POLÍCIA', 30, 100, 255)
                        end
                    end
                end
            end
        else
            Citizen.Wait(500)
        end
    end
end)

-- ── Guard: HeliCop não pode usar poderes de chão ─────────────────
-- Os RegisterCommand para policiaarrestar, policiaemp, policiaturret já
-- verificam myRole == 'cop', mas o HeliCop precisa de guards extras.
-- Vamos patchar com wraps: sobrepor os comandos existentes quando heliCop.

-- NOTA: As teclas G (algemar), E (EMP), U (turret) já existem e verificam se
-- está fora do carro ou dentro dum carro de polícia. Como o HeliCop está
-- dentro do helicóptero, essas verificações naturalmente bloqueiam a maioria.
-- Adicionamos guard explícito no assignRole handler onde já se trata.

-- ── SÓ AUTOCARROS COMO TRÂNSITO ──────────────────────────────────
Citizen.CreateThread(function()
    local busHash = GetHashKey('bus')
    local driverHash = GetHashKey('a_m_m_tourist_01')
    local ambientBuses = {}

    while true do
        Citizen.Wait(0)
        if roundActive then
            -- 1. Matar o spawning normal e carros estacionados do GTA
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
            
            -- 1.5. Apagar brutal e ativamente as falsas existências do motor (Tráfego que a engine crie teimosamente)
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                if DoesEntityExist(veh) and GetEntityModel(veh) ~= busHash then
                    -- Se o veículo não é do script nem de um player (não é Missão), a IA do jogo tentou pô-lo nas ruas. Elimina.
                    if not IsEntityAMissionEntity(veh) then
                        SetEntityAsMissionEntity(veh, true, true)
                        DeleteEntity(veh)
                    end
                end
            end
            
            -- 2. Sistema Custom de População de Autocarros a cada 2 segundos
            if GetGameTimer() % 2000 == 0 then
                local myC = GetEntityCoords(PlayerPedId())
                
                -- Limpar buses velhos longe
                for i = #ambientBuses, 1, -1 do
                    local b = ambientBuses[i]
                    if not DoesEntityExist(b) or #(GetEntityCoords(b) - myC) > 300.0 then
                        if DoesEntityExist(b) then DeleteEntity(b) end
                        table.remove(ambientBuses, i)
                    end
                end
                
                -- Spawn novo se não houver suficientes (max 8)
                if #ambientBuses < 8 then
                    local rx = myC.x + math.random(-250, 250)
                    local ry = myC.y + math.random(-250, 250)
                    local nodeOk, nodePos, nodeHeading = GetClosestVehicleNodeWithHeading(rx, ry, myC.z, 1, 3.0, 0)
                    
                    if nodeOk and #(nodePos - myC) > 80.0 then
                        if not IsSphereVisible(nodePos.x, nodePos.y, nodePos.z, 5.0) then
                            RequestModel(busHash)
                            RequestModel(driverHash)
                            local t = 0
                            while (not HasModelLoaded(busHash) or not HasModelLoaded(driverHash)) and t < 20 do
                                Citizen.Wait(100); t = t + 1
                            end
                            if HasModelLoaded(busHash) and HasModelLoaded(driverHash) then
                                local bus = CreateVehicle(busHash, nodePos.x, nodePos.y, nodePos.z, nodeHeading, true, false)
                                local driver = CreatePedInsideVehicle(bus, 26, driverHash, -1, true, false)
                                TaskVehicleDriveWander(driver, bus, 25.0, 786603)
                                SetEntityAsMissionEntity(bus, true, true)
                                SetEntityAsMissionEntity(driver, true, true)
                                table.insert(ambientBuses, bus)
                                SetModelAsNoLongerNeeded(busHash)
                                SetModelAsNoLongerNeeded(driverHash)
                            end
                        end
                    end
                end
            end
        else
            -- Limpar se a ronda acabar
            for i = #ambientBuses, 1, -1 do
                if DoesEntityExist(ambientBuses[i]) then DeleteEntity(ambientBuses[i]) end
            end
            ambientBuses = {}
            Citizen.Wait(1000)
        end
    end
end)

AddEventHandler('baseevents:onPlayerDied', function()
    if myRole == 'robber' and roundActive then
        TriggerServerEvent('policia:robberDied')
    end
end)
