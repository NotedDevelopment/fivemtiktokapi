-- =============================================================================
-- Ped Management
-- =============================================================================

-- ---------------------------------------------------------------------------
-- ActionCam helpers (no-ops if actioncam isn't running)
-- ---------------------------------------------------------------------------
local function acAdd(ped)
    pcall(function() exports['actioncam']:AddTrackedPed(ped) end)
end
local function acRemove(ped)
    pcall(function() exports['actioncam']:RemoveTrackedPed(ped) end)
end

-- ---------------------------------------------------------------------------
-- Random selection from arrays (falls back gracefully to plain values)
-- ---------------------------------------------------------------------------
local function pickOne(t)
    if type(t) == 'table' and #t > 0 then return t[math.random(#t)] end
    return t
end

-- ---------------------------------------------------------------------------
-- Active ped tables
-- ---------------------------------------------------------------------------
ActiveDefenders = {}
--[[
    ActiveDefenders[key] = {
        ped, cfg, alive, maxHP, prevHP, homePos, homeHead, state, idleTimer,
        converted (bool, optional), convertedOwner (string, optional)
    }
--]]

ActiveAttackers = {}
--[[
    ActiveAttackers[i] = {
        ped, owner, colorIndex, tier, tierName, alive, maxHP, prevHP,
        damageDealt, kills
    }
--]]

local _defIdx = 100  -- counter for converted/reinforcement defender keys

-- ---------------------------------------------------------------------------
-- Who is currently filling the defender role via conversion
-- nil = original static defenders
-- ---------------------------------------------------------------------------
local convertedOwner = nil

-- ---------------------------------------------------------------------------
-- Relationship groups
-- ---------------------------------------------------------------------------
local DEFENDER_GROUP = GetHashKey('ARENA_DEFENDERS')
AddRelationshipGroup('ARENA_DEFENDERS')

local viewerGroups = {}

local AMBIENT_NPC_GROUPS = {
    'COP', 'CIVMALE', 'CIVFEMALE', 'SECURITY_GUARD',
    'GANG_1','GANG_2','GANG_3','GANG_4','GANG_5',
    'GANG_6','GANG_7','GANG_8','GANG_9','GANG_10',
    'AMBIENT_GANG_LOST','AMBIENT_GANG_BALLAS','AMBIENT_GANG_VAGOS',
    'AMBIENT_GANG_FAMILY','AMBIENT_GANG_MARABUNTE','AMBIENT_GANG_SALVA',
    'AMBIENT_GANG_WEICHENG','ARMY','FIREMAN','MEDIC',
}

CreateThread(function()
    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())
    SetRelationshipBetweenGroups(0, DEFENDER_GROUP, playerGroup)
    SetRelationshipBetweenGroups(0, playerGroup, DEFENDER_GROUP)
    for _, name in ipairs(AMBIENT_NPC_GROUPS) do
        local hash = GetHashKey(name)
        SetRelationshipBetweenGroups(5, DEFENDER_GROUP, hash)
        SetRelationshipBetweenGroups(5, hash, DEFENDER_GROUP)
    end
end)

local function sanitize(name)
    return name:upper():gsub('[^A-Z0-9]', '_')
end

local function getOrCreateViewerGroup(username)
    if viewerGroups[username] then return viewerGroups[username] end
    local groupName = 'ARENA_V_' .. sanitize(username)
    AddRelationshipGroup(groupName)
    local hash = GetHashKey(groupName)
    viewerGroups[username] = hash

    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())
    SetRelationshipBetweenGroups(0, hash, playerGroup)
    SetRelationshipBetweenGroups(0, playerGroup, hash)
    SetRelationshipBetweenGroups(5, hash, DEFENDER_GROUP)
    SetRelationshipBetweenGroups(5, DEFENDER_GROUP, hash)
    for otherUser, otherHash in pairs(viewerGroups) do
        if otherUser ~= username then
            SetRelationshipBetweenGroups(5, hash, otherHash)
            SetRelationshipBetweenGroups(5, otherHash, hash)
        end
    end
    return hash
