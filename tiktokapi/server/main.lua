local connected = false
local currentUsername = nil

-- ─── exports ──────────────────────────────────────────────────────────────────

-- Connect to a TikTok LIVE stream by username (no @ prefix needed)
exports('Connect', function(username)
    if not username or username == '' then
        return false, 'Username is required'
    end
    username = username:gsub('^@', '') -- strip leading @ if provided
    TriggerEvent('tiktokapi:cmd:connect', username)
    return true
end)

-- Disconnect from the current stream
exports('Disconnect', function()
    TriggerEvent('tiktokapi:cmd:disconnect')
end)

-- Returns true/false
exports('IsConnected', function()
    return connected
end)

-- Returns the currently connected TikTok username, or nil
exports('GetUsername', function()
    return currentUsername
end)

-- ─── internal state tracking ──────────────────────────────────────────────────

AddEventHandler('tiktokapi:connected', function(username)
    connected = true
    currentUsername = username
end)

AddEventHandler('tiktokapi:disconnected', function()
    connected = false
    currentUsername = nil
end)

AddEventHandler('tiktokapi:connectFailed', function(username, reason)
    print('^1[TikTokAPI]^0 Failed to connect to @' .. tostring(username) .. ': ' .. tostring(reason))
end)

-- ─── server console commands ──────────────────────────────────────────────────

RegisterCommand('tiktok', function(source, args)
    if source ~= 0 then return end
    if not args[1] then
        print('[TikTokAPI] Usage: tiktok <username>')
        return
    end
    exports['tiktokapi']:Connect(args[1])
end, true)

RegisterCommand('tiktokstop', function(source, args)
    if source ~= 0 then return end
    exports['tiktokapi']:Disconnect()
    print('[TikTokAPI] Disconnecting...')
end, true)

RegisterCommand('tiktokstatus', function(source, args)
    if source ~= 0 then return end
    if connected then
        print('[TikTokAPI] Connected to @' .. tostring(currentUsername))
    else
        print('[TikTokAPI] Not connected')
    end
end, true)


AddEventHandler('tiktokapi:test', function(msg)
    print('[TikTokAPI] LUA received cross-runtime test: ' .. tostring(msg))
end)

AddEventHandler('tiktokapi:member', function(jsonData)
    local data = json.decode(jsonData)
    print('[TikTokAPI] LUA member joined: ' .. tostring(data.nickname) .. ' (@' .. tostring(data.uniqueId) .. ')')
end)

AddEventHandler('tiktokapi:chat', function(jsonData)
    local data = json.decode(jsonData)
    print('[TikTokAPI] LUA received chat: ' .. tostring(data.nickname) .. ' said: ' .. tostring(data.comment))
end)

AddEventHandler('tiktokapi:like', function(jsonData)
    local data = json.decode(jsonData)
    print("data == " .. json.encode(data, {indent = true}))

    -- -- find the player whose TikTok uniqueId matches
    -- local target = GetPlayerFromTikTokId(data.uniqueId)
    -- if not target then return end

    -- local diamonds = data.diamondCount * data.repeatCount
    -- TriggerClientEvent('myresource:showGiftNotification', target, data.nickname, data.giftName, diamonds)

    -- -- give in-game money proportional to diamond value
    -- local cash = math.floor(diamonds * 0.5)
    -- exports['Renewed-Banking']:addAccountMoney(target, 'cash', cash)
end)