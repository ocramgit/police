local QBCore = exports['qb-core']:GetCoreObject()

local roundActive   = false
local cops          = {}
local robbers       = {}
local livingRobbers = 0
local givenItems    = {}  -- { [src] = {{item,amount}, ...} }

-- ── Utilitários ──────────────────────────────────────────────

local function shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

local function randomFrom(tbl)
    return tbl[math.random(#tbl)]
end

local function notifyAll(msg, msgType)
    TriggerClientEvent('QBCore:Notify', -1, msg, msgType or 'primary', 8000)
end

-- ── Inventário QBCore ─────────────────────────────────────────

local function giveItem(src, itemName, amount, meta)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    Player.Functions.AddItem(itemName, amount, false, meta or {})
    if QBCore.Shared.Items and QBCore.Shared.Items[itemName] then
        TriggerClientEvent('qb-inventory:client:ItemBox', src, QBCore.Shared.Items[itemName], 'add')
    end
    if not givenItems[src] then givenItems[src] = {} end
    givenItems[src][#givenItems[src]+1] = {item = itemName, amount = amount}
end

local function cleanupItems(src)
    if not givenItems[src] then return end
    local Player = QBCore.Functions.GetPlayer(src)
    if Player then
        for _, v in ipairs(givenItems[src]) do
            Player.Functions.RemoveItem(v.item, v.amount)
        end
    end
    givenItems[src] = nil
end

-- ── Lógica principal ─────────────────────────────────────────

local function startRound(numCops, lockSeconds)
    if roundActive then return end

    local players = QBCore.Functions.GetPlayers()
    local total   = #players

    if total < Config.minPlayers then
        print(('[POLICIA] Jogadores insuficientes: %d/%d'):format(total, Config.minPlayers))
        return
    end

    numCops = math.min(math.max(numCops, 1), total - 1)

    roundActive   = true
    cops          = {}
    robbers       = {}
    givenItems    = {}
    livingRobbers = 0

    local pool = {}
    for _, src in ipairs(players) do pool[#pool+1] = src end
    shuffle(pool)

    for i, src in ipairs(pool) do
        if i <= numCops then cops[src] = true
        else robbers[src] = true; livingRobbers = livingRobbers + 1 end
    end

    print(('[POLICIA] Ronda | Pol:%d | Ladr:%d | Lock:%ds'):format(numCops, livingRobbers, lockSeconds))

    -- Enviar zona para todos
    TriggerClientEvent('policia:setupZone', -1, Config.zone.x, Config.zone.y, Config.zone.z, Config.zone.radius)
    notifyAll('🚨 MINIJOGO: POLICIA VS LADROES! Verifica o teu papel...', 'warning')

    Citizen.Wait(2000)

    -- Spawns únicos: embaralhar listas e distribuir
    local copSpawnPool    = {}
    local robberSpawnPool = {}
    for _, v in ipairs(Config.copsSpawns)    do copSpawnPool[#copSpawnPool+1]       = v end
    for _, v in ipairs(Config.robbersSpawns) do robberSpawnPool[#robberSpawnPool+1] = v end
    shuffle(copSpawnPool)
    shuffle(robberSpawnPool)

    local copIdx, robberIdx = 1, 1

    for src in pairs(cops) do
        local spawnPos = copSpawnPool[copIdx] or copSpawnPool[1]
        copIdx = copIdx + 1
        local car = randomFrom(Config.policeCars)
        TriggerClientEvent('policia:assignRole', src, 'cop', car, lockSeconds,
            spawnPos, Config.policeWeapon, Config.policeAmmo)
        Citizen.Wait(200)
        giveItem(src, Config.policeWeapon,  1, {ammo = Config.policeAmmo, quality = 100})
        giveItem(src, Config.handcuffsItem, 1, {})
    end

    for src in pairs(robbers) do
        local spawnPos = robberSpawnPool[robberIdx] or robberSpawnPool[1]
        robberIdx = robberIdx + 1
        local car = randomFrom(Config.robberCars)
        TriggerClientEvent('policia:assignRole', src, 'robber', car, lockSeconds,
            spawnPos, Config.robberWeapon, Config.robberAmmo)
        Citizen.Wait(200)
        giveItem(src, Config.robberWeapon, 1, {quality = 100})
    end

    -- Libertar polícias após lockSeconds
    Citizen.CreateThread(function()
        Citizen.Wait(lockSeconds * 1000)
        if not roundActive then return end
        for src in pairs(cops) do
            TriggerClientEvent('policia:releasePolice', src)
        end
        notifyAll('🚓 POLÍCIAS LIBERTADOS! A caça começa AGORA!', 'error')
    end)

    -- Pistas periódicas (coords exactas)
    Citizen.CreateThread(function()
        local elapsed = 0
        while roundActive and elapsed < Config.roundDuration do
            Citizen.Wait(Config.clueInterval * 1000)
            elapsed = elapsed + Config.clueInterval
            if roundActive then sendClues() end
        end
    end)

    -- Fim por tempo
    Citizen.CreateThread(function()
        Citizen.Wait(Config.roundDuration * 1000)
        if roundActive then
            endRound('⏱️ Tempo esgotado! Os ladrões escaparam!', 'robbers')
        end
    end)
end

-- ── Pistas — coordenadas EXACTAS ─────────────────────────────

function sendClues()
    if not roundActive then return end

    local positions = {}
    local alive = 0

    for src in pairs(cops) do
        local coords = GetEntityCoords(GetPlayerPed(src))
        positions[#positions+1] = { x = coords.x, y = coords.y, z = coords.z, role = 'cop', name = GetPlayerName(src) }
    end
    for src in pairs(robbers) do
        alive = alive + 1
        local coords = GetEntityCoords(GetPlayerPed(src))
        positions[#positions+1] = { x = coords.x, y = coords.y, z = coords.z, role = 'robber', name = GetPlayerName(src) }
    end

    for src in pairs(cops)    do TriggerClientEvent('policia:sendClue', src, positions, Config.blipDuration, alive) end
    for src in pairs(robbers) do TriggerClientEvent('policia:sendClue', src, positions, Config.blipDuration, alive) end

    notifyAll(('📡 PISTA: %d ladrão(ões) ainda activo(s)!'):format(alive), 'primary')
end

-- ── Fim de ronda ─────────────────────────────────────────────

function endRound(reason, winner)
    if not roundActive then return end
    roundActive = false

    local winMsg = winner == 'cops' and '🏆 POLÍCIAS VENCERAM!' or (winner == 'robbers' and '🏆 LADRÕES ESCAPARAM!' or '🏁 EMPATE!')
    notifyAll(winMsg .. '  ' .. (reason or ''), 'success')

    TriggerClientEvent('policia:endRound', -1, reason, winner)

    Citizen.CreateThread(function()
        Citizen.Wait(4000)
        for src in pairs(cops)    do cleanupItems(src) end
        for src in pairs(robbers) do cleanupItems(src) end
        cops    = {}
        robbers = {}
    end)

    print('[POLICIA] Ronda terminada: ' .. (reason or ''))
end

-- ── Evento: Tentar algemar (G) ────────────────────────────────

RegisterServerEvent('policia:tryArrest')
AddEventHandler('policia:tryArrest', function()
    local src = source
    if not roundActive or not cops[src] then return end

    -- Polícia deve estar fora do carro
    if IsPedInAnyVehicle(GetPlayerPed(src), false) then
        TriggerClientEvent('QBCore:Notify', src, '🚗 Sai do carro para poder algemar!', 'error', 3000)
        return
    end

    local copCoords = GetEntityCoords(GetPlayerPed(src))

    for robberSrc in pairs(robbers) do
        local robberCoords = GetEntityCoords(GetPlayerPed(robberSrc))
        local dist = #(copCoords - robberCoords)

        if dist <= Config.arrestRange then
            -- Ladrão também deve estar fora do carro
            if IsPedInAnyVehicle(GetPlayerPed(robberSrc), false) then
                TriggerClientEvent('QBCore:Notify', src, '🚗 O suspeito ainda está no carro!', 'error', 3000)
                return
            end

            local robberName = GetPlayerName(robberSrc)
            robbers[robberSrc] = nil
            livingRobbers = livingRobbers - 1

            TriggerClientEvent('policia:youWereArrested', robberSrc)
            notifyAll(('🔒 %s foi ALGEMADO por %s!'):format(robberName, GetPlayerName(src)), 'error')

            if livingRobbers <= 0 then
                endRound('Todos os ladrões foram apanhados!', 'cops')
            end
            return
        end
    end

    TriggerClientEvent('QBCore:Notify', src, '❌ Nenhum suspeito ao alcance!', 'error', 3000)
end)


-- ── Evento: Ladrão morreu ─────────────────────────────────────

RegisterServerEvent('policia:robberDied')
AddEventHandler('policia:robberDied', function()
    local src = source
    if not roundActive or not robbers[src] then return end

    robbers[src]  = nil
    livingRobbers = livingRobbers - 1

    notifyAll(('💀 %s foi eliminado! Restam %d ladrão(ões).'):format(GetPlayerName(src), livingRobbers), 'error')

    if livingRobbers <= 0 then
        endRound('Todos os ladrões foram eliminados!', 'cops')
    end
end)

-- ── Evento: Saiu da zona ──────────────────────────────────────

RegisterServerEvent('policia:outOfBounds')
AddEventHandler('policia:outOfBounds', function()
    local src = source
    if not roundActive then return end

    if robbers[src] then
        robbers[src]  = nil
        livingRobbers = livingRobbers - 1
        notifyAll(('🚫 %s SAIU DA ZONA e foi eliminado!'):format(GetPlayerName(src)), 'error')
        TriggerClientEvent('policia:youWereArrested', src)
        if livingRobbers <= 0 then
            endRound('Todos os ladrões foram eliminados!', 'cops')
        end
    elseif cops[src] then
        TriggerClientEvent('QBCore:Notify', src, '⚠️ Estás fora da zona! Volta rapidamente!', 'error', 5000)
    end
end)

-- ── Comandos ──────────────────────────────────────────────────

RegisterCommand('comecarpolicia', function(source, args)
    local numCops  = tonumber(args[1])
    local lockSecs = tonumber(args[2])

    if not numCops or not lockSecs or numCops < 1 or lockSecs < 1 then
        local msg = 'Uso: /comecarpolicia <nPolicias> <segundosLock>'
        if source == 0 then print('[POLICIA] ' .. msg)
        else TriggerClientEvent('QBCore:Notify', source, msg, 'error') end
        return
    end

    if roundActive then
        local msg = 'Já existe uma ronda activa.'
        if source == 0 then print('[POLICIA] ' .. msg)
        else TriggerClientEvent('QBCore:Notify', source, msg, 'error') end
        return
    end

    startRound(numCops, lockSecs)
end, false)

RegisterCommand('terminarpolicia', function()
    endRound('Ronda cancelada manualmente.', 'draw')
end, false)
