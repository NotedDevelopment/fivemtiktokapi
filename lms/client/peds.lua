-- =============================================================================
-- LMS Ped Management
-- Handles spawning, relationship groups, health tracking, kill attribution,
-- NPC name assignment, center-zone emotes, and anti-scatter behavior.
-- =============================================================================

ActiveNpcs        = {}
ActiveFodder      = {}
ActiveAttackers   = {}
viewerDisplayNames = {}   -- [owner] = last known NPC charName, read by client.lua

-- ---------------------------------------------------------------------------
-- Funny NPC names (gender-matched)
-- ---------------------------------------------------------------------------
local MALE_NAMES = {
    'Putin',        'Netanyahu',  'Epstein',      'Biden',       'Trump',
    'Boris',        'Kim Jong',   'Stalin',        'Macron',      'Zelensky',
    'Berlusconi',   'Elon Musk',  'Bezos',         'Zuckerborg',  'Assange',
    'Lukashenko',   'Erdogan',    'Farage',         'Bolsonaro',   'El Chapo',
    'Pinochet',     'Gaddafi',    'Saddam',         'Al Capone',   'Madoff',
    'Harvey W',     'Shrek',      'Thanos',         'Mussolini',   'Obama',
    'Scheming Rat', 'Big Tony',   'Uncle Vladimir', 'The Don',     'Jeff B',
}

local FEMALE_NAMES = {
    'Hillary',       'Pelosi',        'Thatcher',   'Merkel',
    'Melania',       'Ivanka',        'Kamala',     'AOC',
    'Oprah',         'Madonna',       'Kim K',      'Meghan',
    'Cruella',       'Monica',        'Marilyn',    'Liz Truss',
    'Whoopi',        'Cardi B',       'Lizzo',      'Ellen',
    'Karen',         'Big Shirley',   'Agent Nancy', 'Lady Hillary',
}

local usedNames = {}

local function isFemale(model)
    -- Female GTA5 ped models contain _f_ in the string (a_f_, s_f_, u_f_, etc.)
    return model:lower():find('_f_') ~= nil
end

