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
    SetVehicleTyresCanBurst(veh, false)  -- Pneus invencíveis
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
                            TaskStandGuard(swat, nodePos.x, nodePos.y, nodePos.z, 0.0)
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

-- ── POWER-UPS ─────────────────────────────────────────────────
-- Spawna 6 pickup points aleatórios na zona; efeito instantâneo ao entrar no raio

local powerupActive = false

local powerups = {
    { icon = '🔧', label = 'Reparação do Carro',  color = {0,200,100,200},  role = 'robber',
      effect = function()
          if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
              SetVehicleFixed(spawnedVehicle)
              SetVehicleEngineHealth(spawnedVehicle, 1000.0)
              SetVehicleBodyHealth(spawnedVehicle, 1000.0)
          end
          SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
          notify('🔧 Carro reparado!', 'success', 3000)
      end },
    { icon = '🛡️', label = 'Colete Completo',     color = {0,150,255,200},  role = 'any',
      effect = function()
          SetPedArmour(PlayerPedId(), 100)
          notify('🛡️ Colete recarregado!', 'success', 3000)
      end },
    { icon = '⚡',  label = 'Boost de Velocidade', color = {255,220,0,200},   role = 'robber',
      effect = function()
          if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
              SetVehicleEngineOn(spawnedVehicle, true, true, false)
              ModifyVehicleTopSpeed(spawnedVehicle, 1.5)
              notify('⚡ BOOST! (+50% velocidade por 15s)', 'success', 4000)
              Citizen.CreateThread(function()
                  Citizen.Wait(15000)
                  if DoesEntityExist(spawnedVehicle) then
                      ModifyVehicleTopSpeed(spawnedVehicle, 1.0 / 1.5)
                  end
              end)
          end
      end },
    { icon = '❤️', label = 'Vida Completa',       color = {255,80,80,200},   role = 'any',
      effect = function()
          SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
          notify('❤️ Vida ao máximo!', 'success', 3000)
      end },
    { icon = '💊', label = 'Invencível 5s',       color = {180,0,255,200},   role = 'robber',
      effect = function()
          SetEntityInvincible(PlayerPedId(), true)
          notify('💊 INVENCÍVEL por 5 segundos!', 'success', 4000)
          Citizen.CreateThread(function()
              Citizen.Wait(5000)
              if roundActive then SetEntityInvincible(PlayerPedId(), false) end
          end)
      end },
    { icon = '🔫', label = 'Munição Extra (cop)',  color = {100,180,255,200}, role = 'cop',
      effect = function()
          local ped  = PlayerPedId()
          local hash = GetHashKey(Config.policeWeapon)
          GiveWeaponToPed(ped, hash, 300, false, false)
          notify('🔫 +300 munições!', 'success', 3000)
      end },
}

