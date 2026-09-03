-- =============================================================================
-- Test Menu  (ox_lib context menus)
-- Open with /testmenu  — only works when Config.TestMode = true
-- =============================================================================

local myName = GetPlayerName(PlayerId())

-- ---------------------------------------------------------------------------
-- Sub-menus
-- ---------------------------------------------------------------------------
lib.registerContext({
    id    = 'arena_menu_game',
    title = 'Game Management',
    options = {
        {
            title       = 'Spawn Defenders',
            description = 'Places the defending team at their config positions.',
            icon        = 'shield',
            onSelect    = function()
                TriggerServerEvent('arena:admin:cmd', 'spawndefenders')
            end,
        },
        {
            title       = 'Reset Game',
            description = 'Clears all peds and resets state.',
            icon        = 'rotate-left',
            onSelect    = function()
                TriggerServerEvent('arena:admin:cmd', 'resetgame')
            end,
        },
        {
            title       = 'Clear Defenders Only',
            description = 'Deletes defender peds without resetting state.',
            icon        = 'trash',
            onSelect    = function()
                ClearDefenders()
            end,
        },
        {
            title       = 'Clear Attackers Only',
            description = 'Deletes all active attacker peds.',
            icon        = 'trash',
            onSelect    = function()
                ClearAttackers()
            end,
        },
    },
})

lib.registerContext({
    id    = 'arena_menu_interactions',
    title = 'Simulate Interactions',
    options = {
        {
            title       = 'Simulate 10 Likes (me)',
            description = ('+%d pts'):format(Config.Points.perLike * 10),
            icon        = 'heart',
            onSelect    = function()
                for _ = 1, 10 do TriggerServerEvent('arena:processLike', myName) end
                lib.notify({ title = 'Arena', description = 'Simulated 10 likes', type = 'success' })
            end,
        },
        {
            title       = 'Simulate 50 Likes (me)',
            description = ('+%d pts'):format(Config.Points.perLike * 50),
            icon        = 'fire',
            onSelect    = function()
                for _ = 1, 50 do TriggerServerEvent('arena:processLike', myName) end
                lib.notify({ title = 'Arena', description = 'Simulated 50 likes', type = 'success' })
            end,
        },
        {
            title       = 'Simulate Gift ×1 (me)',
            description = ('+%d pts'):format(Config.Points.perGift),
            icon        = 'gift',
            onSelect    = function()
                TriggerServerEvent('arena:processGift', myName, 1)
                lib.notify({ title = 'Arena', description = 'Simulated gift ×1', type = 'success' })
            end,
        },
        {
            title       = 'Simulate Gift ×10 (me)',
            description = ('+%d pts'):format(Config.Points.perGift * 10),
            icon        = 'star',
            onSelect    = function()
                TriggerServerEvent('arena:processGift', myName, 10)
                lib.notify({ title = 'Arena', description = 'Simulated gift ×10', type = 'success' })
            end,
        },
    },
})

lib.registerContext({
    id    = 'arena_menu_points',
    title = 'Point Management',
    options = {
        {
            title    = 'Add 100 pts (me)',
            icon     = 'plus',
            onSelect = function() TriggerServerEvent('arena:admin:addpoints', myName, 100) end,
        },
        {
            title    = 'Add 500 pts (me)',
            icon     = 'plus',
            onSelect = function() TriggerServerEvent('arena:admin:addpoints', myName, 500) end,
        },
        {
            title    = 'Add 2000 pts (me)',
            icon     = 'plus',
            onSelect = function() TriggerServerEvent('arena:admin:addpoints', myName, 2000) end,
        },
    },
})

lib.registerContext({
    id    = 'arena_menu_waves',
    title = 'Wave Testing',
    options = {
        {
            title       = 'Force Tier 1 Wave (me)',
            description = 'Spawns 3× Grunt for you — no cost.',
            icon        = 'person',
            onSelect    = function() TriggerServerEvent('arena:test:forceWave', 1) end,
        },
        {
            title       = 'Force Tier 2 Wave (me)',
            description = 'Spawns 3× Soldier for you — no cost.',
            icon        = 'person-military-rifle',
            onSelect    = function() TriggerServerEvent('arena:test:forceWave', 2) end,
        },
        {
            title       = 'Force Tier 3 Wave (me)',
            description = 'Spawns 3× Veteran for you — no cost.',
            icon        = 'shield-halved',
            onSelect    = function() TriggerServerEvent('arena:test:forceWave', 3) end,
        },
        {
            title       = 'Force Tier 4 Wave (me)',
            description = 'Spawns 3× Commander for you — no cost.',
            icon        = 'crown',
            onSelect    = function() TriggerServerEvent('arena:test:forceWave', 4) end,
        },
    },
})

-- ---------------------------------------------------------------------------
-- Root menu
-- ---------------------------------------------------------------------------
lib.registerContext({
    id    = 'arena_menu_root',
    title = 'Arena Test Menu',
    options = {
        {
            title  = 'Game Management',
            icon   = 'gear',
            arrow  = true,
            menu   = 'arena_menu_game',
        },
        {
            title  = 'Simulate Interactions',
            icon   = 'mobile',
            arrow  = true,
            menu   = 'arena_menu_interactions',
        },
        {
            title  = 'Point Management',
            icon   = 'coins',
            arrow  = true,
            menu   = 'arena_menu_points',
        },
        {
            title  = 'Wave Testing',
            icon   = 'person-running',
            arrow  = true,
            menu   = 'arena_menu_waves',
        },
        {
            title    = 'My Stats',
            icon     = 'chart-bar',
            onSelect = function() TriggerServerEvent('arena:requestMyStats') end,
        },
        {
            title       = 'Stop Action Cam',
            description = 'Stop the arena view camera if active.',
            icon        = 'video-slash',
            onSelect    = function()
                pcall(function() exports['actioncam']:StopActionCam() end)
            end,
        },
    },
})

-- ---------------------------------------------------------------------------
-- Open command
-- ---------------------------------------------------------------------------
RegisterCommand('testmenu', function()
    if not Config.TestMode then return end
    lib.showContext('arena_menu_root')
end)
