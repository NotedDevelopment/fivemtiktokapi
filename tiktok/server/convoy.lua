-- =============================================================================
-- Convoy Gamemode — Server
-- Manages viewer attacker waves, outcome handling, and admin commands.
-- =============================================================================

local ConvoyServerState = {
    running      = false,
    activeCrews  = {},   -- [username] = { colorIndex }
    viewerColors = {},   -- [username] = colorIndex (persistent)
    nextColor    = 1,
}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function isAdmin(source)
    if Config.TestMode then return true end
    return source == 0 or IsPlayerAceAllowed(source, 'tiktok.admin')
end

local function notify(source, msg, ntype)
    if source <= 0 then print('[Convoy] ' .. msg); return end
    TriggerClientEvent('ox_lib:notify', source, { title = 'Convoy', description = msg, type = ntype or 'inform' })
end

local function broadcast(msg, ntype)
    TriggerClientEvent('ox_lib:notify', -1, { title = 'Convoy', description = msg, type = ntype or 'inform' })
end

local function assignColor(username)
    if not ConvoyServerState.viewerColors[username] then
        ConvoyServerState.viewerColors[username] = ConvoyServerState.nextColor
        ConvoyServerState.nextColor = (ConvoyServerState.nextColor % #Config.ViewerColors) + 1
    end
    return ConvoyServerState.viewerColors[username]
end

local function firstPlayer()
    for _, pid in ipairs(GetPlayers()) do return GetPlayerName(pid) end
    return nil
end

-- ─── Viewer Commands ──────────────────────────────────────────────────────────

-- /attackconvoy — spend points to send an attacker vehicle
RegisterCommand('attackconvoy', function(source, args)
    if source == 0 then return end
    if not ConvoyServerState.running then
        notify(source, 'No convoy is active.', 'error'); return
    end
    local username = GetPlayerName(source)
    CreateThread(function()
        local viewer = DB.getOrCreateViewer(username)

        if ConvoyServerState.activeCrews[username] then
            notify(source, 'Your attacker vehicle is still active.', 'error'); return
        end

        local tier    = 1
        local tierCfg = Config.Tiers[tier]
        local cost    = tierCfg.cost * 2  -- vehicles cost 2× normal wave cost

        if viewer.points < cost then
            notify(source, ('Need %d pts (have %d).'):format(cost, viewer.points), 'error'); return
        end

        DB.addPoints(username, -cost)
        local colorIndex = assignColor(username)
        ConvoyServerState.activeCrews[username] = { colorIndex = colorIndex }

        TriggerClientEvent('convoy:spawnAttackers', -1, {
            owner      = username,
            colorIndex = colorIndex,
            tier       = tier,
            count      = 3,
        })
        notify(source, 'Attacker vehicle sent!', 'success')
        broadcast(username .. ' sent an attacker vehicle!', 'inform')
    end)
end)

-- ─── Admin Commands ───────────────────────────────────────────────────────────

RegisterCommand('convoystart', function(source)
    if not isAdmin(source) then notify(source, 'No permission.', 'error'); return end
    ConvoyServerState.running     = true
    ConvoyServerState.activeCrews = {}
    TriggerClientEvent('convoy:start', -1)
    notify(source, 'Convoy started.', 'success')
end, false)

RegisterCommand('convoystop', function(source)
    if not isAdmin(source) then notify(source, 'No permission.', 'error'); return end
    ConvoyServerState.running     = false
    ConvoyServerState.activeCrews = {}
    TriggerClientEvent('convoy:stop', -1)
    notify(source, 'Convoy stopped.', 'success')
end, false)

-- convoyattack <tier 1-4> [username]  — force-spawn an attacker vehicle
RegisterCommand('convoyattack', function(source, args)
    if not isAdmin(source) then notify(source, 'No permission.', 'error'); return end
    if not ConvoyServerState.running then notify(source, 'No convoy running.', 'error'); return end

    local tier = tonumber(args[1])
    if not tier or not Config.Tiers[tier] then
        notify(source, 'Usage: convoyattack <tier 1-4> [username]', 'error'); return
    end
    local username   = args[2] or firstPlayer()
    if not username then notify(source, 'No players connected.', 'error'); return end
    local colorIndex = assignColor(username)

    ConvoyServerState.activeCrews[username] = { colorIndex = colorIndex }
    TriggerClientEvent('convoy:spawnAttackers', -1, {
        owner      = username,
        colorIndex = colorIndex,
        tier       = tier,
        count      = 4,
    })
    notify(source, ('Force-spawned tier %d attacker for %s.'):format(tier, username), 'success')
end, false)

-- convoystate — show current state
RegisterCommand('convoystate', function(source)
    if not isAdmin(source) then return end
    local crews = {}
    for u in pairs(ConvoyServerState.activeCrews) do crews[#crews + 1] = u end
    local crewStr = #crews > 0 and table.concat(crews, ', ') or 'none'
    notify(source, ('Running: %s | Active attackers: %s'):format(
        tostring(ConvoyServerState.running), crewStr), 'inform')
end, false)

-- ─── Outcome Events (fired by client) ────────────────────────────────────────

RegisterNetEvent('convoy:vipArrived', function()
    ConvoyServerState.running     = false
    ConvoyServerState.activeCrews = {}
    broadcast('CONVOY SUCCESS — VIP reached the destination!', 'success')
    print('[Convoy] VIP arrived.')
end)

RegisterNetEvent('convoy:vipDestroyed', function()
    ConvoyServerState.running     = false
    ConvoyServerState.activeCrews = {}
    broadcast('CONVOY FAILED — VIP vehicle was destroyed!', 'error')
    print('[Convoy] VIP destroyed.')
end)

-- ─── Test Menu Net Events ─────────────────────────────────────────────────────

RegisterNetEvent('convoy:admin:start', function()
    local source = source
    if not isAdmin(source) then return end
    ConvoyServerState.running     = true
    ConvoyServerState.activeCrews = {}
    TriggerClientEvent('convoy:start', -1)
end)

RegisterNetEvent('convoy:admin:stop', function()
    local source = source
    if not isAdmin(source) then return end
    ConvoyServerState.running     = false
    ConvoyServerState.activeCrews = {}
    TriggerClientEvent('convoy:stop', -1)
end)

RegisterNetEvent('convoy:admin:forceAttack', function(tier)
    local source   = source
    if not isAdmin(source) then return end
    if not ConvoyServerState.running then return end
    local username   = GetPlayerName(source)
    local colorIndex = assignColor(username)
    ConvoyServerState.activeCrews[username] = { colorIndex = colorIndex }
    TriggerClientEvent('convoy:spawnAttackers', -1, {
        owner      = username,
        colorIndex = colorIndex,
        tier       = tier or 1,
        count      = 4,
    })
end)
