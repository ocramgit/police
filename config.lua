Config = {}

-- ── TEMPORIZADORES ─────────────────────────────────────────
Config.clueInterval        = 20
Config.roundDuration       = 900    -- 15 minutos
Config.blipDuration        = 18
Config.outOfBoundsWarnSecs = 15

-- ── ZONAS MÚLTIPLAS (sorteada aleatoriamente em cada ronda) ─
-- Cada zona tem nome, centro, raio e os seus próprios spawns
Config.zones = {
    {
        name   = '🏙️ Centro da Cidade',
        x      = 200.0, y = -900.0, z = 30.0, radius = 1350.0,
        copsSpawns = {
            vector4( 253.71, -580.18, 43.11, 164.0),
            vector4( 130.30, -635.82, 43.74,  90.0),
            vector4(  -8.00,-1086.36, 29.38, 332.0),
            vector4( 388.08, -616.23, 29.05, 358.0),
            vector4(-181.55, -771.36, 31.29,  90.0),
            vector4( 652.16,-1582.05, 29.29, 270.0),
            vector4(-268.64,-1356.74, 31.29, 178.0),
        },
        robbersSpawns = {
            vector4(-201.72,-1502.84, 31.08,   0.0),
            vector4( 495.57,-1286.04, 29.87, 270.0),
            vector4( 816.45,-1289.36, 25.82, 270.0),
            vector4(-673.30, -943.60, 21.83,  90.0),
            vector4(1135.95, -981.48, 46.42, 270.0),
            vector4(-200.00,-1650.00, 29.00,   0.0),
            vector4( 100.00,-1700.00, 29.00, 180.0),
            vector4(-600.00,-1000.00, 22.00,  90.0),
            vector4( 900.00,-1400.00, 25.00, 270.0),
            vector4(-800.00, -700.00, 27.00,   0.0),
        },
    },
    {
        name   = '✈️ Aeroporto',
        x      = -1050.0, y = -2900.0, z = 13.0, radius = 1150.0,
        copsSpawns = {
            vector4(-1034.55,-2729.12,  13.75,  90.0),
            vector4( -986.78,-2821.73,  13.75, 180.0),
            vector4(-1158.25,-2689.23,  13.75,  10.0),
            vector4( -750.00,-2830.00,  20.00, 270.0),
            vector4(-1250.00,-2950.00,  13.75,  90.0),
        },
        robbersSpawns = {
            vector4(-1239.90,-3015.07,  13.95, 270.0),
            vector4( -900.00,-3100.00,  13.75, 180.0),
            vector4(-1500.00,-2900.00,  13.75,  90.0),
            vector4(-1050.00,-3150.00,  13.75,   0.0),
            vector4( -800.00,-2700.00,  20.00, 270.0),
        },
    },
    {
        name   = '🏖️ Sandy Shores',
        x      = 1850.0, y = 3700.0, z = 33.0, radius = 1100.0,
        copsSpawns = {
            vector4(1853.94, 3685.84, 34.27, 210.0),
            vector4(1960.14, 3740.59, 32.35, 270.0),
            vector4(1700.00, 3600.00, 35.00,  90.0),
            vector4(2100.00, 3800.00, 32.00, 180.0),
            vector4(1750.00, 3900.00, 34.00,   0.0),
        },
        robbersSpawns = {
            vector4(1380.21, 3608.89, 38.01, 180.0),
            vector4(2400.00, 3700.00, 44.00, 270.0),
            vector4(1600.00, 4200.00, 38.00,  90.0),
            vector4(2000.00, 3500.00, 33.00,   0.0),
            vector4(1250.00, 3700.00, 40.00, 180.0),
        },
    },
    {
        name   = '⛰️ Paleto Bay',
        x      = -265.0, y = 6235.0, z = 31.0, radius = 1050.0,
        copsSpawns = {
            vector4(-265.54, 6230.20, 31.49, 225.0),
            vector4(-260.00, 6060.00, 43.00, 180.0),
            vector4( -50.00, 6300.00, 31.00, 270.0),
            vector4(-450.00, 6200.00, 31.00,  90.0),
            vector4(-180.00, 6380.00, 31.00,   0.0),
        },
        robbersSpawns = {
            vector4(-900.00, 5370.00, 34.00, 90.0),
            vector4(  80.00, 6410.00, 31.00,  0.0),
            vector4(-600.00, 6000.00, 35.00, 90.0),
            vector4( 200.00, 6160.00, 31.00,180.0),
            vector4(-450.00, 6550.00, 31.00,  0.0),
        },
    },
    {
        name   = '🏭 Zona Industrial (La Mesa)',
        x      = 800.0, y = -1900.0, z = 26.0, radius = 950.0,
        copsSpawns = {
            vector4( 873.62,-1891.00, 26.59, 270.0),
            vector4( 700.00,-1800.00, 28.00,  90.0),
            vector4( 950.00,-2000.00, 26.00, 180.0),
            vector4( 600.00,-1950.00, 27.00,   0.0),
            vector4(1000.00,-1700.00, 30.00, 270.0),
        },
        robbersSpawns = {
            vector4( 450.00,-1800.00, 28.00, 90.0),
            vector4(1050.00,-2100.00, 26.00,  0.0),
            vector4( 600.00,-2200.00, 26.00, 90.0),
            vector4( 350.00,-2000.00, 27.00,  0.0),
            vector4(1150.00,-1800.00, 29.00,180.0),
        },
    },
}

