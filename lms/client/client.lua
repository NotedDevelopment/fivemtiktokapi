-- =============================================================================
-- LMS Client
-- =============================================================================

-- NUI is a persistent HUD — never steals focus
SendReactMessage('setVisible', true)
SetNuiFocus(false, false)

-- Suppress minimap for the stream view
CreateThread(function()
    while true do
        Wait(1000)
        DisplayRadar(false)
    end
end)

-- ---------------------------------------------------------------------------
-- Game-active flag (read by peds.lua to gate fodder/attacker spawning)
-- ---------------------------------------------------------------------------
lmsRunning = false


-- ---------------------------------------------------------------------------
-- NUI refresh loop
-- ---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.HealthBarRefreshMs)
        SendReactMessage('updateCrews',     GetCrewHealthData())
        SendReactMessage('updateFodder',    GetFodderHealthData())
        SendReactMessage('updateAttackers', GetAttackerHealthData())
    end
end)

-- ---------------------------------------------------------------------------
-- Net events from server
-- ---------------------------------------------------------------------------
RegisterNetEvent('lms:spawnNpc', function(npcData)
    SpawnLmsNpc(npcData)
end)

RegisterNetEvent('lms:resetGame', function()
    lmsRunning = false
    ClearAllNpcs()
    SendReactMessage('resetUI', {})
end)

RegisterNetEvent('lms:updateLeaderboard', function(lb)
    SendReactMessage('updateLeaderboard', lb)
end)

-- Enrich elimination data with NPC display names before forwarding to NUI
RegisterNetEvent('lms:showElimination', function(data)
    data.victimChar = viewerDisplayNames and viewerDisplayNames[data.owner] or nil
    data.killerChar = data.killer and viewerDisplayNames and viewerDisplayNames[data.killer] or nil
    SendReactMessage('showElimination', data)
end)

-- ---------------------------------------------------------------------------
-- ActionCam lifecycle
-- ---------------------------------------------------------------------------
RegisterNetEvent('lms:camStart', function(opts)
    lmsRunning = true
    if Config.FodderEnabled then
        CreateThread(function()
            Wait(6000)
            if lmsRunning then SpawnFodder() end
        end)
    end
    if Config.AttackerEnabled then
        CreateThread(function()
            Wait(15000)
            if lmsRunning then SpawnAttackers() end
        end)
    end
    if Config.ActionCamEnabled and exports['actioncam'] then
        pcall(function() exports['actioncam']:StartActionCam(opts) end)
    end
end)

RegisterNetEvent('lms:camStop', function()
    lmsRunning = false
    if Config.ActionCamEnabled and exports['actioncam'] then
        pcall(function() exports['actioncam']:StopActionCam() end)
    end
end)

-- ---------------------------------------------------------------------------
-- NUI callbacks
-- ---------------------------------------------------------------------------
RegisterNUICallback('nuiReady', function(_, cb)
    SendReactMessage('setVisible', true)
    SendReactMessage('setConfig', {
        eliminationMessages = Config.EliminationMessages,
        fodderName          = Config.FodderNpc.tierName   or 'Fodder',
        guardName           = Config.AttackerNpc.tierName or 'Guard',
    })
    cb({})
end)

RegisterNUICallback('hideFrame', function(_, cb)
    cb({})
end)

RegisterNUICallback('savePositions', function(_, cb)
    -- Positions are saved to localStorage inside the NUI; Lua just closes edit mode
    SetNuiFocus(false, false)
    SendReactMessage('setEditMode', false)
    cb({})
end)

RegisterNUICallback('cancelEdit', function(_, cb)
    SetNuiFocus(false, false)
    SendReactMessage('setEditMode', false)
    cb({})
end)

-- ---------------------------------------------------------------------------
-- /lmsedit — in-game UI position editor
-- /lmsuireset — restore all panels to default positions
-- ---------------------------------------------------------------------------
RegisterCommand('lmsedit', function()
    SetNuiFocus(true, true)
    SendReactMessage('setEditMode', true)
end, false)

RegisterCommand('lmsuireset', function()
    SendReactMessage('resetUIPositions', {})
    print('[LMS] UI positions reset to defaults')
end, false)
