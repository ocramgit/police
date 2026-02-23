Config = {}

-- ── TEMPORIZADORES ─────────────────────────────────────────
Config.clueInterval        = 20     -- segundos entre pistas
Config.roundDuration       = 900    -- 15 minutos
Config.blipDuration        = 18
Config.outOfBoundsWarnSecs = 15

-- ── ZONA (apenas para o blip no mapa) ───────────────────────
Config.zone = { x = 200.0, y = -900.0, z = 30.0, radius = 1100.0 }

-- ── SPAWNS DOS POLÍCIAS (em estradas) ───────────────────────
Config.copsSpawns = {
    vector4( 253.71, -580.18,  43.11, 164.0),  -- Estrada Vinewood
    vector4( 130.30, -635.82,  43.74,  90.0),  -- Estrada Central
    vector4(  -8.00,-1086.36,  29.38, 332.0),  -- Perto do Porto
    vector4( 388.08, -616.23,  29.05, 358.0),  -- Mission Row road
    vector4(-181.55, -771.36,  31.29,  90.0),  -- Western LS
    vector4( 652.16,-1582.05,  29.29, 270.0),  -- Route 1 Sul
    vector4(-419.57,-1674.24,  19.77, 180.0),  -- Estrada Aeroporto
}

-- ── SPAWNS DOS LADRÕES (locais dispersos) ───────────────────
Config.robbersSpawns = {
    vector4(-201.72,-1502.84,  31.08,   0.0),  -- Terminal Portuário
    vector4(1698.15, 3579.98,  35.64, 313.0),  -- Sandy Shores
    vector4(-1041.88,-2748.67, 21.36, 260.0),  -- Terminal Sul
    vector4( 495.57,-1286.04,  29.87, 270.0),  -- Rancho
    vector4(-1185.53,-1566.86,  3.56, 270.0),  -- LSIA
    vector4( 816.45,-1289.36,  25.82, 270.0),  -- Cypress Flats
    vector4( -673.30,-943.60,  21.83,  90.0),  -- Del Perro
    vector4( 1134.95,-981.48,  46.42, 270.0),  -- Strawberry El
    vector4(-2429.15, 502.46,  131.2, 180.0),  -- Chiliad Mountain
    vector4( 2546.63, 380.73, 108.62,  90.0),  -- Vinewood Hills Este
}

-- ── VEÍCULOS ────────────────────────────────────────────────
Config.policeCars = { 'police', 'police2', 'police3' }
Config.robberCars = { 'blista', 'issi2', 'prairie', 'rhapsody', 'ingot' }

-- ── ARMAS ───────────────────────────────────────────────────
Config.policeWeapon  = 'weapon_pistol'
Config.policeAmmo    = 60
Config.robberWeapon  = 'weapon_knife'
Config.robberAmmo    = 0
Config.handcuffsItem = 'handcuffs'

-- ── MECÂNICAS ────────────────────────────────────────────────
Config.arrestRange = 3.5
Config.alertRange  = 80.0

-- ── GERAL ────────────────────────────────────────────────────
Config.allowedGroups = { 'god', 'admin' }
Config.minPlayers    = 2
