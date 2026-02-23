local QBCore = exports['qb-core']:GetCoreObject()

local myRole           = nil
local roundActive      = false
local spawnedVehicle   = nil
local spawnedPlate     = nil
local tempBlips        = {}
local zoneBlip         = nil
local isFrozen         = false
local outOfBoundsWarn  = false
local lastPositions    = {}
local zoneData         = nil
local chaosEntities    = {}   -- todos os props/veículos/peds de caos

-- ── Utilitários ──────────────────────────────────────────────

local function notify(msg, msgType, dur)
    QBCore.Functions.Notify(msg, msgType or 'primary', dur or 7000)
end

-- ── Upgrade de veículo ────────────────────────────────────────

local function upgradeVehicle(veh)
    SetVehicleModKit(veh, 0)
    for modType = 0, 49 do
        local maxMod = GetNumVehicleMods(veh, modType) - 1
        if maxMod >= 0 then SetVehicleMod(veh, modType, maxMod, false) end
    end
    ToggleVehicleMod(veh, 18, true)   -- Turbo
    ToggleVehicleMod(veh, 22, true)   -- Xenon
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
    spawnedPlate   = plate

    -- Desbloquear permanentemente (lock 0 = None, sem locks)
    Citizen.CreateThread(function()
        while roundActive do
            if DoesEntityExist(veh) then
                SetVehicleDoorsLocked(veh, 0)
            end
            Citizen.Wait(500)
        end
    end)

    -- Dar chaves via qb-vehiclekeys (tenta ambas as versões)
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

