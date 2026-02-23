local QBCore    = exports['qb-core']:GetCoreObject()

-- Estado local do cliente
local myRole         = nil   -- 'cop' | 'robber'
local roundActive    = false
local spawnedVehicle = nil
local tempBlips      = {}
local nuiOpen        = false

-- ──────────────────────────────────────────────
--  Utilitários
-- ──────────────────────────────────────────────

local function notify(msg, msgType)
    QBCore.Functions.Notify(msg, msgType or 'primary', 7000)
end

-- Spawn de veículo junto ao jogador na posição dada
local function spawnVehicle(model, coords)
    local hash = GetHashKey(model)
    RequestModel(hash)
    while not HasModelLoaded(hash) do Citizen.Wait(100) end

    -- Destruir veículo anterior se ainda existir
    if spawnedVehicle and DoesEntityExist(spawnedVehicle) then
        DeleteEntity(spawnedVehicle)
    end

    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w, true, false)
    SetVehicleNumberPlateText(veh, 'JOGO-' .. math.random(1000, 9999))
    SetEntityInvincible(veh, false)
    SetVehicleDoorsLocked(veh, 1)

    spawnedVehicle = veh
    SetModelAsNoLongerNeeded(hash)
    return veh
end

-- Teleportar o ped para um veículo como condutor
local function warpIntoCar(veh)
    local ped = PlayerPedId()
    SetPedIntoVehicle(ped, veh, -1)   -- -1 = lugar do condutor
end

-- Dar arma ao jogador
local function giveWeapon(weapon, ammo)
    local ped = PlayerPedId()
    GiveWeaponToPed(ped, GetHashKey(weapon), ammo, false, true)
    SetCurrentPedWeapon(ped, GetHashKey(weapon), true)
end

-- Remover TODAS as armas do jogador
local function removeAllWeapons()
    RemoveAllPedWeapons(PlayerPedId(), true)
end

-- ──────────────────────────────────────────────
--  Gestão de handcuff (imobilizar polícias)
--  Usa freeze + bloqueio de controlos para não
--  depender de qb-policejob.
-- ──────────────────────────────────────────────

local freezeThread = nil

local function freezePlayer(active)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, active)
    SetEntityInvincible(ped, active)

    if active then
        -- Thread contínuo a bloquear inputs de movimento e combate
        freezeThread = Citizen.CreateThread(function()
            while myRole == 'cop' and roundActive do
                -- Movimento
                DisableControlAction(0, 30, true)  -- Move LR
                DisableControlAction(0, 31, true)  -- Move UD
                DisableControlAction(0, 21, true)  -- Sprint
                DisableControlAction(0, 22, true)  -- Jump
                DisableControlAction(0, 24, true)  -- Attack
                DisableControlAction(0, 25, true)  -- Aim
                DisableControlAction(0, 263, true) -- Melee Attack
                Citizen.Wait(0)
            end
        end)
    else
        -- Descongelar
        FreezeEntityPosition(ped, false)
        SetEntityInvincible(ped, false)
    end
end

-- ──────────────────────────────────────────────
--  Blips temporários
-- ──────────────────────────────────────────────

local function spawnTempBlips(positions, duration)
    -- Limpar blips antigos
    for _, b in ipairs(tempBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    tempBlips = {}

    for _, pos in ipairs(positions) do
        local blip = AddBlipForCoord(pos.x, pos.y, pos.z)

        if pos.role == 'cop' then
            SetBlipSprite(blip, 60)    -- ícone polícia
            SetBlipColour(blip, 3)     -- azul
            BeginTextCommandSetBlipName(blip)
            AddTextComponentString('Polícia (aprox.)')
            EndTextCommandSetBlipName(blip)
        else
            SetBlipSprite(blip, 84)    -- ícone correr
            SetBlipColour(blip, 1)     -- vermelho
            BeginTextCommandSetBlipName(blip)
            AddTextComponentString('Ladrão (aprox.)')
            EndTextCommandSetBlipName(blip)
        end

        SetBlipScale(blip, 0.9)
        SetBlipAsShortRange(blip, false)
        SetBlipFlashes(blip, true)

        tempBlips[#tempBlips + 1] = blip
    end

    -- Remover após 'duration' segundos
    Citizen.CreateThread(function()
        Citizen.Wait(duration * 1000)
        for _, b in ipairs(tempBlips) do
            if DoesBlipExist(b) then RemoveBlip(b) end
        end
        tempBlips = {}
    end)
end

-- ──────────────────────────────────────────────
--  NUI (HUD)
-- ──────────────────────────────────────────────

local function openNUI(role, lockSeconds, roundDuration)
    SetNuiFocus(false, false)  -- NUI visível mas sem bloquear controlos
    SendNUIMessage({
        action        = 'open',
        role          = role,
        lockSeconds   = lockSeconds,
        roundDuration = roundDuration,
    })
    nuiOpen = true
end

local function closeNUI()
    SendNUIMessage({ action = 'close' })
    nuiOpen = false
end

-- ──────────────────────────────────────────────
--  Eventos do servidor
-- ──────────────────────────────────────────────

-- Atribuição de papel e spawn inicial
AddEventHandler('policia:assignRole', function(role, carModel, lockSeconds, spawnCoords, weapon, ammo)
    myRole      = role
    roundActive = true

    removeAllWeapons()

    -- Teleportar para spawn
    local ped = PlayerPedId()
    SetEntityCoords(ped, spawnCoords.x, spawnCoords.y, spawnCoords.z, false, false, false, true)
    SetEntityHeading(ped, spawnCoords.w)

    Citizen.Wait(500)  -- aguardar que o mundo carregue

    -- Spawn veículo
    local veh = spawnVehicle(carModel, spawnCoords)
    Citizen.Wait(300)
    warpIntoCar(veh)

    -- Dar arma
    Citizen.Wait(200)
    giveWeapon(weapon, ammo)

    if role == 'cop' then
        notify('🚓 És POLÍCIA! Estás preso durante ' .. lockSeconds .. 's. Aguarda...', 'error')
        freezePlayer(true)
        openNUI('cop', lockSeconds, Config.roundDuration)
    else
        notify('🔪 És LADRÃO! Foge agora! As polícias são libertadas em ' .. lockSeconds .. 's!', 'warning')
        openNUI('robber', 0, Config.roundDuration)
    end
end)

-- Libertar as polícias
AddEventHandler('policia:releasePolice', function()
    if myRole ~= 'cop' then return end
    freezePlayer(false)
    notify('🚨 Foste libertado! VAI À CAÇA!', 'success')
    SendNUIMessage({ action = 'released' })
end)

-- Receber pistas de localização
AddEventHandler('policia:sendClue', function(positions, blipDuration)
    spawnTempBlips(positions, blipDuration)
end)

-- Fim da ronda
AddEventHandler('policia:endRound', function(reason)
    roundActive = false
    myRole      = nil

    freezePlayer(false)
    closeNUI()

    -- Limpar blips
    for _, b in ipairs(tempBlips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    tempBlips = {}

    -- Remover armas
    removeAllWeapons()

    notify('🏁 RONDA TERMINADA: ' .. (reason or ''), 'primary')
end)