local function startPowerups()
    if powerupActive then return end
    if not zoneData then return end
    powerupActive = true

    local pickupPoints = {}
    local PICKUP_RADIUS = 3.0

    -- Gerar 6 pontos distribuídos pela zona
    for i = 1, 6 do
        local angle = (i - 1) * (math.pi * 2 / 6)
        local rfrac = 0.3 + math.random() * 0.45
        local px    = zoneData.x + math.cos(angle) * zoneData.radius * rfrac
        local py    = zoneData.y + math.sin(angle) * zoneData.radius * rfrac
        local pDef  = powerups[((i - 1) % #powerups) + 1]
        -- Z será determinado no thread de render (GetGroundZFor_3dCoord precisa de contexto)
        pickupPoints[i] = { x = px, y = py, z = zoneData.z, groundFound = false, def = pDef, taken = false, respawnAt = 0 }
    end

    Citizen.CreateThread(function()
        -- Resolver Z no chão a partir do thread
        Citizen.Wait(1000)
        for _, p in ipairs(pickupPoints) do
            local found, gz = GetGroundZFor_3dCoord(p.x, p.y, p.z + 100.0, false)
            if found then p.z = gz + 0.1 end
            p.groundFound = true
        end
    end)

    Citizen.CreateThread(function()
        while powerupActive do
            local myPos = GetEntityCoords(PlayerPedId())
            local now   = GetGameTimer()

            for _, p in ipairs(pickupPoints) do
                if p.taken and now >= p.respawnAt then
                    p.taken = false
                end

                if not p.taken and p.groundFound then
                    local show = (p.def.role == 'any') or (p.def.role == myRole)
                    if show then
                        local c    = p.def.color
                        local dist = #(myPos - vector3(p.x, p.y, p.z))

                        -- Marcador circular no chão
                        DrawMarker(1,
                            p.x, p.y, p.z,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            2.0, 2.0, 0.5,
                            c[1], c[2], c[3], c[4],
                            false, true, 2, nil, nil, false)
                        -- Seta apontando para baixo por cima
                        DrawMarker(27,
                            p.x, p.y, p.z + 2.5,
                            0.0, 0.0, 0.0,
                            0.0, 0.0, 0.0,
                            0.7, 0.7, 0.7,
                            c[1], c[2], c[3], 200,
                            false, true, 2, nil, nil, false)

                        -- Texto 2D no ecrã quando perto
                        if dist < 20.0 then
                            local onScreen, sx, sy = World3dToScreen2d(p.x, p.y, p.z + 1.5)
                            if onScreen then
                                SetTextFont(4)
                                SetTextProportional(true)
                                SetTextScale(0.4, 0.4)
                                SetTextColour(255, 255, 255, 255)
                                SetTextOutline()
                                SetTextEntry('STRING')
                                AddTextComponentString(p.def.icon .. '  ' .. p.def.label)
                                DrawText(sx, sy)
                            end
                        end

                        -- Colisão
                        if dist < PICKUP_RADIUS then
                            p.taken     = true
                            p.respawnAt = now + 30000
                            p.def.effect()
                        end
                    end
                end
            end

            Citizen.Wait(0)
        end
    end)
end


-- ── CAOS PRINCIPAL ────────────────────────────────────────────

local function startChaosZone()
    rampCount = 0
    rampList  = {}

    -- 1. Tráfego extremo
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
                local min = math.floor(sec / 60)

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
                    -- CAP: nunca mais de 8 entidades chaos
                    local aliveCount = 0
                    for _, e in ipairs(chaosEntities) do
                        if DoesEntityExist(e) then aliveCount = aliveCount + 1 end
                    end
                    if aliveCount > 16 then Citizen.Wait(5000) end  -- espera se já há muita coisa

                    if min == 0 then
                        -- Min 0-1: COMPLETAMENTE CALMO, ladrão tem 2 min para se orientar
                        Citizen.Wait(60000)

                    elseif min == 1 then
                        -- Min 1: ainda calmo (apenas leve aviso)
                        if min ~= lastWave - 1 then  -- só notifica na transição
                            notify('⚠️ A calma está quase a acabar...', 'warning', 5000)
                        end
                        Citizen.Wait(60000)

                    elseif min == 2 then
                        -- Min 2: 1 carro leve de perseguição
                        spawnChaser(light, 150, 'a_m_y_downtown_01')
                        Citizen.Wait(30000)

                    elseif min == 3 then
                        -- Min 3: 1 carro pesado de polícia
                        local police = {'police', 'police2', 'police3', 'fbi'}
                        spawnChaser(police, 160, 's_m_y_cop_01')
                        Citizen.Wait(25000)

                    elseif min == 4 then
                        -- Min 4: 2 carros pesados
                        spawnChaser(heavy, 150, 'a_m_m_business_01')
                        Citizen.Wait(3000)
                        spawnChaser(heavy, 180, 'a_m_m_business_01')
                        Citizen.Wait(20000)

                    elseif min == 5 then
                        -- Min 5: 1 blindado (sem armas) + 1 carro pesado
                        spawnTank(false)
                        Citizen.Wait(3000)
                        spawnChaser(heavy, 150, 'a_m_m_business_01')
                        Citizen.Wait(18000)

                    elseif min == 6 then
                        -- Min 6: 1 heli (mísseis) + 1 carro pesado
                        spawnHeli(false)
                        Citizen.Wait(3000)
                        spawnChaser(heavy, 150, 's_m_y_swat_01')
                        Citizen.Wait(18000)

                    elseif min == 7 then
                        -- Min 7: tanque armado + 1 heli
                        spawnTank(true)
                        Citizen.Wait(3000)
                        spawnHeli(false)
                        Citizen.Wait(18000)

                    elseif min == 8 then
                        -- Min 8: 1 heli kamikaze + 1 tanque
                        spawnHeli(true)
                        Citizen.Wait(3000)
                        spawnTank(true)
                        Citizen.Wait(15000)

                    elseif min == 9 then
                        -- Min 9: camião + heli kamikaze
                        spawnTruck()
                        Citizen.Wait(3000)
                        spawnHeli(true)
                        Citizen.Wait(15000)

                    else
                        -- Min 10+: tanque + heli + autocarro (máx. intensidade)
                        spawnTank(true)
                        Citizen.Wait(3000)
                        spawnHeli(true)
                        Citizen.Wait(3000)
                        spawnBus()
                        Citizen.Wait(12000)
                    end
                else
                    -- Cops: spawn leve para manter acção
                    spawnChaser(light, 200, 'a_m_y_downtown_01', 0.5)
                    Citizen.Wait(45000)
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

RegisterKeyMapping('policiaarrestar', 'Algemar / Arrastar Suspeito', 'keyboard', 'g')
RegisterCommand('policiaarrestar', function()
    if myRole ~= 'cop' or not roundActive or isFrozen then return end
    -- Funciona dentro E fora do carro; o servidor valida alcance e estado do ladrão
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
    powerupActive   = false

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

    -- Auto-flip: se o carro do ladrão ficar virado > 5s, endireita automaticamente
    if role == 'robber' then
        Citizen.CreateThread(function()
            local tiltedSince = nil
            while roundActive and myRole == 'robber' do
                Citizen.Wait(500)
                local veh = spawnedVehicle
                if veh and DoesEntityExist(veh) and GetPedInVehicleSeat(veh, -1) == PlayerPedId() then
                    local rot      = GetEntityRotation(veh, 1)
                    local isTilted = math.abs(rot.x) > 70.0 or math.abs(rot.y) > 70.0
                    if isTilted then
                        if not tiltedSince then
                            tiltedSince = GetGameTimer()
                        elseif (GetGameTimer() - tiltedSince) > 5000 then
                            local pos = GetEntityCoords(veh)
                            SetEntityRotation(veh, 0.0, 0.0, GetEntityHeading(veh), 1, true)
                            SetEntityCoords(veh, pos.x, pos.y, pos.z + 1.5, false, false, false, true)
                            SetVehicleOnGroundProperly(veh)
                            notify('\ud83d\udd04 Carro endireitado automaticamente!', 'success', 3000)
                            tiltedSince = nil
                        end
                    else
                        tiltedSince = nil
                    end
                else
                    tiltedSince = nil
                end
            end
        end)
    end


    -- Roadblocks para todos
    if roadblockCount and roadblockCount > 0 then
        spawnRoadblocks(roadblockCount)
    end

    -- Iniciar caos + power-ups após 5s
    Citizen.CreateThread(function()
        Citizen.Wait(5000)
        if roundActive then
            startChaosZone()
            startPowerups()   -- power-ups na zona
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
        local myC = GetEntityCoords(PlayerPedId())

        -- Heli de apoio de polícia — mais agressivo, dispara mísseis
        local heliModels = {'hunter', 'valkyrie', 'buzzard2'}
        local hHash = GetHashKey(randomFrom(heliModels))
        RequestModel(hHash)
        local t = 0
        while not HasModelLoaded(hHash) and t < 30 do Citizen.Wait(100); t = t + 1 end
        if not HasModelLoaded(hHash) then return end

        local spawnX = targetCoords and targetCoords.x or myC.x
        local spawnY = targetCoords and targetCoords.y or myC.y
        local spawnZ = (targetCoords and targetCoords.z or myC.z) + (heliAlt or 80)

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
            -- Armar com mísseis de perseguição
            local rocketHash = GetHashKey('weapon_hominglauncher')
            GiveWeaponToPed(pilot, rocketHash, 30, false, true)
            SetModelAsNoLongerNeeded(pilotHash)
        end

        -- Perseguir e disparar ao ladrão
        if pilot then
            -- Perseguição ativa do heli
            local allPlayers = GetActivePlayers()
            local robberPed  = nil
            for _, playerId in ipairs(allPlayers) do
                local ped = GetPlayerPed(playerId)
                if ped ~= PlayerPedId() then
                    robberPed = ped
                    break
                end
            end
            if robberPed then
                TaskHeliChase(pilot, robberPed, 0.0, 0.0, 30.0)
            end

            -- Thread de mísseis: dispara a cada 8s contra o carro do ladrão
            Citizen.CreateThread(function()
                local elapsed = 0
                Citizen.Wait(4000)  -- delay inicial
                while roundActive and elapsed < duration and DoesEntityExist(heli) and DoesEntityExist(pilot) do
                    -- Tentar encontrar carro do ladrão
                    local target = nil
                    for _, playerId in ipairs(GetActivePlayers()) do
                        local ped = GetPlayerPed(playerId)
                        if ped ~= PlayerPedId() and IsPedInAnyVehicle(ped, false) then
                            target = GetVehiclePedIsIn(ped, false)
                            break
                        end
                    end
                    if target and DoesEntityExist(target) then
                        TaskShootAtEntity(pilot, target, 2500, GetHashKey('FIRING_PATTERN_BURST_FIRE'))
                    end
                    Citizen.Wait(8000)
                    elapsed = elapsed + 8
                end
            end)
        end

        -- Holofote
        Citizen.CreateThread(function()
            while roundActive and DoesEntityExist(heli) do
                SetVehicleSearchlight(heli, true, true)
                Citizen.Wait(500)
            end
        end)

        -- Duração total do apoio
        Citizen.Wait(duration * 1000)

        -- Desaparecer
        SetVehicleSearchlight(heli, false, false)
        if pilot and DoesEntityExist(pilot) then
            ClearPedTasksImmediately(pilot)
            SetEntityAsMissionEntity(pilot, true, true)
            DeleteEntity(pilot)
        end
        if DoesEntityExist(heli) then
            SetEntityAsMissionEntity(heli, true, true)
            DeleteEntity(heli)
        end
        notify('\ud83d\ude81 Helic\u00f3ptero de apoio retirado.', 'primary', 3000)
    end)
end)


AddEventHandler('baseevents:onPlayerDied', function()
    if myRole == 'robber' and roundActive then
        TriggerServerEvent('policia:robberDied')
    end
end)
