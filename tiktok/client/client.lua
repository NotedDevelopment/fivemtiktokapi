-- =============================================================================
-- Main Client
-- Orchestrates NUI updates, event handlers, and game flow.
-- =============================================================================

-- NUI is a persistent HUD — never steals focus
SendReactMessage('setVisible', true)
SetNuiFocus(false, false)


-- Hide the mini-map radar for the streamer view
CreateThread(function()
    while true do
        Wait(1000)
        DisplayRadar(false)
    end
end)

-- ---------------------------------------------------------------------------
-- NUI refresh loop
-- ---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(Config.HealthBarRefreshMs)
        SendReactMessage('updateDefenders', GetDefenderHealthData())
        SendReactMessage('updateCrews',     GetCrewHealthData())
        if GetConvoyUIData then
            SendReactMessage('updateConvoy', GetConvoyUIData())
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Event: Spawn Defenders
-- ---------------------------------------------------------------------------
RegisterNetEvent('arena:spawnDefenders', function()
    ClearDefenders()
    SpawnDefenders()
end)

-- ---------------------------------------------------------------------------
-- Event: Spawn attacker wave (normal and test both use this path)
-- ---------------------------------------------------------------------------
RegisterNetEvent('arena:spawnWave', function(waveData)
    SpawnAttackerWave(waveData)
end)

-- ---------------------------------------------------------------------------
-- Event: Crew ended (server confirmed result)
-- ---------------------------------------------------------------------------
RegisterNetEvent('arena:crewEnded', function(summary)
    -- summary = { owner, damageDealt, kills, outcome, colorIndex }
    SendReactMessage('crewEnded', summary)
end)

-- ---------------------------------------------------------------------------
-- Event: Reset game
-- ---------------------------------------------------------------------------
RegisterNetEvent('arena:resetGame', function()
    ClearDefenders()
    ClearAttackers()
    SendReactMessage('resetUI', {})
end)

-- ---------------------------------------------------------------------------
-- Events: targeted clears (triggered by server console commands)
-- ---------------------------------------------------------------------------
RegisterNetEvent('arena:clearDefenders', function()
    ClearDefenders()
end)

RegisterNetEvent('arena:clearAttackers', function()
    ClearAttackers()
    SendReactMessage('updateCrews', {})
end)

-- ---------------------------------------------------------------------------
-- NUI callbacks (React → Lua)
-- ---------------------------------------------------------------------------

-- React fires this on mount once its message listeners are registered.
-- Responds with setVisible so the HUD appears even if the top-level call
-- above was sent before CEF had finished loading the page.
RegisterNUICallback('nuiReady', function(_, cb)
    SendReactMessage('setVisible', true)
    cb({})
end)

RegisterNUICallback('hideFrame', function(_, cb)
    cb({})
end)
