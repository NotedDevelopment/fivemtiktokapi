-- =============================================================================
-- LMS Server
-- =============================================================================

local State = {
    running         = false,
    nextColor       = 1,
    nextZone        = 1,
    viewers         = {},   -- active viewers (removed 30 s after elimination)
    session         = {},   -- all-time this game session (never removed until lmsreset)
    likeAccumulator = {},   -- pending like counts per username before ped threshold
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function ensureViewer(username)
    if not State.viewers[username] then
        local ci = State.nextColor
        local zi = State.nextZone
        State.viewers[username] = { colorIndex = ci, zoneIndex = zi, points = 0 }
        State.nextColor = (State.nextColor % #Config.ViewerColors) + 1
        State.nextZone  = (State.nextZone  % #Config.SpawnZones)  + 1
    end
    if not State.session[username] then
        State.session[username] = {
            colorIndex = State.viewers[username].colorIndex,
            points     = 0,
        }
    end
end

local function broadcastLeaderboard()
    local lb = {}
    for username, v in pairs(State.session) do
        lb[#lb + 1] = { owner = username, points = v.points, colorIndex = v.colorIndex }
    end
    table.sort(lb, function(a, b) return a.points > b.points end)
    TriggerClientEvent('lms:updateLeaderboard', -1, lb)
end

local function buildSpawnPayload(username, npcCfg)
    local v = State.viewers[username]
    return {
        owner      = username,
        colorIndex = v.colorIndex,
        zoneIndex  = v.zoneIndex,
        model      = npcCfg.models[math.random(#npcCfg.models)],
        weapon     = npcCfg.weapon,
        health     = npcCfg.health,
        armor      = npcCfg.armor,
        accuracy   = npcCfg.accuracy,
        tierName   = npcCfg.tierName,
        points     = npcCfg.points or 1,
    }
end

-- ---------------------------------------------------------------------------
-- Start / stop
-- ---------------------------------------------------------------------------
RegisterNetEvent('lms:start', function()
    if State.running then return end
    State.running = true
    TriggerClientEvent('lms:camStart', -1, {
        center    = { x = Config.ArenaCenter.x, y = Config.ArenaCenter.y, z = Config.ArenaCenter.z },
        venueCams = Config.ArenaCameras,
    })
    print('[LMS] Game started')
end)

RegisterNetEvent('lms:reset', function()
    State.running         = false
    State.viewers         = {}
    State.session         = {}
    State.nextColor       = 1
    State.nextZone        = 1
    State.likeAccumulator = {}
    TriggerClientEvent('lms:resetGame', -1)
    TriggerClientEvent('lms:camStop', -1)
    print('[LMS] Game reset')
end)

-- ---------------------------------------------------------------------------
-- TikTok events
-- ---------------------------------------------------------------------------
RegisterNetEvent('lms:like', function(username)
    if not State.running then return end
    ensureViewer(username)
    broadcastLeaderboard()
    TriggerClientEvent('lms:spawnNpc', -1, buildSpawnPayload(username, Config.LikeNpc))
end)

-- Accumulate likes from tiktokapi; spawn one LikeNpc per Config.LikesPerPed likes
AddEventHandler('tiktokapi:like', function(jsonData)
    if not State.running then return end
    local data = json.decode(jsonData)
    if not data then return end
    local username = data.uniqueId or data.nickname or 'unknown'
    State.likeAccumulator[username] = (State.likeAccumulator[username] or 0) + (data.likeCount or 1)
    while State.likeAccumulator[username] >= Config.LikesPerPed do
        State.likeAccumulator[username] = State.likeAccumulator[username] - Config.LikesPerPed
        ensureViewer(username)
        TriggerClientEvent('lms:spawnNpc', -1, buildSpawnPayload(username, Config.LikeNpc))
    end
    broadcastLeaderboard()
end)

RegisterNetEvent('lms:donation', function(username, coins)
    if not State.running then return end
    ensureViewer(username)
    broadcastLeaderboard()
    local tier = Config.DonationTiers[1]
    for _, t in ipairs(Config.DonationTiers) do
        if coins >= t.minCoins and coins <= t.maxCoins then tier = t; break end
    end
    TriggerClientEvent('lms:spawnNpc', -1, buildSpawnPayload(username, tier))
end)

-- ---------------------------------------------------------------------------
-- Kill / point reporting (from client)
-- ---------------------------------------------------------------------------
RegisterNetEvent('lms:reportKill', function(killerName, pts)
    if not killerName or killerName == '' then return end
    pts = tonumber(pts) or 1
    if State.viewers[killerName] then
        State.viewers[killerName].points = State.viewers[killerName].points + pts
    end
    if State.session[killerName] then
        State.session[killerName].points = State.session[killerName].points + pts
    end
    broadcastLeaderboard()
end)

RegisterNetEvent('lms:crewEliminated', function(owner, killerName)
    TriggerClientEvent('lms:showElimination', -1, { owner = owner, killer = killerName })
    print(('[LMS] %s\'s crew was wiped by %s'):format(owner, killerName or 'nobody'))

    SetTimeout(30000, function()
        if State.viewers[owner] then
            State.viewers[owner] = nil
            -- session entry is intentionally kept for Session Top 5
        end
    end)
end)

-- ---------------------------------------------------------------------------
-- Admin commands
-- ---------------------------------------------------------------------------
RegisterCommand('lmsstart', function()
    TriggerEvent('lms:start')
end, true)

RegisterCommand('lmsreset', function()
    TriggerEvent('lms:reset')
end, true)

RegisterCommand('lmslike', function(_, args)
    local name = args[1] or 'TestViewer'
    TriggerEvent('lms:like', name)
end, true)

RegisterCommand('lmsdonate', function(_, args)
    local name  = args[1] or 'TestViewer'
    local coins = tonumber(args[2]) or 10
    TriggerEvent('lms:donation', name, coins)
end, true)
