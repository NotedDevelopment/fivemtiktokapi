Config = {}

-- Bolingbroke Penitentiary inner yard centre
Config.ArenaCenter = vector3(1695, 3762, 37.5)

-- Six spawn zones spread around the yard perimeter
Config.SpawnZones = {
    { spawn = vector3(1648, 3778, 37.5), scatter = 5.0 },   -- West wall
    { spawn = vector3(1742, 3778, 37.5), scatter = 5.0 },   -- East wall
    { spawn = vector3(1648, 3745, 37.5), scatter = 5.0 },   -- SW corner
    { spawn = vector3(1742, 3745, 37.5), scatter = 5.0 },   -- SE corner
    { spawn = vector3(1695, 3800, 37.5), scatter = 4.0 },   -- North gate
    { spawn = vector3(1695, 3725, 37.5), scatter = 4.0 },   -- South road
}

-- How many TikTok likes must accumulate before one LikeNpc is spawned
Config.LikesPerPed = 5

-- NPC spawned from a like: one unarmed inmate
Config.LikeNpc = {
    models   = { 's_m_y_prisoner_01' },
    weapon   = nil,
    health   = 150,
    armor    = 0,
    accuracy = 30,
    tierName = 'Inmate',
    points   = 5,
}

-- Donation tiers keyed by coin range
Config.DonationTiers = {
    {
        minCoins = 1,
        maxCoins = 49,
        models   = { 's_m_y_prisoner_01', 's_m_y_prisoner_02' },
        weapon   = 'weapon_bat',
        health   = 200,
        armor    = 25,
        accuracy = 40,
        tierName = 'Brawler',
        points   = 15,
    },
    {
        minCoins = 50,
        maxCoins = 999999,
        models   = { 's_m_y_prisoner_02' },
        weapon   = 'weapon_pistol',
        health   = 250,
        armor    = 50,
        accuracy = 55,
        tierName = 'Armed',
        points   = 25,
    },
}

-- Weak "fodder" NPCs spawned periodically for players to fight
Config.FodderEnabled   = true
Config.FodderInterval  = 45          -- seconds between batches
Config.FodderBatchSize = 4
Config.MaxFodder       = 20          -- hard cap on simultaneous fodder NPCs
Config.FodderNpc = {
    models   = { 'a_m_y_skater_01', 'a_f_y_tourist_01', 'a_m_m_beach_01', 'a_m_y_beachvesp_01' },
    weapon   = nil,                  -- unarmed
    health   = 10,                   -- nearly dead on arrival
    armor    = 0,
    accuracy = 8,
    tierName = 'Fodder',
    points   = 1,
}

Config.MaxNpcsPerViewer    = 12
Config.MaxCrewUIPeds       = 4      -- max ped HP bars shown per crew card in the UI
Config.LeashRadius         = 60.0    -- metres from ArenaCenter before an NPC is yanked back
Config.HealthBarRefreshMs  = 500
Config.BehaviorTickMs      = 800   -- how often the NPC behavior loop ticks

-- Center zone: NPCs walk here when no enemies are alive, then emote
Config.CenterZoneRadius    = 9.0   -- metres from ArenaCenter to trigger emoting
Config.EmoteMinMs          = 15000 -- minimum emote duration (ms)
Config.EmoteMaxMs          = 35000 -- maximum emote duration (ms)

-- Emotes played at the center zone (GTA5 TaskStartScenarioInPlace scenarios)
Config.CenterEmotes = {
    'WORLD_HUMAN_CHEERING',        -- crowd cheer
    'WORLD_HUMAN_YOGA',            -- yoga poses
    'WORLD_HUMAN_PUSH_UPS',        -- push-ups on the ground
    'WORLD_HUMAN_DRINKING',        -- drinking
    'WORLD_HUMAN_AA_COFFEE',       -- sipping coffee
    'WORLD_HUMAN_BINOCULARS',      -- peering through binoculars
    'WORLD_HUMAN_MUSCLE_CURL',     -- bicep curls
    'WORLD_HUMAN_SEAT_LEDGE',      -- sitting on a ledge
    'WORLD_HUMAN_JOG_STANDING',    -- jogging in place
    'WORLD_HUMAN_SMOKING',         -- smoking a cigarette
    'WORLD_HUMAN_GUARD_STAND',     -- standing guard (ironic)
    'WORLD_HUMAN_PARTYING',        -- partying
}

Config.ViewerColors = {
    { 255, 80,  80  },   -- 1 red
    { 80,  150, 255 },   -- 2 blue
    { 80,  255, 120 },   -- 3 green
    { 255, 200, 50  },   -- 4 yellow
    { 200, 80,  255 },   -- 5 purple
    { 255, 140, 50  },   -- 6 orange
    { 50,  230, 230 },   -- 7 cyan
    { 255, 130, 180 },   -- 8 pink
}

-- Elimination toast message templates.
-- {victim} → "NpcName (TikTokUser)"   {killer} → same, or "nobody"
Config.EliminationMessages = {
    '{victim} got mogged on by {killer}',
    '{victim} dropped the soap near {killer}',
    '{victim} just got cooked by {killer}',
    '{victim} caught these hands from {killer}',
    '{victim} was speedrun by {killer}',
    '{victim} fell off. {killer} ate.',
    '{victim} couldn\'t handle {killer}',
    '{victim} got absolutely bodied by {killer}',
    '{victim} is no more — shoutout {killer}',
    '{victim} is cooked, courtesy of {killer}',
}

-- Attacker NPCs: hostile guards that spawn and fight viewer NPCs.
-- Spawn half as often as fodder (AttackerInterval ≈ FodderInterval * 2).
Config.AttackerEnabled   = true
Config.AttackerInterval  = 90          -- seconds between attacker batches
Config.AttackerBatchSize = 2
Config.MaxAttackers      = 10
Config.AttackerNpc = {
    models   = { 's_m_y_cop_01', 's_m_m_security_01', 's_m_y_sheriff_01' },
    weapon   = nil,
    health   = 10,
    armor    = 0,
    accuracy = 8,
    tierName = 'Guard',
    points   = 1,
}

Config.ActionCamEnabled  = true
Config.DeathSmokeEnabled = true   -- poof of colored smoke when an NPC dies
Config.ArenaCameras = {
    {
        camType     = 'spin',
        label       = 'Yard Overview',
        location    = { x = 1695, y = 3762, z = 37.5 },
        radius      = 42.0,
        height      = 22.0,
        speed       = 0.5,
        fov         = 62.0,
        duration    = 16,
        proximity   = 120.0,
        proximityPos = { x = 1695, y = 3762, z = 37.5 },
    },
    {
        camType     = 'crane',
        label       = 'Guard Tower',
        location    = { x = 1655, y = 3742, z = 37.5 },
        radius      = 22.0,
        height      = 28.0,
        amplitude   = 5.0,
        craneSpeed  = 0.06,
        speed       = 2.5,
        fov         = 52.0,
        duration    = 20,
        proximity   = 90.0,
        proximityPos = { x = 1695, y = 3762, z = 37.5 },
    },
}
