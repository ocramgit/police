local QBCore = exports['qb-core']:GetCoreObject()

local roundActive   = false
local cops          = {}
local robbers       = {}
local livingRobbers = 0
local givenItems    = {}  -- { [src] = {{item,amount}, ...} }
local heliCooldowns = {}  -- { [src] = timestamp }
local activeZone    = nil -- zona sorteada desta ronda
local heliCopSrc    = nil -- source ID do cop no helicóptero

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

-- ── Kill Feed ─────────────────────────────────────────────────

local function broadcastKillFeed(feedType, actor, victim)
    for src in pairs(cops)    do TriggerClientEvent('policia:killFeed', src, feedType, actor, victim) end
    for src in pairs(robbers) do TriggerClientEvent('policia:killFeed', src, feedType, actor, victim) end
end

-- ── Lógica principal ─────────────────────────────────────────

local function startRound(numCops, lockSeconds, waveMode)
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
    heliCooldowns = {}
    livingRobbers = 0
    heliCopSrc    = nil

    -- Sortear zona aleatória
    activeZone = Config.zones[math.random(#Config.zones)]
    print(('[POLICIA] Zona sorteada: %s'):format(activeZone.name))

    local pool = {}
    for _, src in ipairs(players) do pool[#pool+1] = src end
    shuffle(pool)

    for i, src in ipairs(pool) do
        if i <= numCops then cops[src] = true
        else robbers[src] = true; livingRobbers = livingRobbers + 1 end
    end

    -- Se há 2+ cops, um deles vai OBRIGATORIAMENTE para o helicóptero
    if numCops >= 2 then
        for src in pairs(cops) do
            heliCopSrc = src
            break  -- primeiro cop da lista vai para o heli
        end
    end

    print(('[POLICIA] Ronda | Pol:%d | Ladr:%d | Lock:%ds | Ondas:%s | HeliCop:%s'):format(
        numCops, livingRobbers, lockSeconds, waveMode and 'ON' or 'OFF',
        heliCopSrc and tostring(heliCopSrc) or 'NENHUM'))

    -- Enviar zona para todos
    TriggerClientEvent('policia:setupZone', -1,
        activeZone.x, activeZone.y, activeZone.z, activeZone.radius, activeZone.name)
    notifyAll('🚨 MINIJOGO: POLICIA VS LADROES! 📍 ' .. activeZone.name, 'warning')

    Citizen.Wait(2000)

    -- Spawns únicos da zona sorteada
    local copSpawnPool    = {}
    local robberSpawnPool = {}
    for _, v in ipairs(activeZone.copsSpawns)    do copSpawnPool[#copSpawnPool+1]       = v end
    for _, v in ipairs(activeZone.robbersSpawns) do robberSpawnPool[#robberSpawnPool+1] = v end
    shuffle(copSpawnPool)
    shuffle(robberSpawnPool)

    local copIdx, robberIdx = 1, 1

    for src in pairs(cops) do
        local spawnPos = copSpawnPool[copIdx] or copSpawnPool[1]
        copIdx = copIdx + 1
        
        local isHeliCop = (src == heliCopSrc)
        local car = isHeliCop and Config.heliCopModel or randomFrom(Config.policeCars)
        
        TriggerClientEvent('policia:assignRole', src, 'cop', car, lockSeconds,
            spawnPos, Config.policeWeapon, Config.policeAmmo, waveMode,
            Config.roadblockCount, isHeliCop)
        Citizen.Wait(200)
        
        if not isHeliCop then
            giveItem(src, Config.policeWeapon,  1, {ammo = Config.policeAmmo, quality = 100})
            giveItem(src, Config.handcuffsItem, 1, {})
        end
    end

    for src in pairs(robbers) do
        local spawnPos = robberSpawnPool[robberIdx] or robberSpawnPool[1]
        robberIdx = robberIdx + 1
        local car = randomFrom(Config.robberCars)
        TriggerClientEvent('policia:assignRole', src, 'robber', car, lockSeconds,
            spawnPos, Config.robberWeapon, Config.robberAmmo, waveMode,
            Config.roadblockCount, false)
        Citizen.Wait(200)
        giveItem(src, Config.robberWeapon, 1, {quality = 100})
    end

    -- Sincronizar listas para os clientes (Útil para a Turret reconhecer o Ladrão)
    TriggerClientEvent('policia:syncRoles', -1, cops, robbers)

    -- Libertar polícias após lockSeconds
    Citizen.CreateThread(function()
        Citizen.Wait(lockSeconds * 1000)
        if not roundActive then return end
        for src in pairs(cops) do
            TriggerClientEvent('policia:releasePolice', src)
        end
        notifyAll('🚓 POLÍCIAS LIBERTADOS! A caça começa AGORA!', 'error')
    end)

    -- X-RAY para o cop no helicóptero — posição dos ladrões em tempo real (1s)
    if heliCopSrc then
        Citizen.CreateThread(function()
            while roundActive and heliCopSrc do
                local positions = {}
                for robberSrc in pairs(robbers) do
                    local rPed = GetPlayerPed(robberSrc)
                    if DoesEntityExist(rPed) then
                        local coords = GetEntityCoords(rPed)
                        positions[#positions+1] = {
                            x = coords.x, y = coords.y, z = coords.z,
                            name = GetPlayerName(robberSrc)
                        }
                    end
                end
                TriggerClientEvent('policia:xrayUpdate', heliCopSrc, positions)
                Citizen.Wait(1000)
            end
        end)
    end

    -- Pistas periódicas (coords exactas)
    Citizen.CreateThread(function()
        local elapsed = 0
        while roundActive and elapsed < Config.roundDuration do
            Citizen.Wait(Config.clueInterval * 1000)
            elapsed = elapsed + Config.clueInterval
            if roundActive then sendClues() end
        end
    end)

    -- Fim por tempo (loop por segundo — evita problemas com Citizen.Wait longo)
    Citizen.CreateThread(function()
        local elapsed = 0
        while roundActive and elapsed < Config.roundDuration do
            Citizen.Wait(1000)
            elapsed = elapsed + 1
        end
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
    heliCopSrc  = nil

    local winMsg = winner == 'cops' and '🏆 POLÍCIAS VENCERAM!' or (winner == 'robbers' and '🏆 LADRÕES ESCAPARAM!' or '🏁 EMPATE!')
    notifyAll(winMsg .. '  ' .. (reason or ''), 'success')

    TriggerClientEvent('policia:endRound', -1, reason, winner)

    Citizen.CreateThread(function()
        Citizen.Wait(4000)
        for src in pairs(cops)    do cleanupItems(src) end
        for src in pairs(robbers) do cleanupItems(src) end
        cops    = {}
        robbers = {}
        activeZone = nil
    end)

    print('[POLICIA] Ronda terminada: ' .. (reason or ''))
end

-- ── Evento: Tentar algemar (G) ────────────────────────────────

RegisterServerEvent('policia:tryArrestClientDistance')
AddEventHandler('policia:tryArrestClientDistance', function(targetSrc, reportedDistance)
    local src = source
    if not roundActive or not cops[src] then return end

    if not robbers[targetSrc] then 
        TriggerClientEvent('QBCore:Notify', src, '❌ Isso não é um ladrão!', 'error', 3000)
        return
    end

    local copPed = GetPlayerPed(src)
    local robberPed = GetPlayerPed(targetSrc)
    
    local inCar = IsPedInAnyVehicle(robberPed, false)
    local allowedRange = inCar and 7.0 or 4.0

    if reportedDistance <= allowedRange then
        local robberName = GetPlayerName(targetSrc)
        local copName    = GetPlayerName(src)

        if inCar then
            TriggerClientEvent('policia:forceLeaveVehicle', targetSrc)
            TriggerClientEvent('QBCore:Notify', src, '🚗 A tirar o suspeito do carro...', 'warning', 3000)
            Citizen.CreateThread(function()
                Citizen.Wait(2500)
                if not roundActive or not robbers[targetSrc] then return end
                robbers[targetSrc] = nil
                livingRobbers = livingRobbers - 1
                TriggerClientEvent('policia:youWereArrested', targetSrc)
                notifyAll(('🔒 %s foi ARRASTADO E ALGEMADO por %s!'):format(robberName, copName), 'error')
                broadcastKillFeed('arrest', copName, robberName)
                if livingRobbers <= 0 then endRound('Todos os ladrões foram apanhados!', 'cops') end
            end)
        else
            robbers[targetSrc] = nil
            livingRobbers = livingRobbers - 1
            TriggerClientEvent('policia:youWereArrested', targetSrc)
            notifyAll(('🔒 %s foi ALGEMADO por %s!'):format(robberName, copName), 'error')
            broadcastKillFeed('arrest', copName, robberName)
            if livingRobbers <= 0 then endRound('Todos os ladrões foram apanhados!', 'cops') end
        end
    else
        TriggerClientEvent('QBCore:Notify', src, '❌ O ladrão está demasiado longe!', 'error', 3000)
    end
end)

-- ── Evento: Ladrão morreu ─────────────────────────────────────

RegisterServerEvent('policia:robberDied')
AddEventHandler('policia:robberDied', function()
    local src = source
    if not roundActive or not robbers[src] then return end

    local victimName = GetPlayerName(src)
    robbers[src]  = nil
    livingRobbers = livingRobbers - 1

    notifyAll(('💀 %s foi eliminado! Restam %d ladrão(ões).'):format(victimName, livingRobbers), 'error')
    broadcastKillFeed('kill', 'NPC', victimName)

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
        local victimName = GetPlayerName(src)
        robbers[src]  = nil
        livingRobbers = livingRobbers - 1
        notifyAll(('🚫 %s SAIU DA ZONA e foi eliminado!'):format(victimName), 'error')
        TriggerClientEvent('policia:youWereArrested', src)
        broadcastKillFeed('oob', '', victimName)
        if livingRobbers <= 0 then
            endRound('Todos os ladrões foram eliminados!', 'cops')
        end
    elseif cops[src] then
        TriggerClientEvent('QBCore:Notify', src, '⚠️ Estás fora da zona! Volta rapidamente!', 'error', 5000)
    end
end)

-- ── Evento: Pedir helicóptero de apoio ───────────────────────

RegisterServerEvent('policia:requestHeli')
AddEventHandler('policia:requestHeli', function()
    local src = source
    if not roundActive or not cops[src] then return end

    local now = os.time()
    if heliCooldowns[src] and (now - heliCooldowns[src]) < Config.heliSupport.cooldown then
        local remaining = Config.heliSupport.cooldown - (now - heliCooldowns[src])
        TriggerClientEvent('QBCore:Notify', src,
            ('🚁 Helicóptero em cooldown! Disponível em %ds.'):format(remaining), 'error', 4000)
        return
    end

    heliCooldowns[src] = now

    -- Encontrar posição do ladrão mais próximo para enviar ao cop
    local copCoords   = GetEntityCoords(GetPlayerPed(src))
    local best, bestD = nil, 999999
    for robberSrc in pairs(robbers) do
        local rc = GetEntityCoords(GetPlayerPed(robberSrc))
        local d  = #(copCoords - rc)
        if d < bestD then best = rc; bestD = d end
    end

    TriggerClientEvent('policia:spawnHeli', src,
        best and {x=best.x, y=best.y, z=best.z} or nil,
        Config.heliSupport.duration,
        Config.heliSupport.heliAlt)

    TriggerClientEvent('QBCore:Notify', src, '🚁 Helicóptero de apoio a caminho!', 'success', 4000)
    notifyAll('🚁 [POLÍCIA] Pediu apoio aéreo!', 'warning')
end)

-- ── Evento: Radar Pulse (cop J) — envia posições a esse cop ──

RegisterServerEvent('policia:requestRadarPulse')
AddEventHandler('policia:requestRadarPulse', function()
    local src = source
    if not roundActive or not cops[src] then return end

    local positions = {}
    for robberSrc in pairs(robbers) do
        local rPed = GetPlayerPed(robberSrc)
        if DoesEntityExist(rPed) then
            local coords = GetEntityCoords(rPed)
            positions[#positions+1] = { x = coords.x, y = coords.y, z = coords.z }
        end
    end
    TriggerClientEvent('policia:radarPulseResult', src, positions)
end)

-- ── Evento: Iniciar ronda da UI ───────────────────────────────

RegisterServerEvent('policia:startFromUI')
AddEventHandler('policia:startFromUI', function(numCops, lockSecs, waveMode)
    local src = source
    if roundActive then
        TriggerClientEvent('QBCore:Notify', src, 'Já existe uma ronda activa.', 'error')
        return
    end
    numCops  = tonumber(numCops)  or 1
    lockSecs = tonumber(lockSecs) or 30
    if type(waveMode) ~= 'boolean' then waveMode = true end
    startRound(numCops, lockSecs, waveMode)
end)

-- ── Comandos ──────────────────────────────────────────────────

-- /comecarpolicia — abre a UI de configuração no cliente
RegisterCommand('comecarpolicia', function(source, args)
    local src = source
    if src == 0 then
        -- Console: modo direto
        local numCops  = tonumber(args[1]) or 1
        local lockSecs = tonumber(args[2]) or 30
        startRound(numCops, lockSecs, true)
        return
    end
    if roundActive then
        TriggerClientEvent('QBCore:Notify', src, 'Já existe uma ronda activa.', 'error')
        return
    end
    TriggerClientEvent('policia:openAdminUI', src)
end, false)

RegisterCommand('terminarpolicia', function()
    endRound('Ronda cancelada manualmente.', 'draw')
end, false)

RegisterServerEvent('policia:startServerDrone')
AddEventHandler('policia:startServerDrone', function()
    local src = source
    if not roundActive or not cops[src] then return end

    Citizen.CreateThread(function()
        local elapsed = 0
        while roundActive and elapsed < 30 do
            local positions = {}
            for robberSrc in pairs(robbers) do
                local rPed = GetPlayerPed(robberSrc)
                if DoesEntityExist(rPed) then
                    local coords = GetEntityCoords(rPed)
                    positions[#positions+1] = { x = coords.x, y = coords.y, z = coords.z }
                end
            end
            
            TriggerClientEvent('policia:updateDroneBlips', src, positions)
            Citizen.Wait(1000)
            elapsed = elapsed + 1
        end
        TriggerClientEvent('policia:stopDroneBlips', src)
    end)
end)

RegisterServerEvent('policia:triggerEMP')
AddEventHandler('policia:triggerEMP', function(targetId)
    local src = source
    if not cops[src] then return end
    
    if robbers[targetId] then
        TriggerClientEvent('policia:receiveEMP', targetId)
    end
end)
