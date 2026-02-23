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
local chaosProps       = {}
local chaosPeds        = {}

-- ── Utilitários ──────────────────────────────────────────────

local function notify(msg, msgType, dur)
    QBCore.Functions.Notify(msg, msgType or 'primary', dur or 7000)
end

-- ── Upgrade de veículo ────────────────────────────────────────

local function upgradeVehicle(veh, fullUpgrade)
    SetVehicleModKit(veh, 0)
    if fullUpgrade then
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
    else
        -- Ladrão com azar: carro em mau estado
        SetVehicleEngineHealth(veh, math.random(200, 500))
        SetVehicleBodyHealth(veh, math.random(300, 650))
        SetVehiclePetrolTankHealth(veh, math.random(400, 900))
    end
end

-- ── Spawn de veículo ──────────────────────────────────────────

local function spawnVehicle(model, coords, isPolice)
    local hash = GetHashKey(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Citizen.Wait(100) end

    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        DeleteEntity(spawnedVehicle)
        spawnedVehicle = nil
    end

    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z + 0.5, coords.w, true, false)
    local plate = 'JOGO-' .. math.random(1000, 9999)
    SetVehicleNumberPlateText(veh, plate)
    SetVehicleDoorsLocked(veh, 1)   -- Unlocked
    SetModelAsNoLongerNeeded(hash)

    -- Upgrades
    if isPolice then
        upgradeVehicle(veh, true)                -- sempre full max
    else
        local fullChance = math.random(100)
        upgradeVehicle(veh, fullChance > 50)     -- 50% full, 50% mau
    end

    spawnedVehicle = veh

    -- Manter carro desbloqueado durante a ronda
    Citizen.CreateThread(function()
        while roundActive do
            Citizen.Wait(3000)
            if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
                SetVehicleDoorsLocked(spawnedVehicle, 1)
            end
        end
    end)

    -- Dar chaves via qb-vehiclekeys (tenta ambas as versões de evento)
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

-- ── Freeze (inclui veículo) ───────────────────────────────────

local function freezePlayer(active)
    isFrozen = active
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, active)
    SetEntityInvincible(ped, active)

    -- Também freezar o veículo se estiver dentro
    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        FreezeEntityPosition(spawnedVehicle, active)
        if active then
            SetVehicleEngineOn(spawnedVehicle, false, true, true)
        else
            SetVehicleEngineOn(spawnedVehicle, true,  false, true)
            FreezeEntityPosition(spawnedVehicle, false)
        end
    end

    if active then
        Citizen.CreateThread(function()
            while isFrozen do
                local veh = spawnedVehicle

                -- Ped controls
                DisableControlAction(0, 30,  true)
                DisableControlAction(0, 31,  true)
                DisableControlAction(0, 21,  true)
                DisableControlAction(0, 22,  true)
                DisableControlAction(0, 24,  true)
                DisableControlAction(0, 25,  true)
                DisableControlAction(0, 263, true)

                -- Vehicle controls
                DisableControlAction(0, 71, true)   -- accelerate
                DisableControlAction(0, 72, true)   -- brake
                DisableControlAction(0, 59, true)   -- steer
                DisableControlAction(0, 63, true)   -- handbrake
                DisableControlAction(0, 75, true)   -- exit vehicle

                -- Forçar velocidade zero
                if veh and DoesEntityExist(veh) then
                    SetEntityVelocity(veh, 0.0, 0.0, 0.0)
                    FreezeEntityPosition(veh, true)
                end

                Citizen.Wait(0)
            end

            -- Libertar veículo ao descongelar
            if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
                FreezeEntityPosition(spawnedVehicle, false)
                SetVehicleEngineOn(spawnedVehicle, true, false, true)
            end
        end)
    end
end

-- ── Zona de jogo ─────────────────────────────────────────────

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

-- ── Caos na zona ──────────────────────────────────────────────