end

-- ---------------------------------------------------------------------------
-- Internal helpers
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

local function setupCombatAI(ped, accuracy)
    SetPedAccuracy(ped, accuracy)
    SetPedCombatAttributes(ped, 0,  true)   -- CanUseCover
    SetPedCombatAttributes(ped, 1,  true)   -- CanNavigate
    SetPedCombatAttributes(ped, 2,  true)   -- FullyRetaliates
    SetPedCombatAttributes(ped, 5,  true)   -- AlwaysFight
    SetPedCombatAttributes(ped, 46, true)   -- CanFightArmedPedsWhenNotArmed
    SetPedCombatAttributes(ped, 52, true)   -- WillChaseTarget — pursues fleeing/distant enemies
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

local function spawnPed(model, x, y, z, heading)
    -- Make sure the game has collision loaded at the spawn point so the ground
    -- Z lookup below is accurate.
    RequestCollisionAtCoord(x, y, z)

    -- Snap Z to actual ground level.  We start the ray 3 m above the nominal Z
    -- so slight underground coords are corrected automatically.
    local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 3.0, false)
    if found then
        z = groundZ + 0.08   -- tiny buffer so the ped sits on top of the surface
    end

    local hash = GetHashKey(model)
    if not loadModel(hash) then
        print('[Arena] Failed to load model: ' .. model); return nil
    end
    local ped = CreatePed(4, hash, x, y, z, heading, false, true)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return nil end

    -- Final safety net: let the engine place the ped on the nearest surface.
    SetEntityOnGroundProperly(ped)

    return ped
end

-- ---------------------------------------------------------------------------
-- refreshCombat
-- Uses TaskCombatHatedTargetsInArea for BOTH defenders and attackers so the
-- AI continuously hunts all hostile groups without needing a specific target.
-- ---------------------------------------------------------------------------
local function refreshCombat()
    local ac = Config.ArenaCenter
    for _, d in pairs(ActiveDefenders) do
        if d.alive and DoesEntityExist(d.ped) and not IsEntityDead(d.ped) then
            TaskCombatHatedTargetsInArea(d.ped, ac.x, ac.y, ac.z, 250.0, 0)
            d.state = 'combat'
        end
    end
    for _, a in ipairs(ActiveAttackers) do
        if a.alive and DoesEntityExist(a.ped) and not IsEntityDead(a.ped) then
            TaskCombatHatedTargetsInArea(a.ped, ac.x, ac.y, ac.z, 250.0, 0)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Public: Spawn Defenders
-- ---------------------------------------------------------------------------
function SpawnDefenders()
    ClearDefenders()

    for i, cfg in ipairs(Config.Defenders) do
        local ped = spawnPed(cfg.model, cfg.coords.x, cfg.coords.y, cfg.coords.z, cfg.coords.w)
        if ped then
            GiveWeaponToPed(ped, GetHashKey(cfg.weapon), 9999, false, true)
            setHealth(ped, cfg.health, cfg.armor)
            setupCombatAI(ped, cfg.accuracy)
            SetPedRelationshipGroupHash(ped, DEFENDER_GROUP)
            SetPedCanBeTargettedByPlayer(ped, PlayerId(), false)
            if Config.DisableBlood then SetPedSuffersCriticalHits(ped, false) end

            local maxHP = cfg.health + cfg.armor
            ActiveDefenders[i] = {
                ped       = ped,
                cfg       = cfg,
                alive     = true,
                maxHP     = maxHP,
                prevHP    = maxHP,
                homePos   = vector3(cfg.coords.x, cfg.coords.y, cfg.coords.z),
                homeHead  = cfg.coords.w,
                state     = 'idle',
                idleTimer = 0,
            }
            ArenaLabels[ped] = { text = cfg.label, r = 255, g = 255, b = 255 }
            acAdd(ped)
        end
    end
    refreshCombat()
