Config = {}

-- ── TEMPORIZADORES ─────────────────────────────────────────
Config.clueInterval        = 20     -- segundos entre pistas (coordenadas EXACTAS)
Config.roundDuration       = 300    -- duração máxima da ronda (segundos)
Config.blipDuration        = 18     -- segundos que o blip fica no mapa
Config.outOfBoundsWarnSecs = 15     -- tempo para voltar à zona antes de ser eliminado

-- ── ZONA DE JOGO ────────────────────────────────────────────
-- Circle visível no mapa. Ambos os spawns estão dentro desta zona.
Config.zone = {
    x      = 200.0,
    y      = -900.0,
    z      = 30.0,
    radius = 1100.0,  -- metros
}

-- ── SPAWNS ──────────────────────────────────────────────────
Config.copsSpawn = {
    pos   = vector4(428.34, -984.94, 29.69, 270.0),  -- Mission Row PD
    label = 'Esquadra Mission Row',
}
Config.robbersSpawn = {
    pos   = vector4(-201.72, -1502.84, 31.08, 0.0),  -- Terminal Portuário
    label = 'Terminal Portuário',
}

-- ── VEÍCULOS ────────────────────────────────────────────────
Config.policeCars = { 'police', 'police2', 'police3' }
Config.robberCars = { 'blista', 'issi2', 'prairie', 'rhapsody', 'ingot' }

-- ── ARMAS (nomes de item QBCore) ─────────────────────────────
Config.policeWeapon  = 'weapon_pistol'
Config.policeAmmo    = 60
Config.robberWeapon  = 'weapon_knife'
Config.robberAmmo    = 0
Config.handcuffsItem = 'handcuffs'

-- ── MECÂNICAS ────────────────────────────────────────────────
Config.arrestRange = 3.5    -- metros para poder algemar (tecla G)
Config.alertRange  = 80.0   -- metros para alerta de proximidade no HUD

-- ── PERMISSÕES ───────────────────────────────────────────────
Config.allowedGroups = { 'god', 'admin' }
Config.minPlayers    = 2
