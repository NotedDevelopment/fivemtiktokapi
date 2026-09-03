Config = {}

-- =============================================================================
-- GROWTH MODE
-- =============================================================================
Config.GrowthMode = 'gifts'

-- =============================================================================
-- WAVE CAP
-- =============================================================================
Config.WaveCapEnabled = true
Config.MaxPedsPerWave = 8
Config.MaxTierPerWave = nil

-- =============================================================================
-- DEFENDER CONFIGURATION
-- =============================================================================
Config.DefenderRespawnEnabled = true
Config.DefenderRespawnDelay   = 20

Config.Defenders = {
    {
        coords   = vector4(1690.48, 3272.37, 41.16, 270.0),
        model    = 's_m_y_swat_01',
        weapon   = 'WEAPON_CARBINERIFLE',
        health   = 200,
        armor    = 50,
        accuracy = 60,
        label    = 'Guard Alpha',
    },
    {
        coords   = vector4(1690.48, 3278.50, 41.16, 270.0),
        model    = 's_m_y_swat_01',
        weapon   = 'WEAPON_COMBATMG',
        health   = 200,
        armor    = 50,
        accuracy = 60,
        label    = 'Guard Beta',
    },
    {
        coords   = vector4(1690.48, 3284.63, 41.16, 270.0),
        model    = 's_m_m_marine_01',
        weapon   = 'WEAPON_SNIPERRIFLE',
        health   = 250,
        armor    = 75,
        accuracy = 80,
        label    = 'Sniper',
    },
    {
        coords   = vec4(1698.49, 3289.31, 47.87, 232.27),
        model    = 's_m_m_marine_01',
        weapon   = 'WEAPON_SNIPERRIFLE',
        health   = 250,
        armor    = 75,
        accuracy = 80,
        label    = 'Sniper',
    },
    {
        coords   = vector4(1714.0, 3278.5, 41.16, 270.0),
        model    = 's_m_y_swat_01',
        weapon   = 'WEAPON_COMBATMG_MK2',
        health   = 250,
        armor    = 75,
        accuracy = 65,
        label    = 'Heavy',
    },
    {
        coords   = vector4(1692.0, 3262.0, 41.16, 10.0),
        model    = 's_m_m_marine_02',
        weapon   = 'WEAPON_ASSAULTRIFLE',
        health   = 200,
        armor    = 50,
        accuracy = 60,
        label    = 'Rifleman',
    },
    {
        coords   = vector4(1692.0, 3295.0, 41.16, 170.0),
        model    = 's_m_m_marine_02',
        weapon   = 'WEAPON_ASSAULTRIFLE',
        health   = 200,
        armor    = 50,
        accuracy = 60,
        label    = 'Rifleman',
    },
    {
        coords   = vec4(1703.0, 3272.0, 44.2, 250.0),
        model    = 's_m_m_marine_01',
        weapon   = 'WEAPON_HEAVYSNIPER',
        health   = 300,
        armor    = 100,
        accuracy = 85,
        label    = 'Marksman',
    },
}

-- =============================================================================
-- ARENA CENTER
-- =============================================================================
Config.ArenaCenter = vector3(1690.48, 3278.50, 41.16)

-- =============================================================================
-- VIEWER SPAWN ZONES
-- =============================================================================
Config.SpawnZoneSubRadius = 22.0

Config.SpawnZones = {
    {
        spawn    = vector3(1810.0, 3278.5, 41.16),
        scatter  = 5.0,
        approach = vector3(1730.0, 3278.5, 41.16),
        label    = 'East Gate',
    },
    {
        spawn    = vector3(1690.0, 3188.0, 41.16),
        scatter  = 5.0,
        approach = vector3(1690.0, 3245.0, 41.16),
        label    = 'North Road',
    },
    {
        spawn    = vector3(1690.0, 3368.0, 41.16),
        scatter  = 5.0,
        approach = vector3(1690.0, 3312.0, 41.16),
        label    = 'South Alley',
    },
    {
        spawn    = vector3(1768.0, 3212.0, 41.16),
        scatter  = 5.0,
        approach = vector3(1724.0, 3248.0, 41.16),
        label    = 'NE Rocks',
    },
    {
        spawn    = vector3(1768.0, 3344.0, 41.16),
        scatter  = 5.0,
        approach = vector3(1724.0, 3308.0, 41.16),
        label    = 'SE Corner',
    },
    {
        spawn    = vector3(1614.0, 3278.5, 41.16),
        scatter  = 5.0,
        approach = vector3(1654.0, 3278.5, 41.16),
        label    = 'West Flank',
    },
}