-- ── Freeze (veículo + ped) ────────────────────────────────────

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
        Citizen.CreateThread(function()
            while isFrozen do
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

-- ── Limpeza de tudo (caos + veículos + peds) ─────────────────

local function cleanupChaos()
    for _, e in ipairs(chaosEntities) do
        if DoesEntityExist(e) then DeleteEntity(e) end
    end
    chaosEntities = {}
end

-- ── ZONA DE CAOS (cidade toda) ────────────────────────────────

local function spawnRamp(x, y, rampModels)
    local model  = rampModels[math.random(#rampModels)]
    local hash   = GetHashKey(model)
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) and t < 20 do Citizen.Wait(100); t = t + 1 end
    if not HasModelLoaded(hash) then return end

    local found, gz = GetGroundZFor_3dCoord(x, y, 200.0, false)
    if not found then gz = 30.0 end

    local prop = CreateObject(hash, x, y, gz, true, false, false)
    SetEntityHeading(prop, math.random(0, 359) * 1.0)
    PlaceObjectOnGroundProperly(prop)
    FreezeEntityPosition(prop, true)
    SetModelAsNoLongerNeeded(hash)
    chaosEntities[#chaosEntities + 1] = prop
end

local function spawnChaseVehicle(px, py)
    local carModels = {'blista', 'issi2', 'sultan', 'banshee2', 'ruiner'}
    local carModel  = carModels[math.random(#carModels)]
    local carHash   = GetHashKey(carModel)
    RequestModel(carHash)
    local t = 0
    while not HasModelLoaded(carHash) and t < 20 do Citizen.Wait(100); t = t + 1 end
    if not HasModelLoaded(carHash) then return end

    local found, gz = GetGroundZFor_3dCoord(px, py, 200.0, false)
    if not found then gz = 30.0 end

    local veh = CreateVehicle(carHash, px, py, gz + 0.5, math.random(0, 359) * 1.0, true, false)
    SetVehicleEngineOn(veh, true, false, true)
    SetModelAsNoLongerNeeded(carHash)

    local driverHash = GetHashKey('a_m_y_downtown_01')
    RequestModel(driverHash)
    t = 0
    while not HasModelLoaded(driverHash) and t < 20 do Citizen.Wait(100); t = t + 1 end

    if HasModelLoaded(driverHash) then
        local driver = CreatePedInsideVehicle(veh, 26, driverHash, -1, true, false)
        TaskVehicleChase(driver, PlayerPedId())
        SetDriverAggressiveness(driver, 1.0)
        SetDriverAbility(driver, 1.0)
        SetModelAsNoLongerNeeded(driverHash)
        chaosEntities[#chaosEntities + 1] = driver
    end
    chaosEntities[#chaosEntities + 1] = veh
end

local function startChaosZone()
    local rampModels = {
        'prop_mp_ramp_02', 'prop_mp_ramp_03',
        'prop_ramp_wooden_01', 'prop_mp_ramp_06',
    }

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

    -- 2. 30+ rampas por toda a cidade
    Citizen.CreateThread(function()
        -- Centro da cidade + pontos dispersos
        local cityPoints = {
            {200, -900}, {0, -600}, {400, -600}, {-400, -600},
            {200, -500}, {600, -800}, {-600, -800}, {100, -1100},
            {800, -400}, {-800, -400}, {1000, -700}, {-1000, -700},
            {300, -1300}, {-300, -1300}, {600, -1500}, {-600, -1500},
            {900, -1200}, {-900, -1200}, {200, -1700}, {-200, -1700},
            {500, -1900}, {0, -1900}, {1200, -900}, {-1200, -900},
            {1400, -500}, {-1400, -500}, {700, -200}, {-700, -200},
            {1600, -1100}, {-1600, -1100}, {400, -2000}, {-400, -2000},
            {1100, -1500}, {-1100, -1500}, {0, -400},
        }

        for _, pt in ipairs(cityPoints) do
            spawnRamp(pt[1], pt[2], rampModels)
            spawnRamp(pt[1] + math.random(-80, 80), pt[2] + math.random(-80, 80), rampModels)
            Citizen.Wait(300)
        end
    end)

    -- 3. Veículos a perseguir o jogador (periódico)
    Citizen.CreateThread(function()
        Citizen.Wait(5000)
        local wave = 0
        while roundActive do
            wave = wave + 1
            local coords = GetEntityCoords(PlayerPedId())
            local angle  = math.random() * math.pi * 2
            local dist   = math.random(100, 250)
            local px = coords.x + math.cos(angle) * dist
            local py = coords.y + math.sin(angle) * dist
            spawnChaseVehicle(px, py)

            -- Nova vaga a cada 25s
            Citizen.Wait(25000)
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

            if closest < 30 then
                SendNUIMessage({ action = 'danger', level = 2 })
                notify('🚨 INIMIGO MUITO PRÓXIMO! (~' .. math.floor(closest) .. 'm)', 'error', 2500)
            elseif closest < Config.alertRange then
                SendNUIMessage({ action = 'danger', level = 1 })
            else
                SendNUIMessage({ action = 'danger', level = 0 })
            end

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
                            Citizen.Wait(1000)
                            t = t - 1
                            local c = GetEntityCoords(PlayerPedId())
                            local d = #(vector3(c.x, c.y, c.z) - vector3(zoneData.x, zoneData.y, zoneData.z))
                            if d <= zoneData.radius then
                                outOfBoundsWarn = false
                                notify('✅ De volta à zona!', 'success', 3000)
                                return
                            end
                        end
                        if roundActive and outOfBoundsWarn then
                            TriggerServerEvent('policia:outOfBounds')
                        end
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
        notify('🚗 Sai do carro para algemar!', 'error', 3000)
        return
    end
    TriggerServerEvent('policia:tryArrest')
end, false)

-- ── Registo de eventos de rede ────────────────────────────────

RegisterNetEvent('policia:setupZone')
RegisterNetEvent('policia:assignRole')
RegisterNetEvent('policia:releasePolice')
RegisterNetEvent('policia:sendClue')
RegisterNetEvent('policia:endRound')
RegisterNetEvent('policia:youWereArrested')

-- ── Função de reset total ─────────────────────────────────────

local function fullReset()
    roundActive     = false
    myRole          = nil
    isFrozen        = false
    outOfBoundsWarn = false
    lastPositions   = {}

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
    spawnedPlate = nil
    removeAllWeapons()
end

-- ── Handlers de eventos ───────────────────────────────────────

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
    SetEntityCoords(ped, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false, true)
    SetEntityHeading(ped, spawnCoords.w)
    Citizen.Wait(1200)

    local veh = spawnVehicle(carModel, spawnCoords)
    Citizen.Wait(500)
    warpIntoCar(veh)
    Citizen.Wait(400)
    giveWeaponNow(weapon, ammo)

    if role == 'cop' then
        notify('🚓 És POLÍCIA! Preso ' .. lockSeconds .. 's. Depois: sai do carro + G = Algemar.', 'error')
        freezePlayer(true)
        openNUI('cop', lockSeconds, Config.roundDuration)
    else
        notify('🔪 És LADRÃO! As polícias saem em ' .. lockSeconds .. 's. FOGE!', 'warning')
        openNUI('robber', lockSeconds, Config.roundDuration)
    end

    startProximityCheck()
    startOOBCheck()

    Citizen.CreateThread(function()
        Citizen.Wait(8000)
        if roundActive then
            startChaosZone()
            notify('🔥 CAOS ACTIVADO! Carros agressivos e rampas por toda a cidade!', 'warning', 5000)
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
    notify('🔒 Foste APANHADO! Ronda terminada para ti.', 'error')
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