local function startChaosZone()
    -- 1. Densidade de tráfego aumentada
    Citizen.CreateThread(function()
        while roundActive do
            SetVehicleDensityMultiplierThisFrame(4.0)
            SetRandomVehicleDensityMultiplierThisFrame(4.0)
            SetParkedVehicleDensityMultiplierThisFrame(2.0)
            SetPedDensityMultiplierThisFrame(2.5)
            SetScenarioPedDensityMultiplierThisFrame(2.5, 2.5)
            Citizen.Wait(0)
        end
        -- Restaurar ao fim
        SetVehicleDensityMultiplierThisFrame(1.0)
        SetRandomVehicleDensityMultiplierThisFrame(1.0)
        SetParkedVehicleDensityMultiplierThisFrame(1.0)
        SetPedDensityMultiplierThisFrame(1.0)
    end)

    -- 2. Rampas aleatórias dentro da zona
    Citizen.CreateThread(function()
        local rampModels = {
            'prop_mp_ramp_02',
            'prop_mp_ramp_03',
            'prop_ramp_wooden_01',
            'prop_mp_ramp_06',
        }

        for _ = 1, 6 do
            local angle = math.random() * math.pi * 2
            local dist  = math.random(150, 700)
            local cx = zoneData and zoneData.x or Config.zone.x
            local cy = zoneData and zoneData.y or Config.zone.y
            local px  = cx + math.cos(angle) * dist
            local py  = cy + math.sin(angle) * dist
            local found, pz = GetGroundZFor_3dCoord(px, py, 300.0, false)
            if not found then pz = 30.0 end

            local model = rampModels[math.random(#rampModels)]
            local hash  = GetHashKey(model)
            RequestModel(hash)
            local t = 0
            while not HasModelLoaded(hash) and t < 30 do Citizen.Wait(100); t = t + 1 end

            if HasModelLoaded(hash) then
                local prop = CreateObject(hash, px, py, pz, true, false, false)
                SetEntityHeading(prop, math.random(0, 359))
                PlaceObjectOnGroundProperly(prop)
                FreezeEntityPosition(prop, true)
                chaosProps[#chaosProps + 1] = prop
                SetModelAsNoLongerNeeded(hash)
            end
            Citizen.Wait(600)
        end

        -- Aguardar fim da ronda e limpar
        while roundActive do Citizen.Wait(5000) end
        for _, p in ipairs(chaosProps) do
            if DoesEntityExist(p) then DeleteEntity(p) end
        end
        chaosProps = {}
    end)

    -- 3. Armadilhas: barris explosivos espalhados
    Citizen.CreateThread(function()
        local barrelHash = GetHashKey('prop_barrel_02a')
        RequestModel(barrelHash)
        while not HasModelLoaded(barrelHash) do Citizen.Wait(100) end

        for _ = 1, 5 do
            local angle = math.random() * math.pi * 2
            local dist  = math.random(100, 500)
            local cx = zoneData and zoneData.x or Config.zone.x
            local cy = zoneData and zoneData.y or Config.zone.y
            local px  = cx + math.cos(angle) * dist
            local py  = cy + math.sin(angle) * dist
            local found, pz = GetGroundZFor_3dCoord(px, py, 300.0, false)
            if not found then pz = 30.0 end

            local prop = CreateObject(barrelHash, px, py, pz + 0.5, true, false, false)
            PlaceObjectOnGroundProperly(prop)
            chaosProps[#chaosProps + 1] = prop
            Citizen.Wait(500)
        end
        SetModelAsNoLongerNeeded(barrelHash)
    end)

    -- 4. Peds hostis espalhados
    Citizen.CreateThread(function()
        local pedModels = {
            's_m_y_cop_01',
            'g_m_y_lost_01',
            'g_m_y_ballasout_01',
        }

        for _ = 1, 4 do
            local angle = math.random() * math.pi * 2
            local dist  = math.random(200, 600)
            local cx = zoneData and zoneData.x or Config.zone.x
            local cy = zoneData and zoneData.y or Config.zone.y
            local px  = cx + math.cos(angle) * dist
            local py  = cy + math.sin(angle) * dist
            local found, pz = GetGroundZFor_3dCoord(px, py, 300.0, false)
            if not found then pz = 30.0 end

            local model = pedModels[math.random(#pedModels)]
            local hash  = GetHashKey(model)
            RequestModel(hash)
            local t = 0
            while not HasModelLoaded(hash) and t < 30 do Citizen.Wait(100); t = t + 1 end

            if HasModelLoaded(hash) then
                local ped = CreatePed(4, hash, px, py, pz, math.random(0, 359), true, false)
                GiveWeaponToPed(ped, GetHashKey('WEAPON_PISTOL'), 150, false, true)
                SetPedFleeAttributes(ped, 0, false)
                SetPedCombatAttributes(ped, 46, true)
                SetPedCombatAbility(ped, 100)
                TaskShootAtCoord(ped, px + math.random(-10,10), py + math.random(-10,10), pz, 5000, GetHashKey('FIRING_PATTERN_FULL_AUTO'))
                SetModelAsNoLongerNeeded(hash)
                chaosPeds[#chaosPeds + 1] = ped
            end
            Citizen.Wait(800)
        end

        -- Aguardar fim e limpar
        while roundActive do Citizen.Wait(5000) end
        for _, p in ipairs(chaosPeds) do
            if DoesEntityExist(p) then DeleteEntity(p) end
        end
        chaosPeds = {}
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
                    notify(('⚠️ FORA DA ZONA! Volta em %ds ou serás eliminado!'):format(Config.outOfBoundsWarnSecs), 'error', 6000)

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
    -- Verificação cliente: deves estar fora do carro
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
    chaosProps      = {}
    chaosPeds       = {}

    removeAllWeapons()

    local ped = PlayerPedId()
    SetEntityCoords(ped, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false, true)
    SetEntityHeading(ped, spawnCoords.w)
    Citizen.Wait(1200)

    local veh = spawnVehicle(carModel, spawnCoords, role == 'cop')
    Citizen.Wait(500)
    warpIntoCar(veh)
    Citizen.Wait(400)
    giveWeaponNow(weapon, ammo)

    if role == 'cop' then
        notify('🚓 És POLÍCIA! Preso por ' .. lockSeconds .. 's. Depois usa G para algemar (fora do carro!).', 'error')
        freezePlayer(true)
        openNUI('cop', lockSeconds, Config.roundDuration)
    else
        local carQuality = math.random(100) > 50 and '🔝 Carro TOP!' or '💀 Sorte má — carro nas últimas...'
        notify('🔪 És LADRÃO! ' .. carQuality .. '  Polícias saem em ' .. lockSeconds .. 's!', 'warning')
        openNUI('robber', lockSeconds, Config.roundDuration)
    end

    startProximityCheck()
    startOOBCheck()

    -- Iniciar caos 5s após o início
    Citizen.CreateThread(function()
        Citizen.Wait(5000)
        if roundActive then
            startChaosZone()
            notify('🔥 ZONA DE CAOS ACTIVADA! Cuidado com as armadilhas!', 'warning', 5000)
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
    roundActive = false
    myRole      = nil
    isFrozen    = false

    freezePlayer(false)
    closeNUI()
    removeZone()
    removeAllWeapons()

    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        DeleteEntity(spawnedVehicle); spawnedVehicle = nil
    end

    notify('🔒 Foste APANHADO! Ronda terminada para ti.', 'error')
end)

AddEventHandler('policia:endRound', function(reason, winner)
    roundActive     = false
    myRole          = nil
    isFrozen        = false
    outOfBoundsWarn = false
    lastPositions   = {}

    freezePlayer(false)
    closeNUI()
    removeZone()

    for _, b in ipairs(tempBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    tempBlips = {}

    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        DeleteEntity(spawnedVehicle); spawnedVehicle = nil
    end

    removeAllWeapons()
    notify('🏁 RONDA TERMINADA: ' .. (reason or ''), 'primary')
end)

AddEventHandler('baseevents:onPlayerDied', function()
    if myRole == 'robber' and roundActive then
        TriggerServerEvent('policia:robberDied')
    end
end)