end

-- ---------------------------------------------------------------------------
-- Public: Spawn Attacker Wave
-- ---------------------------------------------------------------------------
function SpawnAttackerWave(waveData)
    if waveData.isReinforcement then
        SpawnReinforcementWave(waveData)
        return
    end

    local viewerGroup = getOrCreateViewerGroup(waveData.owner)
    local color = Config.ViewerColors[waveData.colorIndex] or { 255, 255, 255 }
    local r, g, b = color[1], color[2], color[3]

    local zoneIdx   = ((waveData.zoneIndex - 1) % #Config.SpawnZones) + 1
    local zone      = Config.SpawnZones[zoneIdx]
    local centerX   = waveData.spawnX or zone.spawn.x
    local centerY   = waveData.spawnY or zone.spawn.y
    local approachX = zone.approach.x
    local approachY = zone.approach.y

    for _, slot in ipairs(waveData.composition) do
        local tierCfg = Config.Tiers[slot.tier]
        if not tierCfg then goto continue end

        for _ = 1, slot.count do
            local angle = math.random() * math.pi * 2
            local dist  = math.random() * zone.scatter
            local sx    = centerX + math.cos(angle) * dist
            local sy    = centerY + math.sin(angle) * dist
            local sz    = zone.spawn.z

            local model    = pickOne(tierCfg.models  or tierCfg.model)
            local weapon   = pickOne(tierCfg.weapons or tierCfg.weapon)
            local pedName  = pickOne(tierCfg.names   or tierCfg.name)
            local label    = ('[%s] %s'):format(waveData.owner, pedName)

            local ped = spawnPed(model, sx, sy, sz, 0.0)
            if ped then
                GiveWeaponToPed(ped, GetHashKey(weapon), 9999, false, true)
                setHealth(ped, tierCfg.health, tierCfg.armor)
                setupCombatAI(ped, tierCfg.accuracy)
                SetPedRelationshipGroupHash(ped, viewerGroup)
                SetPedCanBeTargettedByPlayer(ped, PlayerId(), false)
                if Config.DisableBlood then SetPedSuffersCriticalHits(ped, false) end

                local maxHP = tierCfg.health + tierCfg.armor
                ActiveAttackers[#ActiveAttackers + 1] = {
                    ped         = ped,
                    owner       = waveData.owner,
                    colorIndex  = waveData.colorIndex,
                    tier        = slot.tier,
                    tierName    = pedName,
                    alive       = true,
                    maxHP       = maxHP,
                    prevHP      = maxHP,
                    damageDealt = 0,
                    kills       = 0,
                    approachX   = approachX,   -- stored for pull-in logic
                    approachY   = approachY,
                }
                ArenaLabels[ped] = { text = label, r = r, g = g, b = b }
                acAdd(ped)
            end
        end
        ::continue::
    end

    refreshCombat()

    -- Tasks issued right at spawn can be silently cleared during ped initialisation.
    -- Re-issue at 500 ms and 2 s to cover that window.
    Citizen.SetTimeout(500,  refreshCombat)
    Citizen.SetTimeout(2000, refreshCombat)
end

-- ---------------------------------------------------------------------------
-- Public: Spawn Reinforcement Wave (owner is now defending)
-- Peds join ActiveDefenders and use DEFENDER_GROUP.
-- ---------------------------------------------------------------------------
function SpawnReinforcementWave(waveData)
    local color = Config.ViewerColors[waveData.colorIndex] or { 255, 255, 255 }
    local r, g, b = color[1], color[2], color[3]

    local zoneIdx = ((waveData.zoneIndex - 1) % #Config.SpawnZones) + 1
    local zone    = Config.SpawnZones[zoneIdx]
    local centerX = waveData.spawnX or zone.spawn.x
    local centerY = waveData.spawnY or zone.spawn.y
    local ac      = Config.ArenaCenter

    for _, slot in ipairs(waveData.composition) do
        local tierCfg = Config.Tiers[slot.tier]
        if not tierCfg then goto continue end

        for _ = 1, slot.count do
            local angle = math.random() * math.pi * 2
            local dist  = math.random() * zone.scatter
            local sx    = centerX + math.cos(angle) * dist
            local sy    = centerY + math.sin(angle) * dist
            local sz    = zone.spawn.z

            local model   = pickOne(tierCfg.models  or tierCfg.model)
            local weapon  = pickOne(tierCfg.weapons or tierCfg.weapon)
            local pedName = pickOne(tierCfg.names   or tierCfg.name)
            local label   = ('[' .. waveData.owner .. '] ' .. pedName)

            local ped = spawnPed(model, sx, sy, sz, 0.0)
            if ped then
                GiveWeaponToPed(ped, GetHashKey(weapon), 9999, false, true)
                setHealth(ped, tierCfg.health, tierCfg.armor)
                setupCombatAI(ped, tierCfg.accuracy)
                SetPedRelationshipGroupHash(ped, DEFENDER_GROUP)
                SetPedCanBeTargettedByPlayer(ped, PlayerId(), false)
                if Config.DisableBlood then SetPedSuffersCriticalHits(ped, false) end

                local maxHP = tierCfg.health + tierCfg.armor
                _defIdx = _defIdx + 1
                ActiveDefenders[_defIdx] = {
                    ped            = ped,
                    cfg            = { label = label },
                    alive          = true,
                    maxHP          = maxHP,
                    prevHP         = maxHP,
                    homePos        = vector3(sx, sy, sz),
                    homeHead       = 0.0,
                    state          = 'combat',
                    idleTimer      = 0,
                    converted      = true,
                    convertedOwner = waveData.owner,
                }
                ArenaLabels[ped] = { text = label, r = r, g = g, b = b }
                acAdd(ped)
                TaskCombatHatedTargetsInArea(ped, ac.x, ac.y, ac.z, 250.0, 0)
            end
        end
        ::continue::
    end
end

-- ---------------------------------------------------------------------------
-- Public: Clear helpers
-- ---------------------------------------------------------------------------
function ClearDefenders()
    for _, d in pairs(ActiveDefenders) do
        acRemove(d.ped)
        if DoesEntityExist(d.ped) then DeleteEntity(d.ped) end
        ArenaLabels[d.ped] = nil
    end
    ActiveDefenders = {}
    convertedOwner  = nil
end

function ClearAttackers()
    for _, a in ipairs(ActiveAttackers) do
        acRemove(a.ped)
        if DoesEntityExist(a.ped) then DeleteEntity(a.ped) end
        ArenaLabels[a.ped] = nil
    end
    ActiveAttackers = {}
end

function ClearCrewByOwner(owner)
    for i = #ActiveAttackers, 1, -1 do
        local a = ActiveAttackers[i]
        if a.owner == owner then
            acRemove(a.ped)
            if DoesEntityExist(a.ped) then DeleteEntity(a.ped) end
            ArenaLabels[a.ped] = nil
            table.remove(ActiveAttackers, i)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Health query helpers
-- ---------------------------------------------------------------------------
function GetDefenderHealthData()
    local result = {}
    local idx = 1
    for _, d in pairs(ActiveDefenders) do
        result[idx] = {
            label = d.cfg.label,
            pct   = d.alive and (combinedHP(d.ped) / d.maxHP) or 0,
            alive = d.alive,
        }
        idx = idx + 1
    end
    return result
end

function GetCrewHealthData()
    local byOwner = {}
    for _, a in ipairs(ActiveAttackers) do
        if not byOwner[a.owner] then
            local c = Config.ViewerColors[a.colorIndex] or { 255, 255, 255 }
            byOwner[a.owner] = { owner = a.owner, color = c, alive = 0, total = 0, peds = {} }
        end
        local crew = byOwner[a.owner]
        crew.total = crew.total + 1
        local pct = 0
        if a.alive and DoesEntityExist(a.ped) then
            pct = math.min(1.0, combinedHP(a.ped) / math.max(1, a.maxHP))
        end
        if a.alive then crew.alive = crew.alive + 1 end
        crew.peds[#crew.peds + 1] = { tierName = a.tierName, pct = pct, alive = a.alive }
    end
    local result = {}
    for _, crew in pairs(byOwner) do result[#result + 1] = crew end
    return result
end

-- ---------------------------------------------------------------------------
-- Net event: convert a winning attacker crew to the defending side
-- ---------------------------------------------------------------------------
RegisterNetEvent('arena:convertCrewToDefenders', true)
AddEventHandler('arena:convertCrewToDefenders', function(owner)
    convertedOwner = owner
    local ac = Config.ArenaCenter

    for i = #ActiveAttackers, 1, -1 do
        local a = ActiveAttackers[i]
        if a.owner == owner and a.alive and DoesEntityExist(a.ped) and not IsEntityDead(a.ped) then
            SetPedRelationshipGroupHash(a.ped, DEFENDER_GROUP)
            TaskCombatHatedTargetsInArea(a.ped, ac.x, ac.y, ac.z, 250.0, 0)

            local pos = GetEntityCoords(a.ped)
            _defIdx = _defIdx + 1
            ActiveDefenders[_defIdx] = {
                ped            = a.ped,
                cfg            = { label = ArenaLabels[a.ped] and ArenaLabels[a.ped].text or owner },
                alive          = true,
                maxHP          = a.maxHP,
                prevHP         = combinedHP(a.ped),
                homePos        = pos,
                homeHead       = GetEntityHeading(a.ped),
                state          = 'combat',
                idleTimer      = 0,
                converted      = true,
                convertedOwner = owner,
            }
            table.remove(ActiveAttackers, i)
        end
    end

    print('[Arena] @' .. owner .. '\'s crew converted to defenders.')
end)

-- ---------------------------------------------------------------------------
-- Health tracking loop
-- ---------------------------------------------------------------------------
local crewEndPending = {}

CreateThread(function()
    while true do
        Wait(Config.HealthBarRefreshMs)

        local defendersDead  = true
        local defendersExist = next(ActiveDefenders) ~= nil

        for _, d in pairs(ActiveDefenders) do
            if not d.alive then goto nextDef end
            if not DoesEntityExist(d.ped) or IsEntityDead(d.ped) then
                d.alive = false
                ArenaLabels[d.ped] = nil
                acRemove(d.ped)
                SchedulePedDeath(d.ped)
                goto nextDef
            end
            defendersDead = false

            local hp = combinedHP(d.ped)
            if hp < d.prevHP then
                local delta = d.prevHP - hp
                local nearest, nearestDist = nil, math.huge
                for _, a in ipairs(ActiveAttackers) do
                    if a.alive and DoesEntityExist(a.ped) then
                        local dist = #(GetEntityCoords(a.ped) - GetEntityCoords(d.ped))
                        if dist < nearestDist then nearest = a; nearestDist = dist end
                    end
                end
                if nearest then nearest.damageDealt = nearest.damageDealt + delta end
            end
            d.prevHP = hp
            ::nextDef::
        end

        local crewStats = {}
        for _, a in ipairs(ActiveAttackers) do
            if not crewStats[a.owner] then
                crewStats[a.owner] = { alive = false, damage = 0, kills = 0 }
            end
            local cs = crewStats[a.owner]
            cs.damage = cs.damage + a.damageDealt
            cs.kills  = cs.kills  + a.kills
            if not a.alive then goto nextAtk end
            if not DoesEntityExist(a.ped) or IsEntityDead(a.ped) then
                a.alive = false
                ArenaLabels[a.ped] = nil
                acRemove(a.ped)
                SchedulePedDeath(a.ped)
                goto nextAtk
            end
            cs.alive = true
            a.prevHP = combinedHP(a.ped)
            ::nextAtk::
        end

        if defendersExist then
            for owner, cs in pairs(crewStats) do
                if not cs.alive and not crewEndPending[owner] then
                    crewEndPending[owner] = true
                    local outcome = defendersDead and 'victory' or 'defeat'
                    TriggerEvent('arena:localCrewComplete', owner, cs.damage, cs.kills, outcome)
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Periodic attacker pull-in / re-task
-- • If a ped is far from the arena and not fighting → navigate them toward
--   their zone's approach waypoint so they physically enter the fight.
-- • If they're already close but still not in combat → re-issue the combat
--   task (handles the "task cleared on spawn" edge case).
-- Runs every 1.5 s — frequent enough to catch stuck peds quickly.
-- ---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(1500)
        local ac           = Config.ArenaCenter
        local hasDefenders = next(ActiveDefenders) ~= nil

        for _, a in ipairs(ActiveAttackers) do
            if not a.alive then goto nextRetask end
            if not DoesEntityExist(a.ped) or IsEntityDead(a.ped) then goto nextRetask end
            if IsPedInCombat(a.ped) or IsPedShooting(a.ped) then goto nextRetask end

            do
                local pos  = GetEntityCoords(a.ped)
                local dist = #(pos - ac)

                -- Underground detection: if the ped is more than 3 m below the
                -- surface at their current X/Y, snap them back up.
                local found, groundZ = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 5.0, false)
                if found and pos.z < groundZ - 0.5 then
                    SetEntityCoords(a.ped, pos.x, pos.y, groundZ + 0.1, false, false, false, true)
                    SetEntityOnGroundProperly(a.ped)
                end

                if dist > 45.0 then
                    -- Ped is outside the fight zone — walk them to their approach waypoint.
                    -- TaskCombatHatedTargets will kick in once enemies are in perception range.
                    TaskFollowNavMeshToCoord(a.ped,
                        a.approachX or ac.x,
                        a.approachY or ac.y,
                        ac.z,
                        2.5, -1, 1.0, true, 0.0)
                elseif hasDefenders then
                    -- Already nearby but not engaging — re-issue the combat search task.
                    TaskCombatHatedTargetsInArea(a.ped, ac.x, ac.y, ac.z, 200.0, 0)
                end
            end

            ::nextRetask::
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Attacker idle behaviour (when no defenders exist to fight)
-- Plays world scenarios on standing attackers so they look alive.
-- ---------------------------------------------------------------------------
local ATTACKER_IDLE_SCENARIOS = {
    'WORLD_HUMAN_GUARD_STAND',
    'WORLD_HUMAN_SMOKING',
    'WORLD_HUMAN_STAND_IMPATIENT',
    'WORLD_HUMAN_AA_COFFEE',
}

CreateThread(function()
    while true do
        Wait(8000)
        if next(ActiveDefenders) ~= nil then goto skipIdle end

        for _, a in ipairs(ActiveAttackers) do
            if a.alive and DoesEntityExist(a.ped) and not IsEntityDead(a.ped) then
                if not IsPedInCombat(a.ped) and not IsPedShooting(a.ped) then
                    local scenario = ATTACKER_IDLE_SCENARIOS[math.random(#ATTACKER_IDLE_SCENARIOS)]
                    TaskStartScenarioInPlace(a.ped, scenario, 0, true)
                end
            end
        end

        ::skipIdle::
    end
end)

-- ---------------------------------------------------------------------------
-- Defender Behavior System
-- ---------------------------------------------------------------------------
local IDLE_POOL = {
    { type = 'scenario', name = 'WORLD_HUMAN_GUARD_STAND',      weight = 4 },
    { type = 'scenario', name = 'WORLD_HUMAN_GUARD_STAND_ARMY', weight = 3 },
    { type = 'wander',                                           weight = 2 },
    { type = 'scenario', name = 'WORLD_HUMAN_SMOKING',          weight = 2 },
    { type = 'scenario', name = 'WORLD_HUMAN_AA_COFFEE',        weight = 1 },
    { type = 'scenario', name = 'WORLD_HUMAN_BINOCULARS',       weight = 1 },
}

local _idleWeighted = (function()
    local t = {}
    for _, entry in ipairs(IDLE_POOL) do
        for _ = 1, entry.weight do t[#t + 1] = entry end
    end
    return t
end)()

local function pickIdleBehavior() return _idleWeighted[math.random(#_idleWeighted)] end

local function isWaveActive()
    for _, a in ipairs(ActiveAttackers) do if a.alive then return true end end
    return false
end

local function distFromHome(d)
    if not DoesEntityExist(d.ped) then return 0 end
    return #(GetEntityCoords(d.ped) - d.homePos)
end

local function startIdle(d)
    local behavior = pickIdleBehavior()
    local cfg      = Config.DefenderIdleChangeMs
    ClearPedTasks(d.ped)
    if behavior.type == 'wander' then
        local angle = math.random() * math.pi * 2
        local r     = Config.DefenderWanderRadius * math.random()
        TaskFollowNavMeshToCoord(d.ped, d.homePos.x + math.cos(angle)*r, d.homePos.y + math.sin(angle)*r, d.homePos.z, 1.0, 8000, 0.5, false, 0.0)
        d.idleTimer = GetGameTimer() + 6000
    else
        SetEntityHeading(d.ped, d.homeHead)
        TaskStartScenarioInPlace(d.ped, behavior.name, 0, true)
        d.idleTimer = GetGameTimer() + math.random(cfg.min, cfg.max)
    end
    d.state = 'idle'
end

local function driveHome(d, speed)
    TaskFollowNavMeshToCoord(d.ped, d.homePos.x, d.homePos.y, d.homePos.z, speed or 1.5, 3000, 1.0, true, 0.0)
end

CreateThread(function()
    while true do
        Wait(1000)
        local waveActive = isWaveActive()
        local now        = GetGameTimer()
        local ac         = Config.ArenaCenter

        for _, d in pairs(ActiveDefenders) do
            if not d.alive then goto nextBeh end
            if not DoesEntityExist(d.ped) or IsEntityDead(d.ped) then goto nextBeh end
            if d.converted then goto nextBeh end  -- converted peds handle their own AI

            local dist = distFromHome(d)

            if waveActive then
                d.state = 'combat'
            else
                if d.state == 'returning' then
                    if dist < Config.DefenderReturnDist then
                        SetEntityHeading(d.ped, d.homeHead)
                        startIdle(d)
                    else
                        driveHome(d, 1.5)
                    end
                elseif dist > Config.DefenderReturnDist then
                    d.state = 'returning'
                    ClearPedTasksImmediately(d.ped)
                    driveHome(d, 1.5)
                else
                    if d.state ~= 'idle' or now >= d.idleTimer then
                        startIdle(d)
                    end
                end
            end
            ::nextBeh::
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Bridge local event → server
-- ---------------------------------------------------------------------------
AddEventHandler('arena:localCrewComplete', function(owner, damage, kills, outcome)
    crewEndPending[owner] = nil
    TriggerServerEvent('arena:crewComplete', {
        owner       = owner,
        damageDealt = damage,
        kills       = kills,
        outcome     = outcome,
    })

    -- Only respawn original defenders when nobody is filling the role via conversion
    if outcome == 'victory' and Config.DefenderRespawnEnabled and not convertedOwner then
        CreateThread(function()
            Wait(Config.DefenderRespawnDelay * 1000)
            SpawnDefenders()
            TriggerServerEvent('arena:defendersRespawned')
        end)
    end

    CreateThread(function()
        Wait(4000)
        ClearCrewByOwner(owner)
    end)
end)