-- =============================================================================
-- WAVE TIERS
-- Each tier keeps the legacy `name`, `model`, `weapon` fields (used by
-- waves.lua summaries).  The `names`, `models`, `weapons` arrays are picked
-- randomly per-ped on spawn for variety.
-- =============================================================================
Config.Tiers = {
    [1] = {
        name    = 'Grunt',
        names   = { 'Grunt', 'Punk', 'Thug', 'Goon', 'Scrub' },
        model   = 'a_m_y_skater_01',
        models  = { 'a_m_y_skater_01', 'a_m_m_prolhost_01', 'g_m_y_mexthug_01', 'a_m_y_musclbeac_01', 'g_m_y_ballaeast_01' },
        weapon  = 'WEAPON_PISTOL',
        weapons = { 'WEAPON_PISTOL', 'WEAPON_SNS_PISTOL', 'WEAPON_PISTOL_MK2' },
        cost     = 50,
        health   = 50,
        armor    = 0,
        accuracy = 25,
    },
    [2] = {
        name    = 'Soldier',
        names   = { 'Soldier', 'Warrior', 'Fighter', 'Brawler', 'Enforcer' },
        model   = 'g_m_y_lost_01',
        models  = { 'g_m_y_lost_01', 'g_m_y_lost_02', 'g_m_y_salvaru_01', 'g_m_m_chicold_01', 'g_m_y_armgoon_01' },
        weapon  = 'WEAPON_SMG',
        weapons = { 'WEAPON_SMG', 'WEAPON_MICROSMG', 'WEAPON_SMG_MK2', 'WEAPON_ASSAULTSHOTGUN' },
        cost     = 150,
        health   = 100,
        armor    = 25,
        accuracy = 45,
    },
    [3] = {
        name    = 'Veteran',
        names   = { 'Veteran', 'Elite', 'Hardened', 'Assault', 'Gunner' },
        model   = 's_m_y_swat_01',
        models  = { 's_m_y_swat_01', 'g_m_y_azteca_01', 'csb_mweather', 'g_m_y_armgoon_01', 'g_m_m_chicold_01' },
        weapon  = 'WEAPON_ASSAULTRIFLE',
        weapons = { 'WEAPON_ASSAULTRIFLE', 'WEAPON_CARBINERIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_SPECIALCARBINE_MK2', 'WEAPON_BULLPUPRIFLE' },
        cost     = 400,
        health   = 175,
        armor    = 50,
        accuracy = 65,
    },
    [4] = {
        name    = 'Sniper',
        names   = { 'Sniper', 'Marksman', 'Sharpshooter', 'Scout' },
        model   = 's_m_m_marine_01',
        models  = { 's_m_m_marine_01', 's_m_m_marine_02', 's_m_y_ranger_01', 'csb_mp_agent14' },
        weapon  = 'WEAPON_SNIPERRIFLE',
        weapons = { 'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_MARKSMANRIFLE_MK2' },
        cost     = 1200,
        health   = 250,
        armor    = 100,
        accuracy = 90,
    },
}

-- =============================================================================
-- POINTS ECONOMY
-- =============================================================================
Config.Points = {
    perLike        = 2,
    perGift        = 100,
    perKill        = 30,
    perDamageDealt = 0.05,
}

-- =============================================================================
-- VIEWER COLORS
-- =============================================================================
Config.ViewerColors = {
    { 255, 80,  80  },
    { 80,  150, 255 },
    { 80,  255, 120 },
    { 255, 200, 50  },
    { 200, 80,  255 },
    { 255, 140, 50  },
    { 50,  230, 230 },
    { 255, 130, 180 },
}

-- =============================================================================
-- DEFENDER BEHAVIOR
-- =============================================================================
Config.DefenderReturnDist   = 3.5
Config.DefenderIdleChangeMs = { min = 14000, max = 40000 }
Config.DefenderWanderRadius = 5.0

-- =============================================================================
-- LABEL SETTINGS
-- =============================================================================
Config.LabelDrawDistance = 85.0
Config.LabelZOffset      = 1.15

-- =============================================================================
-- UI REFRESH
-- =============================================================================
Config.HealthBarRefreshMs = 500

-- =============================================================================
-- AUTO-BOT — spawns CPU waves when no players are sending attackers
-- =============================================================================
Config.AutoBotEnabled  = true
Config.AutoBotInterval = 45    -- seconds of inactivity before a bot wave spawns
Config.AutoBotTier     = 2     -- tier for the bot wave
Config.AutoBotCount    = 4     -- peds per bot wave
Config.AutoBotOwner    = 'CPU' -- display name

-- =============================================================================
-- BODY / BLOOD SETTINGS
-- =============================================================================
Config.DisableBlood         = false   -- true = no blood spurts on any spawned ped
Config.PedsDisappearOnDeath = true    -- true = bodies vanish after PedDeathFadeDelay ms
Config.PedDeathFadeDelay    = 3000    -- ms before dead body disappears (smoke poof first)

-- =============================================================================
-- TEST MODE
-- =============================================================================
Config.TestMode = true

-- =============================================================================
-- GAME MODE
-- 'arena'  — Attack & Defend (default)
-- 'convoy' — VIP escort convoy
-- =============================================================================
Config.GameMode = 'arena'

