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
    -- ═══ ROBBER POWER-UPS ═══
    { icon = '🔧', label = 'Reparação Total',       color = {0,220,100,220},   role = 'robber',
      prop = 'prop_tool_spanner',
      effect = function()
          if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
              SetVehicleFixed(spawnedVehicle)
              SetVehicleEngineHealth(spawnedVehicle, 1000.0)
              SetVehicleBodyHealth(spawnedVehicle, 1000.0)
              SetVehicleDirtLevel(spawnedVehicle, 0.0)
              for w = 0, 7 do SetVehicleTyreFixed(spawnedVehicle, w) end
          end
          SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
          notify('🔧 Carro + vida reparados!', 'success', 3000)
      end },
    { icon = '⚡', label = 'NITRO BOOST',           color = {255,180,0,255},   role = 'robber',
      prop = 'prop_cs_dildo_01',  -- pequeno cilindro como NOS
      effect = function()
          if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
              -- Boost imediato + velocidade
              local heading = GetEntityHeading(spawnedVehicle)
              local rad     = math.rad(heading)
              ApplyForceToEntityCenterOfMass(spawnedVehicle, 1, 0.0, 80.0, 0.0, false, true, true, false)
              ModifyVehicleTopSpeed(spawnedVehicle, 1.6)
              notify('⚡ NITRO! +60% velocidade por 12s!', 'success', 4000)
              Citizen.CreateThread(function()
                  Citizen.Wait(12000)
                  if DoesEntityExist(spawnedVehicle) then
                      ModifyVehicleTopSpeed(spawnedVehicle, 1.0 / 1.6)
                  end
              end)
          end
      end },
    { icon = '👻', label = 'GHOST MODE',            color = {255,255,255,180},  role = 'robber',
      prop = 'prop_ghost_skin',
      effect = function()
          -- Invisível + sem colisão por 8s
          local ped = PlayerPedId()
          SetEntityAlpha(ped, 50, false)
          if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
              SetEntityAlpha(spawnedVehicle, 80, false)
          end
          SetEntityInvincible(ped, true)
          notify('👻 GHOST MODE! Quase invisível por 8s!', 'success', 4000)
          Citizen.CreateThread(function()
              Citizen.Wait(8000)
              if roundActive then
                  ResetEntityAlpha(ped)
                  SetEntityInvincible(ped, false)
                  if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
                      ResetEntityAlpha(spawnedVehicle)
                  end
              end
          end)
      end },
    { icon = '💣', label = 'EMP BLAST',             color = {100,50,255,255},   role = 'robber',
      prop = 'prop_cs_heist_bag_01',
      effect = function()
          -- Desliga todos os veículos inimigos próximos
          local myPos = GetEntityCoords(PlayerPedId())
          local count = 0
          for _, v in ipairs(GetGamePool('CVehicle')) do
              if v ~= spawnedVehicle and DoesEntityExist(v) then
                  local d = #(myPos - GetEntityCoords(v))
                  if d < 60.0 then
                      SetVehicleEngineOn(v, false, true, true)
                      SetVehicleUndriveable(v, true)
                      count = count + 1
                  end
              end
          end
          AddExplosion(myPos.x, myPos.y, myPos.z, 36, 0.0, true, true, 0.5)  -- EMP visual
          notify('💣 EMP! ' .. count .. ' veículos desligados!', 'success', 4000)
          Citizen.CreateThread(function()
              Citizen.Wait(10000)
              for _, v in ipairs(GetGamePool('CVehicle')) do
                  if DoesEntityExist(v) then SetVehicleUndriveable(v, false) end
              end
          end)
      end },
    { icon = '🌀', label = 'TELEPORT ALEATÓRIO',   color = {255,0,200,255},    role = 'robber',
      prop = 'prop_cs_heist_bag_02',
      effect = function()
          if not zoneData then return end
          -- Teletransportar para ponto aleatório dentro da zona
          local angle = math.random() * math.pi * 2
          local rfrac = 0.2 + math.random() * 0.5
          local nx    = zoneData.x + math.cos(angle) * zoneData.radius * rfrac
          local ny    = zoneData.y + math.sin(angle) * zoneData.radius * rfrac
          local ok, nd = GetClosestVehicleNode(nx, ny, zoneData.z, 0, 3.0, 0)
          if ok and nd then
              if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
                  SetEntityCoords(spawnedVehicle, nd.x, nd.y, nd.z + 1.0, false, false, false, true)
              else
                  SetEntityCoords(PlayerPedId(), nd.x, nd.y, nd.z + 1.0, false, false, false, true)
              end
              notify('🌀 TELEPORTADO para posição aleatória!', 'success', 4000)
          end
      end },

    -- ═══ COP POWER-UPS ═══
    { icon = '🔫', label = 'Arma PESADA',           color = {80,180,255,220},   role = 'cop',
      prop = 'prop_cs_tablet',
      effect = function()
          local ped = PlayerPedId()
          local heavyGuns = {'weapon_combatmg', 'weapon_sniperrifle', 'weapon_rpg'}
          local gun = heavyGuns[math.random(#heavyGuns)]
          GiveWeaponToPed(ped, GetHashKey(gun), 50, false, true)
          SetPedInfiniteAmmoClip(ped, true)
          notify('🔫 Arma pesada recebida!', 'success', 3000)
      end },
    { icon = '🚨', label = 'SPIKE STRIP',           color = {255,50,50,255},    role = 'cop',
      prop = 'prop_barrier_work_06b',
      effect = function()
          -- Spawna spike strip à frente do cop
          local ped = PlayerPedId()
          local pos = GetEntityCoords(ped)
          local fwd = GetEntityForwardVector(ped)
          local spX = pos.x + fwd.x * 8.0
          local spY = pos.y + fwd.y * 8.0
          local spikeH = GetHashKey('p_stinger_06')
          RequestModel(spikeH)
          local t = 0
          while not HasModelLoaded(spikeH) and t < 20 do Citizen.Wait(100); t = t + 1 end
          if HasModelLoaded(spikeH) then
              local spike = CreateObject(spikeH, spX, spY, pos.z, true, true, false)
              if DoesEntityExist(spike) then
                  PlaceObjectOnGroundProperly(spike)
                  SetEntityHeading(spike, GetEntityHeading(ped))
                  chaosEntities[#chaosEntities + 1] = spike
                  notify('🚨 Spike strip colocada!', 'success', 3000)
                  -- Auto-remover após 45s
                  Citizen.CreateThread(function()
                      Citizen.Wait(45000)
                      if DoesEntityExist(spike) then
                          SetEntityAsMissionEntity(spike, true, true)
                          DeleteEntity(spike)
                      end
                  end)
              end
              SetModelAsNoLongerNeeded(spikeH)
          end
      end },

    -- ═══ AMBOS ═══
    { icon = '❤️', label = 'Vida + Colete',         color = {255,50,80,220},    role = 'any',
      prop = 'prop_ld_health_pack',
      effect = function()
          SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
          SetPedArmour(PlayerPedId(), 100)
          notify('❤️ Vida e colete ao máximo!', 'success', 3000)
      end },
    { icon = '💨', label = 'SUPER SALTO',           color = {0,255,200,220},    role = 'any',
      prop = 'prop_cs_fury',
      effect = function()
          SetSuperJumpThisFrame(PlayerId())
          notify('💨 Super salto activado por 20s!', 'success', 4000)
          Citizen.CreateThread(function()
              local t2 = 0
              while t2 < 20000 and roundActive do
                  SetSuperJumpThisFrame(PlayerId())
                  Citizen.Wait(0)
                  t2 = t2 + 1  -- ~20s
              end
          end)
      end },
    { icon = '🔥', label = 'CARRO EM CHAMAS',       color = {255,100,0,255},    role = 'any',
      prop = 'prop_fire_exting_1a',
      effect = function()
          -- Carro fica com visual de fogo (não destrói)
          if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
              SetVehicleNeonLightEnabled(spawnedVehicle, 0, true)
              SetVehicleNeonLightEnabled(spawnedVehicle, 1, true)
              SetVehicleNeonLightEnabled(spawnedVehicle, 2, true)
              SetVehicleNeonLightEnabled(spawnedVehicle, 3, true)
              SetVehicleNeonLightsColour(spawnedVehicle, 255, 80, 0)
              -- Boost temporário de 30%
              ModifyVehicleTopSpeed(spawnedVehicle, 1.3)
              notify('🔥 MODO FOGO! Neon + 30% speed por 15s!', 'success', 4000)
              Citizen.CreateThread(function()
                  Citizen.Wait(15000)
                  if DoesEntityExist(spawnedVehicle) then
                      ModifyVehicleTopSpeed(spawnedVehicle, 1.0 / 1.3)
                      for n = 0, 3 do SetVehicleNeonLightEnabled(spawnedVehicle, n, false) end
                  end
              end)
          end
      end },
}

-- ══ POWER-UP SYSTEM ══════════════════════════════════════

local function startPowerups()
    if powerupActive then return end
    if not zoneData then return end
    powerupActive = true

    local pickupPoints = {}
    local PICKUP_RADIUS = 4.0
    local NUM_PICKUPS   = 12  -- distribuídos pela zona toda

    for i = 1, NUM_PICKUPS do
        local angle = ((i - 1) / NUM_PICKUPS) * math.pi * 2 + math.random() * 0.3
        local rfrac = 0.2 + math.random() * 0.6  -- entre 20% e 80% do raio
        local px    = zoneData.x + math.cos(angle) * zoneData.radius * rfrac
        local py    = zoneData.y + math.sin(angle) * zoneData.radius * rfrac
        local pDef  = powerups[math.random(#powerups)]  -- power-up aleatório
        pickupPoints[i] = {
            x = px, y = py, z = zoneData.z,
            groundFound = false, def = pDef,
            taken = false, respawnAt = 0,
            propObj = nil,
        }
    end

    -- Resolver Z no chão
    Citizen.CreateThread(function()
        Citizen.Wait(2000)
        for _, p in ipairs(pickupPoints) do
            RequestCollisionAtCoord(p.x, p.y, p.z)
            Citizen.Wait(200)
            local found, gz = GetGroundZFor_3dCoord(p.x, p.y, p.z + 100.0, false)
            if found then p.z = gz + 0.05 end
            p.groundFound = true
        end
    end)

    -- Thread para spawnar/despawnar props (3D objects a girar)
    Citizen.CreateThread(function()
        Citizen.Wait(3000)
        while powerupActive do
            local myPos = GetEntityCoords(PlayerPedId())
            for _, p in ipairs(pickupPoints) do
                local dist = #(myPos - vector3(p.x, p.y, p.z))
                local show = (p.def.role == 'any') or (p.def.role == myRole)

                if not p.taken and p.groundFound and show and dist < 120.0 then
                    -- Spawnar prop se não existe
                    if not p.propObj or not DoesEntityExist(p.propObj) then
                        local propH = GetHashKey(p.def.prop)
                        RequestModel(propH)
                        local t = 0
                        while not HasModelLoaded(propH) and t < 15 do Citizen.Wait(100); t = t + 1 end
                        if HasModelLoaded(propH) then
                            p.propObj = CreateObject(propH, p.x, p.y, p.z + 1.0, false, false, false)
                            if DoesEntityExist(p.propObj) then
                                FreezeEntityPosition(p.propObj, true)
                                SetEntityCollision(p.propObj, false, false)
                                SetEntityAlpha(p.propObj, 200, false)
                            end
                            SetModelAsNoLongerNeeded(propH)
                        end
                    end
                else
                    -- Apagar prop se longe ou apanhado
                    if p.propObj and DoesEntityExist(p.propObj) then
                        SetEntityAsMissionEntity(p.propObj, true, true)
                        DeleteEntity(p.propObj)
                        p.propObj = nil
                    end
                end
            end
            Citizen.Wait(2000)
        end
        -- Limpar todos os props ao desativar
        for _, p in ipairs(pickupPoints) do
            if p.propObj and DoesEntityExist(p.propObj) then
                SetEntityAsMissionEntity(p.propObj, true, true)
                DeleteEntity(p.propObj)
            end
        end
    end)

    -- Thread de render: marcadores + rotação do prop + texto + colisão
    Citizen.CreateThread(function()
        local spinAngle = 0.0
        while powerupActive do
            local myPos = GetEntityCoords(PlayerPedId())
            local now   = GetGameTimer()
            spinAngle   = spinAngle + 2.0
            if spinAngle > 360.0 then spinAngle = 0.0 end

            for _, p in ipairs(pickupPoints) do
                if p.taken and now >= p.respawnAt then
                    p.taken = false
                    -- Re-sortear power-up
                    p.def = powerups[math.random(#powerups)]
                end

                if not p.taken and p.groundFound then
                    local show = (p.def.role == 'any') or (p.def.role == myRole)
                    if show then
                        local c    = p.def.color
                        local dist = #(myPos - vector3(p.x, p.y, p.z))

                        if dist < 100.0 then
                            -- Pilar de luz vertical (visível de longe)
                            DrawMarker(1,
                                p.x, p.y, p.z + 5.0,
                                0.0, 0.0, 0.0,
                                0.0, 0.0, 0.0,
                                0.4, 0.4, 10.0,
                                c[1], c[2], c[3], 100,
                                false, true, 2, nil, nil, false)

                            -- Círculo pulsante no chão
                            local pulse = 1.8 + math.sin(now * 0.005) * 0.4
                            DrawMarker(25,
                                p.x, p.y, p.z + 0.05,
                                0.0, 0.0, 0.0,
                                0.0, 0.0, 0.0,
                                pulse, pulse, 0.3,
                                c[1], c[2], c[3], 160,
                                false, true, 2, nil, nil, false)

                            -- Rodar o prop
                            if p.propObj and DoesEntityExist(p.propObj) then
                                local bob = math.sin(now * 0.003) * 0.3
                                SetEntityCoords(p.propObj, p.x, p.y, p.z + 1.0 + bob, false, false, false, false)
                                SetEntityRotation(p.propObj, 0.0, 0.0, spinAngle, 1, false)
                            end
                        end

                        -- Texto com ícone quando perto
                        if dist < 25.0 then
                            local onScreen, sx, sy = World3dToScreen2d(p.x, p.y, p.z + 2.0)
                            if onScreen then
                                SetTextFont(4)
                                SetTextProportional(true)
                                SetTextScale(0.5, 0.5)
                                SetTextColour(c[1], c[2], c[3], 255)
                                SetTextOutline()
                                SetTextCentre(true)
                                SetTextEntry('STRING')
                                AddTextComponentString(p.def.icon .. '  ' .. p.def.label)
                                DrawText(sx, sy)
                            end
                        end

                        -- Colisão / apanhar
                        if dist < PICKUP_RADIUS then
                            p.taken     = true
                            p.respawnAt = now + 25000  -- 25s respawn
                            PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
                            p.def.effect()
                            -- Apagar prop
                            if p.propObj and DoesEntityExist(p.propObj) then
                                SetEntityAsMissionEntity(p.propObj, true, true)
                                DeleteEntity(p.propObj)
                                p.propObj = nil
                            end
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

-- ══ Thread: fora da zona ═ HARD WALL (teletransporta de volta) ════

local function startOOBCheck()
    Citizen.CreateThread(function()
        while roundActive do
            Citizen.Wait(500)
            if not roundActive or not zoneData then goto next end
            do
                local ped    = PlayerPedId()
                local coords = GetEntityCoords(ped)
                local center = vector3(zoneData.x, zoneData.y, zoneData.z)
                local dist   = #(vector3(coords.x, coords.y, coords.z) - center)
                local limit  = zoneData.radius * 0.95

                if dist > limit then
                    local dirX    = coords.x - zoneData.x
                    local dirY    = coords.y - zoneData.y
                    local dirLen  = math.sqrt(dirX * dirX + dirY * dirY)
                    if dirLen < 1.0 then dirLen = 1.0 end
                    local safeDist = zoneData.radius * 0.85
                    local safeX   = zoneData.x + (dirX / dirLen) * safeDist
                    local safeY   = zoneData.y + (dirY / dirLen) * safeDist

                    local veh = GetVehiclePedIsIn(ped, false)
                    if DoesEntityExist(veh) then
                        SetEntityCoords(veh, safeX, safeY, coords.z, false, false, false, true)
                        SetVehicleOnGroundProperly(veh)
                    else
                        SetEntityCoords(ped, safeX, safeY, coords.z, false, false, false, true)
                    end

                    if not outOfBoundsWarn then
                        outOfBoundsWarn = true
                        PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET', true)
                        notify('⛔ ZONA BLOQUEADA! Não podes sair!', 'error', 3000)
                        Citizen.CreateThread(function()
                            Citizen.Wait(4000)
                            outOfBoundsWarn = false
                        end)
                    end
                end
            end
            ::next::
        end
    end)
end


-- ── Tecla G: Algemar ──────────────────────────────────────────

RegisterKeyMapping('policiaarrestar', 'Algemar / Arrastar Suspeito', 'keyboard', 'g')
RegisterCommand('policiaarrestar', function()
    if myRole ~= 'cop' or not roundActive or isFrozen then return end
    TriggerServerEvent('policia:tryArrest')
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

-- ══ Tecla H: Helicóptero de Apoio (cops) ═ 60s duração + 60s cooldown ══

local heliCooldown = 0

RegisterKeyMapping('policiaheli', 'Pedir Helicóptero de Apoio', 'keyboard', 'h')
RegisterCommand('policiaheli', function()
    if myRole ~= 'cop' or not roundActive or isFrozen then return end
    local now = GetGameTimer()
    if now < heliCooldown then
        local remaining = math.ceil((heliCooldown - now) / 1000)
        notify('⏳ Heli em cooldown! Espera ' .. remaining .. 's', 'error', 3000)
        return
    end
    heliCooldown = now + 120000  -- 60s duração + 60s cooldown = 2min total
    -- Disparar evento com 60s de duração
    local robberPos = nil
    for _, pos in ipairs(lastPositions) do
        if pos.role == 'robber' then robberPos = pos; break end
    end
    TriggerEvent('policia:spawnHeli', robberPos, 60, 80)
    notify('🚁 Heli de apoio chamado! (60s)', 'success', 4000)
end, false)

-- ══ Tecla J: Drone de Reconhecimento (cops) ═════════════════════

local droneCooldown = 0
local droneActive   = false

RegisterKeyMapping('policiadrone', 'Drone de Reconhecimento', 'keyboard', 'j')
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
    droneCooldown = now + 90000  -- 90s cooldown
    notify('📡 DRONE ACTIVADO! A escanear por 15s...', 'success', 4000)

    Citizen.CreateThread(function()
        local droneBlips = {}
        local elapsed    = 0

        while elapsed < 15 and roundActive do
            -- Limpar blips antigos
            for _, b in ipairs(droneBlips) do
                if DoesBlipExist(b) then RemoveBlip(b) end
            end
            droneBlips = {}

            -- Marcar todos os jogadores inimigos
            for _, playerId in ipairs(GetActivePlayers()) do
                local ped = GetPlayerPed(playerId)
                if ped ~= PlayerPedId() and DoesEntityExist(ped) then
                    local pos = GetEntityCoords(ped)
                    local blip = AddBlipForCoord(pos.x, pos.y, pos.z)
                    SetBlipSprite(blip, 84)       -- círculo
                    SetBlipColour(blip, 1)         -- vermelho
                    SetBlipScale(blip, 1.2)
                    SetBlipFlashes(blip, true)
                    SetBlipAsShortRange(blip, false)
                    BeginTextCommandSetBlipName('STRING')
                    AddTextComponentString('LADRÃO DETECTADO')
                    EndTextCommandSetBlipName(blip)
                    droneBlips[#droneBlips + 1] = blip
                end
            end

            -- Efeito visual: scan pulse
            if elapsed % 3 == 0 then
                local myPos = GetEntityCoords(PlayerPedId())
                DrawMarker(28,
                    myPos.x, myPos.y, myPos.z + 50.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    200.0, 200.0, 200.0,
                    0, 200, 255, 40,
                    false, true, 2, nil, nil, false)
            end

            Citizen.Wait(1000)
            elapsed = elapsed + 1
        end

        -- Limpar blips
        for _, b in ipairs(droneBlips) do
            if DoesBlipExist(b) then RemoveBlip(b) end
        end
        droneActive = false
        notify('📡 Drone desactivado.', 'primary', 3000)
    end)
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

        -- Perseguir e disparar ao ladrão com combate real
        if pilot then
            -- Encontrar ped do ladrão
            local robberPed = nil
            for _, playerId in ipairs(GetActivePlayers()) do
                local ped = GetPlayerPed(playerId)
                if ped ~= PlayerPedId() then
                    robberPed = ped
                    break
                end
            end

            if robberPed then
                -- Configurar IA de combate do piloto
                SetPedCombatAttributes(pilot, 1,  true)  -- pode usar veículos em combate
                SetPedCombatAttributes(pilot, 5,  true)  -- pode lutar contra peds armados
                SetPedCombatAttributes(pilot, 17, true)  -- pode atacar alvo no veículo
                SetPedCombatAttributes(pilot, 46, true)  -- reage sempre ao alvo
                SetPedCombatRange(pilot, 2)               -- alcance longo
                SetPedAlertness(pilot, 3)                 -- máximo alerta

                -- Perseguição ativa a baixa altitude para tiros mais precisos
                TaskHeliChase(pilot, robberPed, 0.0, 0.0, 15.0)

                -- Combate contínuo: a cada 6s reafirma o alvo para o piloto não desistir
                Citizen.CreateThread(function()
                    local elapsed = 0
                    Citizen.Wait(3000)
                    while roundActive and elapsed < duration and DoesEntityExist(heli) and DoesEntityExist(pilot) do
                        if DoesEntityExist(robberPed) then
                            -- Virar piloto para o alvo + disparar
                            TaskCombatPed(pilot, robberPed, 0, 16)
                            Citizen.Wait(2000)
                            -- Retomar perseguição depois de disparar
                            if DoesEntityExist(heli) and DoesEntityExist(pilot) then
                                TaskHeliChase(pilot, robberPed, 0.0, 0.0, 15.0)
                            end
                        end
                        Citizen.Wait(6000)
                        elapsed = elapsed + 8
                    end
                end)
            end
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
        notify('🚁 Helicóptero de apoio retirado.', 'primary', 3000)
    end)
end)


AddEventHandler('baseevents:onPlayerDied', function()
    if myRole == 'robber' and roundActive then
        TriggerServerEvent('policia:robberDied')
    end
end)