local function pickName(model)
    local pool = isFemale(model) and FEMALE_NAMES or MALE_NAMES
    local available = {}
    for _, n in ipairs(pool) do
        if not usedNames[n] then available[#available + 1] = n end
    end
    if #available == 0 then
        usedNames  = {}
        available  = pool
    end
    local name = available[math.random(#available)]
    usedNames[name] = true
    return name
end

-- ---------------------------------------------------------------------------
-- Relationship groups
-- ---------------------------------------------------------------------------
local FODDER_GROUP   = GetHashKey('LMS_FODDER')
AddRelationshipGroup('LMS_FODDER')

local ATTACKER_GROUP = GetHashKey('LMS_ATTACKER')
AddRelationshipGroup('LMS_ATTACKER')

local viewerGroups = {}

local function sanitize(name)
    return name:upper():gsub('[^A-Z0-9]', '_')
end

local function getOrCreateViewerGroup(username)
    if viewerGroups[username] then return viewerGroups[username] end

    local groupName = 'LMS_V_' .. sanitize(username)
    AddRelationshipGroup(groupName)
    local hash = GetHashKey(groupName)
    viewerGroups[username] = hash

    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())

    -- Viewer NPCs ignore player (player fights fodder only)
    SetRelationshipBetweenGroups(0, hash, playerGroup)
    SetRelationshipBetweenGroups(0, playerGroup, hash)

    -- Viewer NPCs fight fodder
    SetRelationshipBetweenGroups(5, hash, FODDER_GROUP)
    SetRelationshipBetweenGroups(5, FODDER_GROUP, hash)

    -- Viewer NPCs fight attackers
    SetRelationshipBetweenGroups(5, hash, ATTACKER_GROUP)
    SetRelationshipBetweenGroups(5, ATTACKER_GROUP, hash)

    -- Fight every other viewer crew
    for otherUser, otherHash in pairs(viewerGroups) do
        if otherUser ~= username then
            SetRelationshipBetweenGroups(5, hash, otherHash)
            SetRelationshipBetweenGroups(5, otherHash, hash)
        end
    end

    return hash
end

-- Set up global static relationships on resource start
CreateThread(function()
    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())
    -- Player ↔ fodder (player can fight fodder and vice-versa)
    SetRelationshipBetweenGroups(5, FODDER_GROUP,   playerGroup)
    SetRelationshipBetweenGroups(5, playerGroup,    FODDER_GROUP)
    -- Attackers ↔ fodder
    SetRelationshipBetweenGroups(5, ATTACKER_GROUP, FODDER_GROUP)
    SetRelationshipBetweenGroups(5, FODDER_GROUP,   ATTACKER_GROUP)
    -- Player ↔ attackers
    SetRelationshipBetweenGroups(5, ATTACKER_GROUP, playerGroup)
    SetRelationshipBetweenGroups(5, playerGroup,    ATTACKER_GROUP)
end)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function loadModel(hash)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    local ticks = 0
    while not HasModelLoaded(hash) do
        Wait(50); ticks = ticks + 1
        if ticks > 60 then return false end
    end
    return true
end

local function spawnPed(model, x, y, z, heading)
    local hash = GetHashKey(model)
    if not loadModel(hash) then print('[LMS] Failed model: ' .. model); return nil end
    local ped = CreatePed(4, hash, x, y, z, heading, false, true)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return nil end
    return ped
end

local function setupCombatAI(ped, accuracy)
    SetPedAccuracy(ped, accuracy)
    SetPedCombatAttributes(ped, 0,  true)
    SetPedCombatAttributes(ped, 1,  true)
    SetPedCombatAttributes(ped, 2,  true)
    SetPedCombatAttributes(ped, 5,  true)
    SetPedCombatAttributes(ped, 46, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCombatMovement(ped, 2)
    SetPedCombatRange(ped, 2)
    SetPedCanRagdoll(ped, false)
end

local function setHealth(ped, extraHealth, armor)
    SetEntityMaxHealth(ped, 100 + extraHealth)
    SetEntityHealth(ped, 100 + extraHealth)
    SetPedArmour(ped, armor)
end

local function combinedHP(ped)
    return math.max(0, GetEntityHealth(ped) - 100) + GetPedArmour(ped)
end

-- Does this NPC have at least one living enemy on the field?
local function hasLivingEnemies(n)
    for _, other in ipairs(ActiveNpcs) do
        if other.alive and other.owner ~= n.owner
            and DoesEntityExist(other.ped) and not IsEntityDead(other.ped)
        then
            return true
        end
    end
    return false
end

-- Re-task living NPCs to combat.
-- Always issues TaskCombatHatedTargetsInArea so new/idle NPCs start fighting
-- immediately.  Only resets n.emoting (and thus interrupts a looping scenario)
-- when the NPC actually has living enemies — NPCs celebrating with nobody left
-- to fight keep their animation uninterrupted.
local function refreshCombat()
    local ac = Config.ArenaCenter
    for _, n in ipairs(ActiveNpcs) do
        if n.alive and DoesEntityExist(n.ped) and not IsEntityDead(n.ped) then
            if hasLivingEnemies(n) then
                n.emoting = false
            end
            TaskCombatHatedTargetsInArea(n.ped, ac.x, ac.y, ac.z, 200.0, 0)
        end
    end
    for _, f in ipairs(ActiveFodder) do
        if f.alive and DoesEntityExist(f.ped) and not IsEntityDead(f.ped) then
            TaskCombatHatedTargetsInArea(f.ped, ac.x, ac.y, ac.z, 80.0, 0)
        end
    end
end

-- Spawn a tinted smoke puff at a world position
local function spawnDeathSmoke(pos, color)
    CreateThread(function()
        RequestNamedPtfxAsset('core')
        local t = 0
        while not HasNamedPtfxAssetLoaded('core') do
            Wait(1); t = t + 1; if t > 120 then return end
        end
        local r = (color[1] or 200) / 255
        local g = (color[2] or 200) / 255
        local b = (color[3] or 200) / 255
        SetParticleFxNonLoopedColour(r, g, b)
        UseParticleFxAssetNextCall('core')
        StartParticleFxNonLoopedAtCoord('exp_grd_smoke', pos.x, pos.y, pos.z + 0.5,
            0.0, 0.0, 0.0, 3.5, false, false, false)
    end)
end

-- ---------------------------------------------------------------------------
-- Public: Spawn a viewer NPC
-- npcData = { owner, colorIndex, zoneIndex, model, weapon, health, armor,
--             accuracy, tierName }
-- ---------------------------------------------------------------------------
function SpawnLmsNpc(npcData)
    local viewerGroup = getOrCreateViewerGroup(npcData.owner)
    local color = Config.ViewerColors[npcData.colorIndex] or { 255, 255, 255 }
    local zone  = Config.SpawnZones[npcData.zoneIndex]    or Config.SpawnZones[1]

    local alive = 0
    for _, n in ipairs(ActiveNpcs) do
        if n.owner == npcData.owner and n.alive then alive = alive + 1 end
    end
    if alive >= Config.MaxNpcsPerViewer then return end

    local angle = math.random() * math.pi * 2
    local dist  = math.random() * zone.scatter
    local sx    = zone.spawn.x + math.cos(angle) * dist
    local sy    = zone.spawn.y + math.sin(angle) * dist
    local sz    = zone.spawn.z

    local ped = spawnPed(npcData.model, sx, sy, sz, 0.0)
    if not ped then return end

    if npcData.weapon then
        GiveWeaponToPed(ped, GetHashKey(npcData.weapon), 9999, false, true)
    end
    setHealth(ped, npcData.health, npcData.armor)
    setupCombatAI(ped, npcData.accuracy)
    SetPedRelationshipGroupHash(ped, viewerGroup)
    SetPedCanBeTargettedByPlayer(ped, PlayerId(), false)

    local maxHP   = npcData.health + npcData.armor
    local npcName = pickName(npcData.model)
    viewerDisplayNames[npcData.owner] = npcName   -- for elimination toasts
    local r, g, b = color[1], color[2], color[3]

    local now = GetGameTimer()
    ActiveNpcs[#ActiveNpcs + 1] = {
        ped        = ped,
        owner      = npcData.owner,
        colorIndex = npcData.colorIndex,
        tierName   = npcData.tierName,
        npcName    = npcName,
        alive      = true,
        maxHP      = maxHP,
        prevHP     = maxHP,
        emoting    = false,
        emoteEnd   = 0,
        points     = npcData.points or 1,
        lastRetask  = now,
        lastNavTask = 0,
    }

    -- 3D label: team name / character name / HP bar
    LmsLabels[ped] = {
        teamName = npcData.owner,
        charName = npcName,
        r = r, g = g, b = b,
        maxHP = maxHP,
    }

    if Config.ActionCamEnabled and exports['actioncam'] then
        pcall(function() exports['actioncam']:AddTrackedPed(ped, 4) end)  -- highest priority
    end

    -- Task only the new ped into combat — don't retask all existing NPCs on every spawn
    local ac = Config.ArenaCenter
    TaskCombatHatedTargetsInArea(ped, ac.x, ac.y, ac.z, 200.0, 0)
end

-- ---------------------------------------------------------------------------
-- Public: Spawn weak fodder batch
-- ---------------------------------------------------------------------------
function SpawnFodder()
    local cfg = Config.FodderNpc
    local ac  = Config.ArenaCenter

    -- Respect the max-fodder cap
    local aliveFodder = 0
    for _, f in ipairs(ActiveFodder) do if f.alive then aliveFodder = aliveFodder + 1 end end
    local canSpawn = math.min(Config.FodderBatchSize, Config.MaxFodder - aliveFodder)
    if canSpawn <= 0 then return end

    for _ = 1, canSpawn do
        local angle = math.random() * math.pi * 2
        local dist  = 12.0 + math.random() * 18.0
        local model = cfg.models[math.random(#cfg.models)]

        local ped = spawnPed(model, ac.x + math.cos(angle) * dist, ac.y + math.sin(angle) * dist, ac.z, 0.0)
        if ped then
            setHealth(ped, cfg.health, cfg.armor)
            SetPedAccuracy(ped, cfg.accuracy)
            SetPedFleeAttributes(ped, 0, false)
            TaskSetBlockingOfNonTemporaryEvents(ped, true)   -- prevent ambient flee-from-weapon events
            SetPedCanRagdoll(ped, true)
            SetPedRelationshipGroupHash(ped, FODDER_GROUP)

            ActiveFodder[#ActiveFodder + 1] = { ped = ped, alive = true, emoting = false, emoteEnd = 0, points = cfg.points or 1 }
            LmsLabels[ped] = { charName = cfg.tierName or 'Fodder', r = 170, g = 170, b = 170, maxHP = cfg.health }

            if Config.ActionCamEnabled and exports['actioncam'] then
                pcall(function() exports['actioncam']:AddTrackedPed(ped, 2) end)  -- below guards
            end

            TaskCombatHatedTargetsInArea(ped, ac.x, ac.y, ac.z, 80.0, 0)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public: Spawn hostile attacker NPCs (fight viewer NPCs, half-freq of fodder)
-- ---------------------------------------------------------------------------
function SpawnAttackers()
    local cfg = Config.AttackerNpc
    local ac  = Config.ArenaCenter

    local aliveCount = 0
    for _, a in ipairs(ActiveAttackers) do if a.alive then aliveCount = aliveCount + 1 end end
    local canSpawn = math.min(Config.AttackerBatchSize, Config.MaxAttackers - aliveCount)
    if canSpawn <= 0 then return end

    for _ = 1, canSpawn do
        local angle = math.random() * math.pi * 2
        local dist  = 15.0 + math.random() * 20.0
        local model = cfg.models[math.random(#cfg.models)]

        local ped = spawnPed(model, ac.x + math.cos(angle) * dist, ac.y + math.sin(angle) * dist, ac.z, 0.0)
        if ped then
            if cfg.weapon then
                GiveWeaponToPed(ped, GetHashKey(cfg.weapon), 9999, false, true)
            end
            setHealth(ped, cfg.health, cfg.armor)
            setupCombatAI(ped, cfg.accuracy)
            SetPedRelationshipGroupHash(ped, ATTACKER_GROUP)
            SetPedFleeAttributes(ped, 0, false)

            ActiveAttackers[#ActiveAttackers + 1] = {
                ped    = ped,
                alive  = true,
                points = cfg.points or 3,
            }
            LmsLabels[ped] = {
                charName = cfg.tierName or 'Guard',
                r = 220, g = 80, b = 80,
                maxHP = cfg.health + cfg.armor,
            }

            if Config.ActionCamEnabled and exports['actioncam'] then
                pcall(function() exports['actioncam']:AddTrackedPed(ped, 3) end)  -- above fodder, below viewers
            end

            TaskCombatHatedTargetsInArea(ped, ac.x, ac.y, ac.z, 150.0, 0)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public: Clear everything
-- ---------------------------------------------------------------------------
function ClearAllNpcs()
    for _, n in ipairs(ActiveNpcs) do
        if DoesEntityExist(n.ped) then
            if Config.ActionCamEnabled and exports['actioncam'] then
                pcall(function() exports['actioncam']:RemoveTrackedPed(n.ped) end)
            end
            LmsLabels[n.ped] = nil
            DeleteEntity(n.ped)
        end
    end
    ActiveNpcs = {}

    for _, f in ipairs(ActiveFodder) do
        if DoesEntityExist(f.ped) then
            if Config.ActionCamEnabled and exports['actioncam'] then
                pcall(function() exports['actioncam']:RemoveTrackedPed(f.ped) end)
            end
            LmsLabels[f.ped] = nil
            DeleteEntity(f.ped)
        end
    end
    ActiveFodder = {}

    for _, a in ipairs(ActiveAttackers) do
        if DoesEntityExist(a.ped) then
            if Config.ActionCamEnabled and exports['actioncam'] then
                pcall(function() exports['actioncam']:RemoveTrackedPed(a.ped) end)
            end
            LmsLabels[a.ped] = nil
            DeleteEntity(a.ped)
        end
    end
    ActiveAttackers = {}

    viewerGroups       = {}
    usedNames          = {}
    viewerDisplayNames = {}
    lastKillerOf       = {}
    crewEliminatePending = {}
end

-- ---------------------------------------------------------------------------
-- Health data for NUI crew cards
-- ---------------------------------------------------------------------------
function GetCrewHealthData()
    local byOwner = {}
    for _, n in ipairs(ActiveNpcs) do
        -- Only include living peds so total/alive counts stay accurate
        if not n.alive then goto nextNpcCD end
        if not DoesEntityExist(n.ped) then goto nextNpcCD end

        if not byOwner[n.owner] then
            local c = Config.ViewerColors[n.colorIndex] or { 255, 255, 255 }
            byOwner[n.owner] = { owner = n.owner, color = c, alive = 0, total = 0, peds = {} }
        end
        local crew = byOwner[n.owner]
        crew.total = crew.total + 1
        crew.alive = crew.alive + 1
        local pct = math.min(1.0, combinedHP(n.ped) / math.max(1, n.maxHP))
        crew.peds[#crew.peds + 1] = { tierName = n.npcName, pct = pct, alive = true }

        ::nextNpcCD::
    end
    local result = {}
    for _, crew in pairs(byOwner) do
        -- Lowest HP first so the most at-risk peds sit at the top
        table.sort(crew.peds, function(a, b) return a.pct < b.pct end)
        -- Cap displayed peds to MaxCrewUIPeds
        if #crew.peds > Config.MaxCrewUIPeds then
            for i = #crew.peds, Config.MaxCrewUIPeds + 1, -1 do
                table.remove(crew.peds, i)
            end
        end
        result[#result + 1] = crew
    end
    return result
end

-- ---------------------------------------------------------------------------
-- Fodder health data for NUI corner panel
-- ---------------------------------------------------------------------------
function GetFodderHealthData()
    local alive, total = 0, 0
    local pcts = {}
    for _, f in ipairs(ActiveFodder) do
        total = total + 1
        if f.alive and DoesEntityExist(f.ped) and not IsEntityDead(f.ped) then
            alive = alive + 1
            if #pcts < Config.MaxCrewUIPeds then
                local hp = math.max(0, GetEntityHealth(f.ped) - 100)
                pcts[#pcts + 1] = math.min(1.0, hp / math.max(1, Config.FodderNpc.health))
            end
        end
    end
    return { alive = alive, total = total, pcts = pcts }
end

-- ---------------------------------------------------------------------------
-- Attacker health data for NUI guard card
-- ---------------------------------------------------------------------------
function GetAttackerHealthData()
    local alive, total = 0, 0
    local pcts = {}
    for _, a in ipairs(ActiveAttackers) do
        total = total + 1
        if a.alive and DoesEntityExist(a.ped) and not IsEntityDead(a.ped) then
            alive = alive + 1
            if #pcts < Config.MaxCrewUIPeds then
                local hp = math.max(0, GetEntityHealth(a.ped) - 100)
                pcts[#pcts + 1] = math.min(1.0, hp / math.max(1, Config.AttackerNpc.health))
            end
        end
    end
    return { alive = alive, total = total, pcts = pcts }
end

-- ---------------------------------------------------------------------------
-- Behavior loop: center attraction, emotes, and scatter prevention
-- Runs every BehaviorTickMs.  Only touches NPCs that are not actively fighting.
-- ---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.BehaviorTickMs)
        local ac  = Config.ArenaCenter
        local now = GetGameTimer()

        for _, n in ipairs(ActiveNpcs) do
            if not n.alive then goto nextBeh end
            if not DoesEntityExist(n.ped) or IsEntityDead(n.ped) then goto nextBeh end

            local inCombat   = IsPedInCombat(n.ped)
            local hasEnemies = hasLivingEnemies(n)

            local pos  = GetEntityCoords(n.ped)
            local dist = #(pos - vector3(ac.x, ac.y, ac.z))

            if inCombat then
                -- Actively fighting — apply leash so they can't chase enemies off-map
                n.emoting = false
                if dist > Config.LeashRadius then
                    ClearPedTasksImmediately(n.ped)
                    TaskFollowNavMeshToCoord(n.ped, ac.x, ac.y, ac.z, 3.0, 6000, 1.0, true, 0.0)
                    n.lastNavTask = now
                end

            elseif hasEnemies then
                -- Enemies exist but this NPC isn't actively fighting right now.
                -- IsPedInCombat is briefly false between attacks/target switches, so we
                -- guard retasking with a cooldown to avoid the constant "squaring up" twitch.
                if dist <= Config.CenterZoneRadius then
                    if not n.emoting or now >= n.emoteEnd then
                        local emote = Config.CenterEmotes[math.random(#Config.CenterEmotes)]
                        ClearPedTasks(n.ped)
                        TaskStartScenarioInPlace(n.ped, emote, 0, true)
                        n.emoting = true
                        n.emoteEnd = now + math.random(Config.EmoteMinMs, Config.EmoteMaxMs)
                    end
                elseif (now - (n.lastRetask or 0)) >= 5000 then
                    n.emoting    = false
                    n.lastRetask = now
                    TaskCombatHatedTargetsInArea(n.ped, ac.x, ac.y, ac.z, 200.0, 0)
                end

            else
                -- No enemies alive — walk to center and emote (celebrate/idle)
                if dist <= Config.CenterZoneRadius then
                    if not n.emoting or now >= n.emoteEnd then
                        local emote = Config.CenterEmotes[math.random(#Config.CenterEmotes)]
                        ClearPedTasks(n.ped)
                        TaskStartScenarioInPlace(n.ped, emote, 0, true)
                        n.emoting = true
                        n.emoteEnd = now + math.random(Config.EmoteMinMs, Config.EmoteMaxMs)
                    end
                elseif (now - (n.lastNavTask or 0)) >= 7000 then
                    n.emoting     = false
                    n.lastNavTask = now
                    TaskFollowNavMeshToCoord(n.ped, ac.x, ac.y, ac.z, 1.0, 6000, 1.0, true, 0.0)
                end
            end

            ::nextBeh::
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Fodder behavior: emotes, socialising, world-alive feel
-- ---------------------------------------------------------------------------
local FODDER_EMOTES = {
    -- Casual hanging out
    'WORLD_HUMAN_HANG_OUT_STREET',
    'WORLD_HUMAN_LEANING',
    'WORLD_HUMAN_STAND_MOBILE',
    'WORLD_HUMAN_TOURIST_MOBILE',
    'WORLD_HUMAN_AA_SMOKE_STAND',
    -- Physical / funny
    'WORLD_HUMAN_PUSH_UPS',
    'WORLD_HUMAN_YOGA',
    'WORLD_HUMAN_MUSCLE_CURL',
    'WORLD_HUMAN_JOG_STANDING',
    'WORLD_HUMAN_CHEERING',
    -- Looking around
    'WORLD_HUMAN_BINOCULARS',
    'WORLD_HUMAN_TOURIST_MAP',
    'WORLD_HUMAN_SECURITY_SHINE_TORCH',
    'WORLD_HUMAN_PAPARAZZI',
    -- Seated / relaxing
    'WORLD_HUMAN_SEAT_LEDGE',
    'WORLD_HUMAN_PICNIC',
    -- Drinking / smoking
    'WORLD_HUMAN_DRINKING',
    'WORLD_HUMAN_AA_COFFEE',
    'WORLD_HUMAN_SMOKING',
    -- Guard poses (ironic for prison)
    'WORLD_HUMAN_GUARD_STAND',
    'WORLD_HUMAN_COP_IDLES',
    'WORLD_HUMAN_CLIPBOARD',
    -- Misc
    'WORLD_HUMAN_PARTYING',
    'WORLD_HUMAN_JANITOR',
}

-- Emotes used when two fodder are near each other (social)
local SOCIAL_EMOTES = {
    'WORLD_HUMAN_HANG_OUT_STREET',
    'WORLD_HUMAN_CHEERING',
    'WORLD_HUMAN_SMOKING',
    'WORLD_HUMAN_AA_COFFEE',
    'WORLD_HUMAN_LEANING',
    'WORLD_HUMAN_STAND_MOBILE',
    'WORLD_HUMAN_DRINKING',
    'WORLD_HUMAN_PARTYING',
}

local function playFodderEmote(f, isSocial)
    local pool = isSocial and SOCIAL_EMOTES or FODDER_EMOTES
    local emote = pool[math.random(#pool)]
    ClearPedTasks(f.ped)
    TaskStartScenarioInPlace(f.ped, emote, 0, true)
    f.emoting = true
    f.emoteEnd = GetGameTimer() + math.random(Config.EmoteMinMs, Config.EmoteMaxMs)
end

-- Runs every 4 s.  Only touches fodder that are NOT in combat.
-- When enemies are present refreshCombat() has already issued
-- TaskCombatHatedTargetsInArea which overrides any scenario.
CreateThread(function()
    while true do
        Wait(4000)
        local now = GetGameTimer()
        for _, f in ipairs(ActiveFodder) do
            if not f.alive then goto nextFodder end
            if not DoesEntityExist(f.ped) or IsEntityDead(f.ped) then goto nextFodder end
            if IsPedInCombat(f.ped) then f.emoting = false; f.emoteEnd = 0; goto nextFodder end
            -- Hold the current emote until its duration expires
            if f.emoting and now < f.emoteEnd then goto nextFodder end

            -- Find nearest alive fodder peer
            local nearest, nearestDist = nil, math.huge
            for _, other in ipairs(ActiveFodder) do
                if other ~= f and other.alive and DoesEntityExist(other.ped) and not IsEntityDead(other.ped) then
                    local d = #(GetEntityCoords(other.ped) - GetEntityCoords(f.ped))
                    if d < nearestDist then nearest = other; nearestDist = d end
                end
            end

            if nearest and nearestDist <= 2.5 then
                -- Close to another fodder — play a social emote together
                playFodderEmote(f, true)
                if not nearest.emoting then playFodderEmote(nearest, true) end

            elseif nearest and nearestDist > 2.5 and nearestDist < 18.0 and math.random() < 0.35 then
                -- Walk toward a nearby peer (will socialise when they arrive)
                local tpos = GetEntityCoords(nearest.ped)
                ClearPedTasks(f.ped)
                TaskFollowNavMeshToCoord(f.ped, tpos.x, tpos.y, tpos.z, 1.0, 8000, 1.5, true, 0.0)
                f.emoting = false

            else
                -- Solo emote
                playFodderEmote(f, false)
            end

            ::nextFodder::
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Health tracking: detect deaths, attribute kills, report crew wipe-outs
-- ---------------------------------------------------------------------------
local crewEliminatePending = {}
local lastKillerOf         = {}   -- [owner] = last entity that killed one of their NPCs

CreateThread(function()
    while true do
        Wait(Config.HealthBarRefreshMs)

        for _, n in ipairs(ActiveNpcs) do
            if not n.alive then goto nextNpc end
            if not DoesEntityExist(n.ped) or IsEntityDead(n.ped) then
                n.alive = false
                LmsLabels[n.ped] = nil
                if Config.ActionCamEnabled and exports['actioncam'] then
                    pcall(function() exports['actioncam']:RemoveTrackedPed(n.ped) end)
                end

                -- Capture position before deletion, then instantly remove corpse
                local deadPos = GetEntityCoords(n.ped)
                if Config.DeathSmokeEnabled then
                    local color = Config.ViewerColors[n.colorIndex] or { 200, 200, 200 }
                    spawnDeathSmoke(deadPos, color)
                end
                if DoesEntityExist(n.ped) then DeleteEntity(n.ped) end

                -- Attribute kill: check viewer NPCs, fodder, and attackers by proximity
                local killerOwner, killerPed, nearestDist = nil, nil, math.huge
                local killerIsViewer = false

                for _, other in ipairs(ActiveNpcs) do
                    if other.alive and other.owner ~= n.owner and DoesEntityExist(other.ped) then
                        local d = #(GetEntityCoords(other.ped) - deadPos)
                        if d < nearestDist then
                            killerOwner = other.owner; killerPed = other.ped
                            nearestDist = d; killerIsViewer = true
                        end
                    end
                end
                for _, f in ipairs(ActiveFodder) do
                    if f.alive and DoesEntityExist(f.ped) then
                        local d = #(GetEntityCoords(f.ped) - deadPos)
                        if d < nearestDist then
                            killerOwner = Config.FodderNpc.tierName or 'Fodder'
                            killerPed = f.ped; nearestDist = d; killerIsViewer = false
                        end
                    end
                end
                for _, a in ipairs(ActiveAttackers) do
                    if a.alive and DoesEntityExist(a.ped) then
                        local d = #(GetEntityCoords(a.ped) - deadPos)
                        if d < nearestDist then
                            killerOwner = Config.AttackerNpc.tierName or 'Guard'
                            killerPed = a.ped; nearestDist = d; killerIsViewer = false
                        end
                    end
                end

                -- Only award points to real viewer crews, not NPC categories
                if killerIsViewer and killerOwner then
                    TriggerServerEvent('lms:reportKill', killerOwner, n.points or 1)
                end
                lastKillerOf[n.owner] = killerOwner

                if killerPed and Config.ActionCamEnabled and exports['actioncam'] then
                    pcall(function() exports['actioncam']:AddPedHeat(killerPed, 80) end)
                end
            end
            ::nextNpc::
        end

        -- Crew wipe-out detection
        local crewAlive = {}
        for _, n in ipairs(ActiveNpcs) do
            crewAlive[n.owner] = crewAlive[n.owner] or false
            if n.alive then crewAlive[n.owner] = true end
        end
        for owner, alive in pairs(crewAlive) do
            if not alive and not crewEliminatePending[owner] then
                crewEliminatePending[owner] = true

                -- Use tracked last killer (viewer, Fodder, Guard, or nil)
                local killerName = lastKillerOf[owner]
                lastKillerOf[owner] = nil

                TriggerServerEvent('lms:crewEliminated', owner, killerName)

                CreateThread(function()
                    Wait(3500)
                    for i = #ActiveNpcs, 1, -1 do
                        local n = ActiveNpcs[i]
                        if n.owner == owner then
                            if DoesEntityExist(n.ped) then DeleteEntity(n.ped) end
                            table.remove(ActiveNpcs, i)
                        end
                    end
                    crewEliminatePending[owner] = nil
                end)
            end
        end

        -- Fodder death cleanup
        for _, f in ipairs(ActiveFodder) do
            if f.alive and (not DoesEntityExist(f.ped) or IsEntityDead(f.ped)) then
                f.alive = false
                LmsLabels[f.ped] = nil
                if DoesEntityExist(f.ped) then
                    local fodderPos = GetEntityCoords(f.ped)

                    -- Award points to nearest viewer NPC
                    local fKillerOwner, fNearestDist = nil, math.huge
                    for _, other in ipairs(ActiveNpcs) do
                        if other.alive and DoesEntityExist(other.ped) then
                            local d = #(GetEntityCoords(other.ped) - fodderPos)
                            if d < fNearestDist then fKillerOwner = other.owner; fNearestDist = d end
                        end
                    end
                    if fKillerOwner then
                        TriggerServerEvent('lms:reportKill', fKillerOwner, f.points or 1)
                    end

                    if Config.ActionCamEnabled and exports['actioncam'] then
                        pcall(function() exports['actioncam']:RemoveTrackedPed(f.ped) end)
                    end
                    if Config.DeathSmokeEnabled then
                        spawnDeathSmoke(fodderPos, {
                            math.random(80, 255),
                            math.random(80, 255),
                            math.random(80, 255),
                        })
                    end
                    DeleteEntity(f.ped)
                end
            end
        end

        -- Attacker death cleanup
        for _, a in ipairs(ActiveAttackers) do
            if a.alive and (not DoesEntityExist(a.ped) or IsEntityDead(a.ped)) then
                a.alive = false
                LmsLabels[a.ped] = nil
                if DoesEntityExist(a.ped) then
                    local aPos = GetEntityCoords(a.ped)
                    local aKiller, aDist = nil, math.huge
                    for _, other in ipairs(ActiveNpcs) do
                        if other.alive and DoesEntityExist(other.ped) then
                            local d = #(GetEntityCoords(other.ped) - aPos)
                            if d < aDist then aKiller = other.owner; aDist = d end
                        end
                    end
                    if aKiller then TriggerServerEvent('lms:reportKill', aKiller, a.points or 3) end
                    if Config.ActionCamEnabled and exports['actioncam'] then
                        pcall(function() exports['actioncam']:RemoveTrackedPed(a.ped) end)
                    end
                    if Config.DeathSmokeEnabled then
                        spawnDeathSmoke(aPos, { 220, 60, 60 })
                    end
                    DeleteEntity(a.ped)
                end
            end
        end
    end
end)

-- Periodic fodder spawns
if Config.FodderEnabled then
    CreateThread(function()
        while true do
            Wait(Config.FodderInterval * 1000)
            if lmsRunning then SpawnFodder() end
        end
    end)
end

-- Periodic attacker spawns (half as often as fodder)
if Config.AttackerEnabled then
    CreateThread(function()
        while true do
            Wait(Config.AttackerInterval * 1000)
            if lmsRunning then SpawnAttackers() end
        end
    end)
end
