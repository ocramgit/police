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

    -- Manter desbloqueado (lock 0 = None, sem qualquer lock)
    Citizen.CreateThread(function()
        while roundActive do
            if DoesEntityExist(veh) then
                SetVehicleDoorsLocked(veh, 0)
            end
            Citizen.Wait(500)
        end
    end)

    -- Dar chaves via qb-vehiclekeys
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

-- ── Freeze (generation counter evita race condition entre rondas) ───────

local freezeGen = 0  -- incrementado a cada freeze; thread antiga sai ao ver geração diferente

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
            -- limpar ao sair — seja por isFrozen=false OU nova geração
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

local function showZone(x, y, z, radius)
    zoneData = { x = x, y = y, z = z, radius = radius }
    if zoneBlip then RemoveBlip(zoneBlip) end
    zoneBlip = AddBlipForRadius(x, y, z, radius)
    SetBlipColour(zoneBlip, 2)
    SetBlipAlpha(zoneBlip, 90)
end

local function removeZone()
    if zoneBlip then RemoveBlip(zoneBlip) end
    zoneBlip = nil
    zoneData = nil
end

-- ── Limpeza de caos ───────────────────────────────────────────

local function cleanupChaos()
    for _, e in ipairs(chaosEntities) do
        if DoesEntityExist(e) then DeleteEntity(e) end
    end
    chaosEntities = {}
end

-- ── Spawn de rampa numa posição de estrada ───────────────────
-- nodeX/Y/Z vêm de GetClosestVehicleNode; terreno garantidamente carregado

local rampCount   = 0
local MAX_RAMPS   = 80
local rampList    = {}   -- lista separada para poder apagar as mais antigas

local function spawnRampOnRoad(nx, ny, nz, size)
    if rampCount >= MAX_RAMPS then
        -- Apagar a rampa mais antiga
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

    -- Terreno carregado (perto do jogador): Z directo
    local gFound, gz = GetGroundZFor_3dCoord(nx, ny, nz + 50.0, false)
    local finalZ = gFound and gz or nz

    local prop = CreateObject(hash, nx, ny, finalZ + 0.1, true, true, false)
    if not DoesEntityExist(prop) then SetModelAsNoLongerNeeded(hash); return false end

    -- Heading variado: alinhado à estrada ou diagonal
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

-- ── CAOS PRINCIPAL ────────────────────────────────────────────

local function startChaosZone()
    rampCount = 0
    rampList  = {}

    -- 1. Rampa especial fixa (coordenada do utilizador)
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

    -- 3. Rampas dinâmicas progressivas — sempre na estrada, perto do jogador
    --    Quanto mais tempo passa: mais rampas, mais perto
    Citizen.CreateThread(function()
        Citizen.Wait(4000)
        local startTime = GetGameTimer()

        while roundActive do
            local elapsed = (GetGameTimer() - startTime) / 1000

            -- Frequência e proximidade escalam com o tempo
            local interval, batch, minDist, maxDist
            if     elapsed < 60  then interval, batch, minDist, maxDist = 20000, 1, 100, 200  -- 0–1 min
            elseif elapsed < 180 then interval, batch, minDist, maxDist = 12000, 2,  70, 160  -- 1–3 min
            elseif elapsed < 360 then interval, batch, minDist, maxDist =  7000, 3,  40, 110  -- 3–6 min
            elseif elapsed < 540 then interval, batch, minDist, maxDist =  4000, 4,  20,  80  -- 6–9 min
            else                      interval, batch, minDist, maxDist =  2500, 5,  10,  50  -- 9+ min
            end

            -- Tamanho varia por ciclo
            local sizes = {'small', 'medium', 'large'}

            for i = 1, batch do
                if not roundActive then break end
                local pedCoords = GetEntityCoords(PlayerPedId())
                local angle     = math.random() * math.pi * 2
                local dist      = math.random(minDist, maxDist)
                local tx        = pedCoords.x + math.cos(angle) * dist
                local ty        = pedCoords.y + math.sin(angle) * dist

                -- GetClosestVehicleNode funciona porque estamos perto do jogador (terreno carregado)
                local roadFound, nodePos = GetClosestVehicleNode(tx, ty, pedCoords.z, 0, 3.0, 0)
                if roadFound and nodePos then
                    local sz = sizes[((rampCount) % 3) + 1]
                    spawnRampOnRoad(nodePos.x, nodePos.y, nodePos.z, sz)
                end
                Citizen.Wait(600)
            end

            Citizen.Wait(interval)
        end
    end)

    -- 4. Ondas de carros agressivos — escalam com o tempo
    Citizen.CreateThread(function()
        Citizen.Wait(8000)
        local startTime = GetGameTimer()

        while roundActive do
            local elapsed = (GetGameTimer() - startTime) / 1000

            local interval, batch
            if     elapsed < 60  then interval, batch = 30000, 1
            elseif elapsed < 180 then interval, batch = 20000, 2
            elseif elapsed < 360 then interval, batch = 14000, 3
            elseif elapsed < 540 then interval, batch = 10000, 4
            else                      interval, batch =  7000, 5
            end

            if myRole == 'robber' then batch = batch + 1 end

            for _ = 1, batch do
                spawnChaseVehicle()
                Citizen.Wait(800)
            end
            Citizen.Wait(interval)
        end
    end)
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

