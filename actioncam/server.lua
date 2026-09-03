-- =============================================================================
-- Action Camera — server side (standalone fallback commands)
-- When used WITH the tiktok resource, arenaview/arenaviewstop are registered
-- there instead (with full Config.ArenaCameras support).
-- These are only needed when actioncam is run on its own.
-- =============================================================================

local function isAdmin(source)
    return source == 0 or IsPlayerAceAllowed(source, 'tiktok.admin')
end

RegisterCommand('acamstart', function(source, args)
    if not isAdmin(source) then return end
    local opts = {}
    if args[1] and args[2] and args[3] then
        opts.center = { x = tonumber(args[1]), y = tonumber(args[2]), z = tonumber(args[3]) }
    end
    TriggerClientEvent('actioncam:start', -1, opts)
end, false)

RegisterCommand('acamstop', function(source)
    if not isAdmin(source) then return end
    TriggerClientEvent('actioncam:stop', -1)
end, false)
