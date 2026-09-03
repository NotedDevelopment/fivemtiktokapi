-- Register net events so the server can push TikTok events to specific clients.
-- Call TriggerClientEvent('tiktokapi:client:gift', playerId, jsonData)
-- from your own resource to relay events to players.

RegisterNetEvent('tiktokapi:client:chat',      true)
RegisterNetEvent('tiktokapi:client:gift',      true)
RegisterNetEvent('tiktokapi:client:like', function(playerId, jsonData)
    print("playerId == " .. json.encode(playerId, {indent = true}))
    print("jsonData == " .. json.encode(jsonData, {indent = true}))
end)
RegisterNetEvent('tiktokapi:client:follow',    true)
RegisterNetEvent('tiktokapi:client:share',     true)
RegisterNetEvent('tiktokapi:client:member',    true)
RegisterNetEvent('tiktokapi:client:subscribe', true)
RegisterNetEvent('tiktokapi:client:streamEnd', true)