-- ── Registo de eventos ────────────────────────────────────────

RegisterNetEvent('policia:setupZone')
RegisterNetEvent('policia:assignRole')
RegisterNetEvent('policia:releasePolice')
RegisterNetEvent('policia:sendClue')
RegisterNetEvent('policia:endRound')
RegisterNetEvent('policia:youWereArrested')

-- ── Reset completo ────────────────────────────────────────────

local function fullReset()
    roundActive     = false
    myRole          = nil
    isFrozen        = false
    outOfBoundsWarn = false
    lastPositions   = {}

    freezePlayer(false)
    closeNUI()
    removeZone()
    cleanupChaos()   -- apaga todas as rampas, carros e peds de caos

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

AddEventHandler('policia:setupZone', function(x, y, z, radius)
    showZone(x, y, z, radius)
end)

AddEventHandler('policia:assignRole', function(role, carModel, lockSeconds, spawnCoords, weapon, ammo)
    myRole          = role
    roundActive     = true
    isFrozen        = false
    outOfBoundsWarn = false
    lastPositions   = {}
    chaosEntities   = {}

    removeAllWeapons()

    local ped = PlayerPedId()

    -- 1. Teleporte acima da área (z+200 garante acima de qualquer edifício ou terreno)
    SetEntityCoords(ped, spawnCoords.x, spawnCoords.y, spawnCoords.z + 200.0, false, false, false, true)
    Citizen.Wait(2500)  -- aguardar colisão e streaming

    -- 2. GetClosestVehicleNode devolve (bool, vector3) no FiveM — desempacotar correctamente
    local roadFound, nodePos = GetClosestVehicleNode(spawnCoords.x, spawnCoords.y, spawnCoords.z, 0, 3.0, 0)

    local spawnX, spawnY, spawnZ

    if roadFound and nodePos then
        -- nodePos é um vector3
        spawnX = nodePos.x
        spawnY = nodePos.y
        spawnZ = nodePos.z + 1.0
    else
        -- Fallback: usar GetGroundZFor_3dCoord para pelo menos acertar o Z
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
        notify('🚓 POLÍCIA! Preso ' .. lockSeconds .. 's. Depois: sai do carro + G = Algemar.', 'error')
        freezePlayer(true)
        openNUI('cop', lockSeconds, Config.roundDuration)
    else
        notify('🔪 LADRÃO! Polícias saem em ' .. lockSeconds .. 's. FOGE! Há carros a perseguir-te!', 'warning')
        openNUI('robber', lockSeconds, Config.roundDuration)
    end

    startProximityCheck()
    startOOBCheck()

    -- Iniciar caos após 5s
    Citizen.CreateThread(function()
        Citizen.Wait(5000)
        if roundActive then
            startChaosZone()
            notify('🔥 CAOS: ' .. #Config.rampPositions .. ' rampas activadas! Carros agressivos em patrulha!', 'warning', 6000)
        end
    end)
end)

AddEventHandler('policia:releasePolice', function()
    if myRole ~= 'cop' then return end
    freezePlayer(false)
    notify('🚨 LIBERTO! VAI À CAÇA! (Sai do carro + G = Algemar)', 'success')
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

AddEventHandler('baseevents:onPlayerDied', function()
    if myRole == 'robber' and roundActive then
        TriggerServerEvent('policia:robberDied')
    end
end)
