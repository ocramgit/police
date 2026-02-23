local QBCore = exports['qb-core']:GetCoreObject()

-- ──────────────────────────────────────────────
--  Estado da ronda
-- ──────────────────────────────────────────────
local roundActive = false
local cops        = {}   -- { source = true, ... }
local robbers     = {}

-- ──────────────────────────────────────────────
--  Utilitários
-- ──────────────────────────────────────────────

-- Embaralha uma lista in-place (Fisher-Yates)
local function shuffle(tbl)
    for i = #tbl, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
    return tbl
end

-- Escolhe um elemento aleatório de uma lista
local function randomFrom(tbl)
    return tbl[math.random(#tbl)]
end

-- Notifica todos os jogadores via QBCore
local function notifyAll(msg, msgType)
    for _, player in pairs(QBCore.Functions.GetPlayers()) do
        TriggerClientEvent('QBCore:Notify', player, msg, msgType or 'primary', 8000)
    end
end

-- ──────────────────────────────────────────────
--  Lógica principal
-- ──────────────────────────────────────────────

local function startRound(numCops, lockSeconds)
    if roundActive then
        print('[POLICIA] Já existe uma ronda activa.')
        return
    end

    local players = QBCore.Functions.GetPlayers()
    local total   = #players

    if total < Config.minPlayers then
        print(('[POLICIA] Jogadores insuficientes. Online: %d | Mínimo: %d'):format(total, Config.minPlayers))
        return
    end

    -- Garante que numCops não excede total - 1 (precisa de pelo menos 1 ladrão)
    numCops = math.min(numCops, total - 1)
    numCops = math.max(numCops, 1)

    roundActive = true
    cops        = {}
    robbers     = {}

    -- Selecção aleatória
    local pool = {}
    for _, src in ipairs(players) do pool[#pool + 1] = src end
    shuffle(pool)

    for i, src in ipairs(pool) do
        if i <= numCops then
            cops[src] = true
        else
            robbers[src] = true
        end
    end

    print(('[POLICIA] Ronda iniciada | Polícias: %d | Ladrões: %d | Tempo de prisão: %ds'):format(
        numCops, total - numCops, lockSeconds))

    -- Anunciar início
    notifyAll('🚨 MINIJOGO POLICIA VS LADROES INICIADO! Verifica o teu papel...', 'warning')

    Citizen.Wait(2000)

    -- Atribuir papeis e fazer spawn
    for src, _ in pairs(cops) do
        local car = randomFrom(Config.policeCars)
        TriggerClientEvent('policia:assignRole', src, 'cop', car, lockSeconds,
            Config.copsSpawn.pos, Config.policeWeapon, Config.policeAmmo)
    end

    for src, _ in pairs(robbers) do
        local car = randomFrom(Config.robberCars)
        TriggerClientEvent('policia:assignRole', src, 'robber', car, 0,
            Config.robbersSpawn.pos, Config.robberWeapon, Config.robberAmmo)
    end

    -- ── Timer para libertar polícias ──────────────────
    Citizen.CreateThread(function()
        Citizen.Wait(lockSeconds * 1000)
        if not roundActive then return end

        for src, _ in pairs(cops) do
            TriggerClientEvent('policia:releasePolice', src)
        end
        notifyAll('🚓 As polícias foram libertadas! A caça começa agora!', 'error')
    end)

    -- ── Timer de pistas ───────────────────────────────
    Citizen.CreateThread(function()
        local elapsed = 0
        while roundActive and elapsed < Config.roundDuration do
            Citizen.Wait(Config.clueInterval * 1000)
            elapsed = elapsed + Config.clueInterval
            if not roundActive then break end

            sendClues()
        end
    end)

    -- ── Timer de fim de ronda ─────────────────────────
    Citizen.CreateThread(function()
        Citizen.Wait(Config.roundDuration * 1000)
        if roundActive then
            endRound('Tempo esgotado! Os ladrões escaparam!')
        end
    end)
end

-- ── Pistas de localização ────────────────────────────
function sendClues()
    if not roundActive then return end

    -- Recolher coords de todos os jogadores
    local positions = {}

    for src, _ in pairs(cops) do
        local player = QBCore.Functions.GetPlayer(src)
        if player then
            local ped    = GetPlayerPed(src)
            local coords = GetEntityCoords(ped)
            -- Adicionar imprecisão aleatória
            local ox = (math.random() * 2 - 1) * Config.clueRadius
            local oy = (math.random() * 2 - 1) * Config.clueRadius
            positions[#positions + 1] = {
                x    = coords.x + ox,
                y    = coords.y + oy,
                z    = coords.z,
                role = 'cop',
            }
        end
    end

    for src, _ in pairs(robbers) do
        local player = QBCore.Functions.GetPlayer(src)
        if player then
            local ped    = GetPlayerPed(src)
            local coords = GetEntityCoords(ped)
            local ox = (math.random() * 2 - 1) * Config.clueRadius
            local oy = (math.random() * 2 - 1) * Config.clueRadius
            positions[#positions + 1] = {
                x    = coords.x + ox,
                y    = coords.y + oy,
                z    = coords.z,
                role = 'robber',
            }
        end
    end

    -- Enviar para TODOS os jogadores
    for src, _ in pairs(cops)    do TriggerClientEvent('policia:sendClue', src, positions, Config.blipDuration) end
    for src, _ in pairs(robbers) do TriggerClientEvent('policia:sendClue', src, positions, Config.blipDuration) end

    notifyAll('📡 PISTA: Localizações aproximadas reveladas no mapa durante ' .. Config.blipDuration .. 's!', 'primary')
end

-- ── Fim de ronda ─────────────────────────────────────
function endRound(reason)
    if not roundActive then return end
    roundActive = false

    notifyAll('🏁 FIM DA RONDA: ' .. (reason or 'Ronda terminada!'), 'success')

    for src, _ in pairs(cops)    do TriggerClientEvent('policia:endRound', src, reason) end
    for src, _ in pairs(robbers) do TriggerClientEvent('policia:endRound', src, reason) end

    cops    = {}
    robbers = {}

    print('[POLICIA] Ronda terminada: ' .. (reason or ''))
end

-- ──────────────────────────────────────────────
--  Comando: comecarpolicia
-- ──────────────────────────────────────────────

-- Registo via consola do servidor (source == 0)
RegisterCommand('comecarpolicia', function(source, args, rawCommand)
    local isConsole = (source == 0)

    -- Verificar permissão in-game
    if not isConsole then
        local player = QBCore.Functions.GetPlayer(source)
        if not player then return end
        local group = player.PlayerData.permission
        local allowed = false
        for _, g in ipairs(Config.allowedGroups) do
            if g == group then allowed = true; break end
        end
        if not allowed then
            TriggerClientEvent('QBCore:Notify', source, 'Sem permissão para usar este comando.', 'error')
            return
        end
    end

    local numCops    = tonumber(args[1])
    local lockSecs   = tonumber(args[2])

    if not numCops or not lockSecs or numCops < 1 or lockSecs < 1 then
        local msg = 'Uso correcto: comecarpolicia <nPolicias> <segundos>'
        if isConsole then print('[POLICIA] ' .. msg)
        else TriggerClientEvent('QBCore:Notify', source, msg, 'error') end
        return
    end

    if roundActive then
        local msg = 'Já existe uma ronda activa. Aguarda o fim.'
        if isConsole then print('[POLICIA] ' .. msg)
        else TriggerClientEvent('QBCore:Notify', source, msg, 'error') end
        return
    end

    startRound(numCops, lockSecs)
end, false) -- false = não restringir a admins automaticamente (gerimos nós)

-- Comando para terminar manualmente (consola ou admin)
RegisterCommand('terminarpolicia', function(source, args, rawCommand)
    local isConsole = (source == 0)
    if not isConsole then
        local player = QBCore.Functions.GetPlayer(source)
        if not player then return end
        local group = player.PlayerData.permission
        local allowed = false
        for _, g in ipairs(Config.allowedGroups) do
            if g == group then allowed = true; break end
        end
        if not allowed then
            TriggerClientEvent('QBCore:Notify', source, 'Sem permissão.', 'error')
            return
        end
    end
    endRound('Ronda cancelada pelo administrador.')
end, false)
