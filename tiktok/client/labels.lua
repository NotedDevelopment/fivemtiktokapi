-- =============================================================================
-- Labels
-- Floating 3D text drawn above each active ped every frame.
-- Other files populate ArenaLabels; this file owns only the draw loop.
-- =============================================================================

-- ArenaLabels[ped] = { text, r, g, b }
ArenaLabels = {}

local playerPed = PlayerPedId

local function drawLabel(x, y, z, text, r, g, b)
    local onScreen, sx, sy = World3dToScreen2d(x, y, z)
    if not onScreen then return end

    local camX, camY, camZ = table.unpack(GetGameplayCamCoords())
    local dist = #(vector3(camX, camY, camZ) - vector3(x, y, z))
    if dist > Config.LabelDrawDistance then return end

    -- Scale slightly with distance so close labels aren't giant
    local scale = math.max(0.28, 0.42 * (1.0 - dist / Config.LabelDrawDistance * 0.6))

    -- Box scales with text scale so it always contains the rendered text
    local sz   = scale / 0.28   -- 1.0 at max draw distance, ~1.5 at point-blank
    local bgW  = (math.max(0.04, #text * 0.0055) + 0.014) * sz
    local bgH  = 0.024 * sz
    DrawRect(sx, sy, bgW, bgH, 0, 0, 0, 160)

    SetTextScale(scale, scale)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(r, g, b, 230)
    SetTextOutline()
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    DrawText(sx, sy - 0.008)
end

CreateThread(function()
    while true do
        Wait(0)
        for ped, info in pairs(ArenaLabels) do
            if DoesEntityExist(ped) and not IsEntityDead(ped) then
                local coords = GetEntityCoords(ped)
                drawLabel(
                    coords.x, coords.y, coords.z + Config.LabelZOffset,
                    info.text, info.r, info.g, info.b
                )
            end
        end
    end
end)