-- =============================================================================
-- CONVOY MODE
-- =============================================================================
Config.Convoy = {
    -- Route end point. All convoy vehicles drive here.
    End = { x = 338.0,  y = 3472.0, z = 35.0 },

    -- One entry per convoy vehicle, spawned in listed order.
    -- Edit x/y/z/w to place each car exactly where you want it at spawn.
    -- role: 'vip' (first one sets the route start) or 'escort'
    VehicleSpawns = {
        {
            role        = 'vip',
            label       = 'VIP Transport',
            model       = 'kuruma2',
            driverModel = 's_m_y_swat_01',
            color       = { 255, 215, 50 },
            x = 2776.98, y = 3465.21, z = 54.47, w = 329.4,
        },
        {
            role        = 'escort',
            label       = 'Escort 1',
            model       = 'police3',
            driverModel = 's_m_y_swat_01',
            color       = { 80, 160, 255 },
            x = 2782.07, y = 3456.60, z = 54.47, w = 329.4,
        },
        {
            role        = 'escort',
            label       = 'Escort 2',
            model       = 'police3',
            driverModel = 's_m_y_swat_01',
            color       = { 80, 160, 255 },
            x = 2787.16, y = 3447.99, z = 54.47, w = 329.4,
        },
    },

    -- Vehicles hostile NPC viewers will send
    AttackerVehicleModels = { 'sultan', 'oracle2', 'buffalo3', 'vigero' },

    -- How far ahead of the VIP to road-snap attacker spawns
    AttackerSpawnAhead = 70.0,

    -- Passive ↔ Aggressive transition
    AggroRadius     = 90.0,   -- metres: switch to aggressive if attacker within this
    PassiveCooldown = 12.0,   -- seconds with no nearby attacker before going passive

    -- Driving speeds (m/s)
    PassiveSpeed    = 14.0,
    AggressiveSpeed = 24.0,
}

-- =============================================================================
-- ARENA CAMERAS
-- Passed to the actioncam as venue cameras (aesthetic cinematic angles).
-- Coordinates are plain tables so they survive net-event serialisation.
-- proximity / proximityPos: if any active ped is within proximity units of
-- proximityPos the cam is eligible to be chosen during action.  Omit both to
-- use the camera only during downtime.
-- =============================================================================
Config.ArenaCameras = {
    -- Slow crane hovering over the defender line
    {
        camType    = 'crane',
        label      = 'Defender Crane',
        location   = { x = 1695.0, y = 3278.5, z = 41.16 },
        radius     = 40.0,
        height     = 22.0,
        amplitude  = 7.0,
        craneSpeed = 0.07,
        speed      = 3.0,
        fov        = 55.0,
        duration   = 22,
        proximity    = 80.0,
        proximityPos = { x = 1695.0, y = 3278.5, z = 41.16 },
    },
    -- Wide high spin surveying the whole battlefield
    {
        camType  = 'spin',
        label    = 'Battlefield Overview',
        location = { x = 1690.0, y = 3278.5, z = 41.16 },
        radius   = 130.0,
        height   = 58.0,
        speed    = 3.5,
        fov      = 68.0,
        duration = 28,
    },
    -- Static shot from the east looking back at defenders
    {
        camType  = 'static',
        label    = 'East Line',
        position = { x = 1772.0, y = 3278.5, z = 46.0 },
        target   = { x = 1690.0, y = 3278.5, z = 42.0 },
        fov      = 50.0,
        duration = 16,
        proximity    = 110.0,
        proximityPos = { x = 1740.0, y = 3278.5, z = 41.16 },
    },
    -- Pan along the east attack corridor
    {
        camType = 'pan',
        label   = 'East Approach Pan',
        pointA  = { x = 1812.0, y = 3262.0, z = 45.0 },
        pointB  = { x = 1812.0, y = 3295.0, z = 45.0 },
        target  = { x = 1690.0, y = 3278.5, z = 42.0 },
        speed   = 6.0,
        fov     = 58.0,
        duration = 20,
        proximity    = 130.0,
        proximityPos = { x = 1812.0, y = 3278.5, z = 41.16 },
    },
    -- Low static from behind the defenders looking east into the battlefield
    {
        camType  = 'static',
        label    = 'Backline',
        position = { x = 1648.0, y = 3278.5, z = 44.0 },
        target   = { x = 1760.0, y = 3278.5, z = 41.16 },
        fov      = 54.0,
        duration = 18,
    },
    -- Slow north–south pan along the defender positions
    {
        camType = 'pan',
        label   = 'Defender Line Pan',
        pointA  = { x = 1702.0, y = 3258.0, z = 48.0 },
        pointB  = { x = 1702.0, y = 3299.0, z = 48.0 },
        target  = { x = 1755.0, y = 3278.5, z = 41.16 },
        speed   = 5.5,
        fov     = 54.0,
        duration = 24,
        proximity    = 60.0,
        proximityPos = { x = 1695.0, y = 3278.5, z = 41.16 },
    },
    -- Tight low spin around the centre of the fight
    {
        camType  = 'spin',
        label    = 'Ground Level Spin',
        location = { x = 1728.0, y = 3278.5, z = 41.16 },
        radius   = 18.0,
        height   = 4.0,
        speed    = 6.0,
        fov      = 72.0,
        duration = 16,
        proximity    = 60.0,
        proximityPos = { x = 1728.0, y = 3278.5, z = 41.16 },
    },
}