-- Polícia: Supercarros topo de gama (A pedido)
Config.policeCars = { 
    't20', 'zentorno', 'osiris', 'nero', 'italiRSX' 
}

-- Ladrão: Carros Desportivos que são muito bons, mas que a polícia alcança (Tier A)
Config.robberCars = { 
    'kuruma', 'sultanrs', 'jester', 'massacro', 'elegy' 
}

-- ── ARMAS ───────────────────────────────────────────────────
Config.policeWeapon  = 'weapon_pistol'
Config.policeAmmo    = 60
Config.robberWeapon  = 'weapon_knife'
Config.robberAmmo    = 0
Config.handcuffsItem = 'handcuffs'

-- ── MECÂNICAS ────────────────────────────────────────────────
Config.arrestRange = 3.5
Config.alertRange  = 80.0

-- ── HELICÓPTERO DE APOIO (polícia) ───────────────────────────
Config.heliSupport = {
    cooldown     = 90,    -- segundos antes de poder usar de novo
    duration     = 60,    -- segundos activos
    heliAlt      = 80,    -- altitude de spawn
    attackRange  = 120,   -- metros — distância para disparar
}

-- ── BORDAS DA ZONA ────────────────────────────────────────────
Config.zoneBounce = {
    bounceForce = 14.0,  -- intensidade do rebote no veículo
    damagePct   = 0.07,  -- % de HP que o ladrão perde a cada impacto (a cada 700ms)
    warnDist    = 80.0,  -- metros antes da borda para aviso HUD
}

-- ── SPIKE STRIPS ──────────────────────────────────────────────
Config.spikeStripsPerCop = 2  -- max spike strips por cop por ronda

-- ── ROADBLOCKS NPC ────────────────────────────────────────────
Config.roadblockCount = 25  -- quantas barricadas por ronda (cobre quase todas as estradas)

-- ── RAMPAS — apenas as melhores posições ─────────────────────
Config.rampPositions = {
    {182.22, -809.06, 31.18, 158.14, 'large'},   -- Centro (posicionada pelo user)

    {220.0,  -700.0,  32.0,  270.0, 'medium'},  -- Vinewood Blvd
    {400.0,  -950.0,  30.0,    0.0, 'large'},   -- Mission Row
    {-300.0, -950.0,  28.0,   90.0, 'large'},   -- Little Seoul
    {700.0, -1000.0,  26.0,  270.0, 'medium'},  -- Cypress Flats
    {-600.0, -800.0,  25.0,  270.0, 'large'},   -- Del Perro
    {200.0, -1500.0,  26.0,  270.0, 'medium'},  -- Terminal Sul
    {-100.0, -550.0,  40.0,    0.0, 'large'},   -- Rockford / Norte
}

-- ── GERAL ────────────────────────────────────────────────────
Config.allowedGroups = { 'god', 'admin' }
Config.minPlayers    = 2
