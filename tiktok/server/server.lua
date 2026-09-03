-- =============================================================================
-- Game state
-- =============================================================================
local State = {
    running           = false,
    activeCrews       = {},   -- [username] = waveData currently active
    viewerZones       = {},   -- [username] = zoneIndex (assigned once, persists)
    viewerColors      = {},   -- [username] = colorIndex (assigned once, persists)
    viewerSpawnSpots  = {},   -- [username] = {x,y}  reset each time a crew is wiped
    defenderOwner     = nil,  -- username whose peds are currently defending, or nil
    nextZone          = 1,
    nextColor         = 1,
    lastWaveTime      = 0,    -- GetGameTimer() ms when the last wave was dispatched
}

-- =============================================================================
-- Helpers
-- =============================================================================
local function isAdmin(source)
    if Config.TestMode then return true end
    return source == 0 or IsPlayerAceAllowed(source, 'tiktok.admin')
end

local function notify(source, msg, ntype)
    if source <= 0 then print('[Arena] ' .. msg); return end
    TriggerClientEvent('ox_lib:notify', source, { title = 'Arena', description = msg, type = ntype or 'inform' })
end

local function broadcast(msg, ntype)
    TriggerClientEvent('ox_lib:notify', -1, { title = 'Arena', description = msg, type = ntype or 'inform' })
end

