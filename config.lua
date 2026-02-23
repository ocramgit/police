Config = {}

-- ── TEMPORIZADORES ─────────────────────────────────────────
Config.clueInterval        = 20
Config.roundDuration       = 900    -- 15 minutos
Config.blipDuration        = 18
Config.outOfBoundsWarnSecs = 15

-- ── ZONA (centro = 200, -900 | raio = 1100m) ────────────────
Config.zone = { x = 200.0, y = -900.0, z = 30.0, radius = 1100.0 }

-- ── SPAWNS DOS POLÍCIAS (estradas abertas, dentro da zona) ───
-- Todos verificados: dist < 1100m de (200, -900)
Config.copsSpawns = {
    vector4( 253.71, -580.18, 43.11, 164.0),  -- Vinewood Blvd
    vector4( 130.30, -635.82, 43.74,  90.0),  -- Alta St
    vector4(  -8.00,-1086.36, 29.38, 332.0),  -- Olympic Fwy
    vector4( 388.08, -616.23, 29.05, 358.0),  -- Capital Blvd
    vector4(-181.55, -771.36, 31.29,  90.0),  -- Vespucci Blvd
    vector4( 652.16,-1582.05, 29.29, 270.0),  -- Route 1 Sul
    vector4(-268.64,-1356.74, 31.29, 178.0),  -- Elgin Ave Sul
}

-- ── SPAWNS DOS LADRÕES (dispersos, todos dentro de 1100m) ───
Config.robbersSpawns = {
    vector4(-201.72,-1502.84, 31.08,   0.0),  -- Terminal Portuário
    vector4( 495.57,-1286.04, 29.87, 270.0),  -- Rancho Ave
    vector4( 816.45,-1289.36, 25.82, 270.0),  -- Cypress Flats
    vector4(-673.30, -943.60, 21.83,  90.0),  -- Del Perro Fwy
    vector4(1135.95, -981.48, 46.42, 270.0),  -- Jamestown St
    vector4(-200.00,-1650.00, 29.00,   0.0),  -- Chamberlain Hills
    vector4( 100.00,-1700.00, 29.00, 180.0),  -- Terminal Norte
    vector4(-600.00,-1000.00, 22.00,  90.0),  -- Little Seoul
    vector4( 900.00,-1400.00, 25.00, 270.0),  -- La Mesa
    vector4(-800.00, -700.00, 27.00,   0.0),  -- Rockford Dr
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

-- ── RAMPAS (dentro da zona, Z conhecido, tamanhos variados) ─
-- formato: { x, y, z, heading, size }
-- size: 'small' | 'medium' | 'large'
Config.rampPositions = {
    -- ─ Especificada pelo utilizador (grande, centro) ────────
    {182.22, -809.06, 31.18, 158.14, 'large'},

    -- ─ Centro / Vinewood / Alta ─────────────────────────────
    {220.0,  -700.0,  32.0,  270.0, 'medium'},
    {100.0,  -850.0,  30.0,   45.0, 'small'},
    {300.0,  -780.0,  30.0,   90.0, 'small'},
    {150.0,  -950.0,  30.0,  180.0, 'medium'},
    {-50.0,  -750.0,  28.0,    0.0, 'large'},
    {350.0,  -680.0,  36.0,  135.0, 'small'},
    { 50.0,  -650.0,  40.0,  270.0, 'medium'},

    -- ─ Mission Row / Strawberry ──────────────────────────────
    {400.0,  -950.0,  30.0,    0.0, 'large'},
    {500.0, -1000.0,  28.0,   90.0, 'medium'},
    {300.0, -1100.0,  28.0,  225.0, 'small'},
    {200.0, -1050.0,  29.0,  315.0, 'large'},

    -- ─ Little Seoul / Chamberlain ────────────────────────────
    {-300.0, -950.0,  28.0,   90.0, 'large'},
    {-200.0,-1000.0,  29.0,  180.0, 'medium'},
    {-400.0, -800.0,  28.0,   45.0, 'small'},
    {-500.0, -900.0,  26.0,  270.0, 'large'},
    {-300.0,-1100.0,  28.0,    0.0, 'small'},

    -- ─ El Burro / Cypress Flats ──────────────────────────────
    {700.0, -1000.0,  26.0,  270.0, 'medium'},
    {800.0,  -900.0,  28.0,   90.0, 'large'},
    {600.0,  -800.0,  30.0,    0.0, 'small'},
    {900.0, -1100.0,  26.0,  180.0, 'medium'},
    {750.0, -1200.0,  25.0,  270.0, 'small'},

    -- ─ La Mesa Norte ────────────────────────────────────────
    {1000.0, -800.0,  30.0,   90.0, 'large'},
    {1050.0, -950.0,  28.0,  180.0, 'medium'},

    -- ─ Vespucci / Del Perro ─────────────────────────────────
    {-600.0, -800.0,  25.0,  270.0, 'large'},
    {-700.0, -700.0,  26.0,  135.0, 'small'},
    {-500.0, -700.0,  28.0,   90.0, 'medium'},
    {-800.0,-1000.0,  23.0,  315.0, 'large'},

    -- ─ Sul (Rancho / Terminal) ───────────────────────────────
    {400.0, -1400.0,  27.0,  270.0, 'medium'},
    {-100.0,-1300.0,  29.0,   90.0, 'large'},
    {600.0, -1300.0,  26.0,  180.0, 'small'},
    {200.0, -1500.0,  26.0,  270.0, 'medium'},
    {-300.0,-1400.0,  27.0,    0.0, 'small'},
    {500.0, -1550.0,  26.0,   90.0, 'large'},

    -- ─ Norte (Rockford / Vinewood Hills) ────────────────────
    {-100.0, -550.0,  40.0,    0.0, 'large'},
    { 300.0, -450.0,  42.0,  225.0, 'small'},
    {-300.0, -600.0,  36.0,  135.0, 'medium'},
    { 500.0, -500.0,  40.0,  270.0, 'large'},
}

-- ── GERAL ────────────────────────────────────────────────────
Config.allowedGroups = { 'god', 'admin' }
Config.minPlayers    = 2
