Config = {}

-- ──────────────────────────────────────────────
--  TEMPORIZADORES
-- ──────────────────────────────────────────────
Config.clueInterval  = 30    -- segundos entre cada pista de localização
Config.roundDuration = 300   -- duração máxima da ronda em segundos (5 min)
Config.blipDuration  = 10    -- segundos que o blip temporário fica visível no mapa
Config.clueRadius    = 150.0 -- imprecisão das pistas em metros (raio aleatório)

-- ──────────────────────────────────────────────
--  SPAWNS
-- ──────────────────────────────────────────────
-- Polícias ficam presos neste local durante os segundos definidos
Config.copsSpawn = {
    pos    = vector4(428.34, -984.94, 29.69, 270.0), -- Mission Row PD
    label  = 'Esquadra Mission Row',
}

-- Ladrões nascem aqui e podem fugir imediatamente
Config.robbersSpawn = {
    pos   = vector4(-201.72, -1502.84, 31.08, 0.0), -- Terminal Portuário
    label = 'Terminal Portuário',
}

-- ──────────────────────────────────────────────
--  VEÍCULOS
-- ──────────────────────────────────────────────
Config.policeCars = {
    'police',   -- Vapid Stanier (Police)
    'police2',  -- Vapid Interceptor
    'police3',  -- Vapid Police Cruiser
}

Config.robberCars = {
    'blista',   -- Declasse Blista
    'issi2',    -- Weeny Issi Classic
    'prairie',  -- Declasse Prairie
    'rhapsody', -- Declasse Rhapsody
    'ingot',    -- Vulcar Ingot
}

-- ──────────────────────────────────────────────
--  ARMAS E MUNIÇÕES
-- ──────────────────────────────────────────────
Config.policeWeapon = 'WEAPON_PISTOL'
Config.policeAmmo   = 60

Config.robberWeapon = 'WEAPON_KNIFE'
Config.robberAmmo   = 1   -- faca não precisa de ammo mas é boa prática definir

-- ──────────────────────────────────────────────
--  PERMISSÕES DE COMANDO
-- ──────────────────────────────────────────────
-- Grupos que podem usar /comecarpolicia (além da consola do servidor)
Config.allowedGroups = { 'god', 'admin' }

-- ──────────────────────────────────────────────
--  MÍNIMO DE JOGADORES
-- ──────────────────────────────────────────────
Config.minPlayers = 2  -- precisa de pelo menos 2 jogadores para iniciar