-- Assign a zone to a viewer — same viewer always gets the same zone.
local function assignZone(username)
    if not State.viewerZones[username] then
        State.viewerZones[username] = State.nextZone
        State.nextZone = (State.nextZone % #Config.SpawnZones) + 1
    end
    return State.viewerZones[username]
end

-- Pick (or reuse) a random sub-point within the viewer's zone.
-- A new point is generated the first time and after each crew wipe.
local function assignSpawnSpot(username, zoneIndex)
    if State.viewerSpawnSpots[username] then
        return State.viewerSpawnSpots[username]
    end
    local zone  = Config.SpawnZones[zoneIndex]
    local r     = Config.SpawnZoneSubRadius * math.sqrt(math.random())  -- uniform in disc
    local angle = math.random() * math.pi * 2
    local spot  = {
        x = zone.spawn.x + math.cos(angle) * r,
        y = zone.spawn.y + math.sin(angle) * r,
    }
    State.viewerSpawnSpots[username] = spot
    return spot
end

-- Assign a display color to a viewer — persists for the session.
local function assignColor(username)
    if not State.viewerColors[username] then
        State.viewerColors[username] = State.nextColor
        State.nextColor = (State.nextColor % #Config.ViewerColors) + 1
    end
    return State.viewerColors[username]
end

-- =============================================================================
-- VIEWER COMMANDS
-- =============================================================================

-- /sendwave — spend all current points on a wave
RegisterCommand('sendwave', function(source, args)
    if source == 0 then return end
    local username = GetPlayerName(source)

    CreateThread(function()
        local viewer = DB.getOrCreateViewer(username)

        if State.activeCrews[username] then
            notify(source, 'Your crew is still active — wait for them to fall.', 'error'); return
        end

        local minCost = Config.Tiers[1].cost
        if viewer.points < minCost then
            notify(source, ('Not enough points (need %d, have %d).'):format(minCost, viewer.points), 'error'); return
        end

        local result = Waves.calculateComposition(viewer.points)
        if result.totalPeds == 0 then
            notify(source, 'Could not build a wave from your points.', 'error'); return
        end

        DB.addPoints(username, -result.totalCost)
        local waveId     = DB.recordViewerWave(username, result.composition, result.totalCost)
        local colorIndex = assignColor(username)
        local zoneIndex  = assignZone(username)
        local spot       = assignSpawnSpot(username, zoneIndex)

        local isReinforcement = (State.defenderOwner == username)
        local waveData = {
            waveId          = waveId,
            owner           = username,
            composition     = result.composition,
            totalCost       = result.totalCost,
            colorIndex      = colorIndex,
            zoneIndex       = zoneIndex,
            spawnX          = spot.x,
            spawnY          = spot.y,
            isReinforcement = isReinforcement,
        }

        State.activeCrews[username] = waveData
        State.lastWaveTime = GetGameTimer()
        TriggerClientEvent('arena:spawnWave', -1, waveData)

        local tag = isReinforcement and ' [REINFORCEMENT]' or ''
        notify(source, 'Wave sent! ' .. Waves.describeWave(result) .. tag, 'success')
        broadcast(username .. ' sent a wave: ' .. Waves.describeWave(result) .. tag, 'inform')
    end)
end)

-- /mystats [username]   — works from console and in-game
RegisterCommand('mystats', function(source, args)
    local username = args[1]
    if not username then
        if source > 0 then
            username = GetPlayerName(source)
        else
            print('[Arena] Usage: mystats <username>'); return
        end
    end
    CreateThread(function()
        local v = DB.getOrCreateViewer(username)
        local zone = State.viewerZones[username] and Config.SpawnZones[State.viewerZones[username]] or nil
        local zoneLabel = zone and zone.label or 'unassigned'
        notify(source,
            ('%s — Points: %d | Damage: %d | Kills: %d | Waves: %d | Zone: %s')
            :format(username, v.points, v.total_damage, v.total_kills, v.waves_sent, zoneLabel),
            'inform')
    end)
end)

-- =============================================================================
-- ADMIN COMMANDS
-- All work from the server console (source == 0) and in-game if isAdmin.
--
--   spawndefenders
--   resetgame
--   cleardefenders
--   clearattackers
--   addpoints   <username> <amount>
--   simlike     <username> [count=1]
--   simgift     <username> [count=1]
--   forcewave   <tier 1-4> [username]
--   mystats     [username]
--   arenastate
-- =============================================================================

local function firstPlayer()
    for _, pid in ipairs(GetPlayers()) do
        return GetPlayerName(pid)
    end
    return nil
end

RegisterCommand('spawndefenders', function(source)
    if not isAdmin(source) then notify(source, 'No permission.', 'error'); return end
    TriggerClientEvent('arena:spawnDefenders', -1)
    State.running = true
    notify(source, 'Defenders spawned.', 'success')
end, false)

RegisterCommand('resetgame', function(source)
    if not isAdmin(source) then notify(source, 'No permission.', 'error'); return end
    TriggerClientEvent('arena:resetGame', -1)
    State.running          = false
    State.activeCrews      = {}
    State.viewerSpawnSpots = {}
    State.defenderOwner    = nil
    notify(source, 'Game reset.', 'success')
end, false)

RegisterCommand('cleardefenders', function(source)
    if not isAdmin(source) then notify(source, 'No permission.', 'error'); return end
    TriggerClientEvent('arena:clearDefenders', -1)
    notify(source, 'Defenders cleared.', 'success')
end, false)

RegisterCommand('clearattackers', function(source)
    if not isAdmin(source) then notify(source, 'No permission.', 'error'); return end
    TriggerClientEvent('arena:clearAttackers', -1)
    State.activeCrews = {}
    notify(source, 'Attackers cleared.', 'success')
end, false)

-- addpoints <username> <amount>
RegisterCommand('addpoints', function(source, args)
    if not isAdmin(source) then notify(source, 'No permission.', 'error'); return end
    local target = args[1]
    local amount = tonumber(args[2])
    if not target or not amount then
        notify(source, 'Usage: addpoints <username> <amount>', 'error'); return
    end
    CreateThread(function()
        DB.getOrCreateViewer(target)
        DB.addPoints(target, amount)
        notify(source, ('Added %d pts to %s.'):format(amount, target), 'success')
    end)
end, false)

-- simlike <username> [count=1]
RegisterCommand('simlike', function(source, args)
    if not isAdmin(source) then notify(source, 'No permission.', 'error'); return end
    local username = args[1] or firstPlayer()
    if not username then notify(source, 'No players connected.', 'error'); return end
    local count = tonumber(args[2]) or 1
    CreateThread(function()
        DB.getOrCreateViewer(username)
        DB.addPoints(username, Config.Points.perLike * count)
        notify(source, ('Simulated %d likes for %s (+%d pts).'):format(count, username, Config.Points.perLike * count), 'success')
    end)
end, false)

-- simgift <username> [count=1]
RegisterCommand('simgift', function(source, args)
    if not isAdmin(source) then notify(source, 'No permission.', 'error'); return end
    local username = args[1] or firstPlayer()
    if not username then notify(source, 'No players connected.', 'error'); return end
    local count = tonumber(args[2]) or 1
    CreateThread(function()
        DB.getOrCreateViewer(username)
        DB.addPoints(username, Config.Points.perGift * count)
        notify(source, ('Simulated %d gift(s) for %s (+%d pts).'):format(count, username, Config.Points.perGift * count), 'success')
    end)
end, false)

-- forcewave <tier 1-4> [username]
RegisterCommand('forcewave', function(source, args)
    if not isAdmin(source) then notify(source, 'No permission.', 'error'); return end
    local tier = tonumber(args[1])
    if not tier then
        notify(source, 'Usage: forcewave <tier 1-4> [username]', 'error'); return
    end
    local username = args[2] or firstPlayer()
    if not username then notify(source, 'No players connected.', 'error'); return end

    CreateThread(function()
        DB.getOrCreateViewer(username)
        if State.activeCrews[username] then
            notify(source, username .. '\'s crew is already active.', 'error'); return
        end
        local tierCfg = Config.Tiers[tier]
        if not tierCfg then notify(source, 'Invalid tier (1–4).', 'error'); return end

        local isReinforcement = (State.defenderOwner == username)
        local composition = { { tier = tier, tierName = tierCfg.name, count = 3 } }
        local waveId     = DB.recordViewerWave(username, composition, 0)
        local colorIndex = assignColor(username)
        local zoneIndex  = assignZone(username)
        local spot       = assignSpawnSpot(username, zoneIndex)

        local waveData = {
            waveId          = waveId,
            owner           = username,
            composition     = composition,
            totalCost       = 0,
            colorIndex      = colorIndex,
            zoneIndex       = zoneIndex,
            spawnX          = spot.x,
            spawnY          = spot.y,
            isReinforcement = isReinforcement,
        }

        State.activeCrews[username] = waveData
        State.lastWaveTime = GetGameTimer()
        TriggerClientEvent('arena:spawnWave', -1, waveData)
        local tag = isReinforcement and ' [REINFORCEMENT]' or ''
        notify(source, ('Force wave: 3× %s for %s (%s)%s'):format(tierCfg.name, username, Config.SpawnZones[zoneIndex].label, tag), 'success')
    end)
end, false)

-- arenastate
RegisterCommand('arenastate', function(source)
    if not isAdmin(source) then return end
    local crewList = {}
    for u in pairs(State.activeCrews) do crewList[#crewList + 1] = u end
    local crewStr   = #crewList > 0 and table.concat(crewList, ', ') or 'none'
    local defOwner  = State.defenderOwner or 'static'
    notify(source, ('Running: %s | Defender: %s | Active crews: %s'):format(tostring(State.running), defOwner, crewStr), 'inform')
end, false)

-- arenaview [x y z]  — starts action cam with tiktok arena venue cameras
RegisterCommand('arenaview', function(source, args)
    if not isAdmin(source) then return end
    local opts = { venueCams = Config.ArenaCameras }
    if args[1] and args[2] and args[3] then
        opts.center = { x = tonumber(args[1]), y = tonumber(args[2]), z = tonumber(args[3]) }
    end
    TriggerClientEvent('actioncam:start', -1, opts)
    if source == 0 then print('[Arena] Action cam started.') end
end, false)

RegisterCommand('arenaviewstop', function(source)
    if not isAdmin(source) then return end
    TriggerClientEvent('actioncam:stop', -1)
    if source == 0 then print('[Arena] Action cam stopped.') end
end, false)

-- =============================================================================
-- AUTO-BOT — spawns a CPU wave when no players are sending attackers
-- =============================================================================
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(Config.AutoBotInterval * 1000)

        if not Config.AutoBotEnabled   then goto autoBotNext end
        if not State.running           then goto autoBotNext end
        if next(State.activeCrews) ~= nil then goto autoBotNext end

        -- Check inactivity: last wave must be older than the interval
        local msSince = GetGameTimer() - State.lastWaveTime
        if msSince < Config.AutoBotInterval * 1000 then goto autoBotNext end

        do
            local username = Config.AutoBotOwner
            local tier     = Config.AutoBotTier
            local tierCfg  = Config.Tiers[tier]
            if not tierCfg then goto autoBotNext end

            DB.getOrCreateViewer(username)

            local composition = { { tier = tier, tierName = tierCfg.name, count = Config.AutoBotCount } }
            local waveId      = DB.recordViewerWave(username, composition, 0)
            local colorIndex  = assignColor(username)
            local zoneIndex   = assignZone(username)
            local spot        = assignSpawnSpot(username, zoneIndex)

            local waveData = {
                waveId      = waveId,
                owner       = username,
                composition = composition,
                totalCost   = 0,
                colorIndex  = colorIndex,
                zoneIndex   = zoneIndex,
                spawnX      = spot.x,
                spawnY      = spot.y,
            }

            State.activeCrews[username] = waveData
            State.lastWaveTime = GetGameTimer()
            TriggerClientEvent('arena:spawnWave', -1, waveData)
            print('[Arena] Auto-bot wave spawned (' .. username .. ').')
        end

        ::autoBotNext::
    end
end)

-- =============================================================================
-- CREW OUTCOME — triggered by client when a viewer's crew is wiped out
-- =============================================================================
RegisterNetEvent('arena:crewComplete', function(data)
    -- data = { owner, damageDealt, kills, outcome }
    local wave = State.activeCrews[data.owner]
    if not wave then return end

    State.activeCrews[data.owner]      = nil
    State.viewerSpawnSpots[data.owner] = nil

    -- Victory: winner's peds become the new defenders
    if data.outcome == 'victory' then
        State.defenderOwner = data.owner
        TriggerClientEvent('arena:convertCrewToDefenders', -1, data.owner)
    end

    CreateThread(function()
        DB.finaliseWave(wave.waveId, data.damageDealt, data.kills, data.outcome)
        DB.updateViewerStats(wave.owner, data.damageDealt, data.kills)

        -- Performance mode: reward attacker based on damage
        if Config.GrowthMode == 'performance' then
            local bonus = math.floor(data.damageDealt * Config.Points.perDamageDealt)
                        + data.kills * Config.Points.perKill
            if bonus > 0 then DB.addPoints(wave.owner, bonus) end
        end

        -- Notify all clients so the UI can update
        TriggerClientEvent('arena:crewEnded', -1, {
            owner       = wave.owner,
            damageDealt = data.damageDealt,
            kills       = data.kills,
            outcome     = data.outcome,
            colorIndex  = wave.colorIndex,
        })

        local outcomeStr = data.outcome == 'victory' and 'VICTORY' or 'DEFEAT'
        broadcast(('[%s] crew ended — %s | %d dmg | %d kills'):format(
            wave.owner, outcomeStr, data.damageDealt, data.kills))
    end)
end)

-- Defenders respawned — client tells server
RegisterNetEvent('arena:defendersRespawned', function()
    State.running = true
end)

-- =============================================================================
-- TIKTOK API STUBS
-- =============================================================================

RegisterNetEvent('arena:processLike', function(username)
    CreateThread(function()
        DB.getOrCreateViewer(username)
        DB.addPoints(username, Config.Points.perLike)
    end)
end)

RegisterNetEvent('arena:processGift', function(username, giftCoins)
    CreateThread(function()
        DB.getOrCreateViewer(username)
        DB.addPoints(username, Config.Points.perGift * (giftCoins or 1))
    end)
end)

RegisterNetEvent('arena:processMessage', function(username, message)
    -- parse viewer commands here in the future
end)

-- =============================================================================
-- TEST MENU NET EVENT RELAYS
-- These back the /testmenu ox_lib UI.
-- =============================================================================

RegisterNetEvent('arena:admin:cmd', function(cmd)
    local source = source
    if not isAdmin(source) then return end
    if cmd == 'spawndefenders' then
        TriggerClientEvent('arena:spawnDefenders', -1)
        State.running = true
    elseif cmd == 'resetgame' then
        TriggerClientEvent('arena:resetGame', -1)
        State.running          = false
        State.activeCrews      = {}
        State.viewerSpawnSpots = {}
        State.defenderOwner    = nil
    end
end)

RegisterNetEvent('arena:admin:addpoints', function(target, amount)
    local source = source
    if not isAdmin(source) then return end
    CreateThread(function()
        DB.getOrCreateViewer(target)
        DB.addPoints(target, amount)
        notify(source, ('Added %d pts to %s.'):format(amount, target), 'success')
    end)
end)

RegisterNetEvent('arena:requestMyStats', function()
    local source   = source
    local username = GetPlayerName(source)
    CreateThread(function()
        local v        = DB.getOrCreateViewer(username)
        local zone     = State.viewerZones[username] and Config.SpawnZones[State.viewerZones[username]] or nil
        local zoneLabel = zone and zone.label or 'unassigned'
        notify(source,
            ('%s — Points: %d | Damage: %d | Kills: %d | Waves: %d | Zone: %s')
            :format(username, v.points, v.total_damage, v.total_kills, v.waves_sent, zoneLabel),
            'inform')
    end)
end)

RegisterNetEvent('arena:test:forceWave', function(tier)
    local source   = source
    if not isAdmin(source) then return end
    local username = GetPlayerName(source)

    CreateThread(function()
        DB.getOrCreateViewer(username)

        if State.activeCrews[username] then
            notify(source, 'Your crew is already active.', 'error'); return
        end

        local tierCfg = Config.Tiers[tier]
        if not tierCfg then notify(source, 'Invalid tier.', 'error'); return end

        local isReinforcement = (State.defenderOwner == username)
        local composition     = { { tier = tier, tierName = tierCfg.name, count = 3 } }
        local waveId          = DB.recordViewerWave(username, composition, 0)
        local colorIndex      = assignColor(username)
        local zoneIndex       = assignZone(username)
        local spot            = assignSpawnSpot(username, zoneIndex)

        local waveData = {
            waveId          = waveId,
            owner           = username,
            composition     = composition,
            totalCost       = 0,
            colorIndex      = colorIndex,
            zoneIndex       = zoneIndex,
            spawnX          = spot.x,
            spawnY          = spot.y,
            isReinforcement = isReinforcement,
        }

        State.activeCrews[username] = waveData
        State.lastWaveTime          = GetGameTimer()
        TriggerClientEvent('arena:spawnWave', -1, waveData)
        notify(source, ('Test wave: 3× %s for %s (%s)'):format(
            tierCfg.name, username, Config.SpawnZones[zoneIndex].label), 'success')
    end)
end)

