-- Floating 3D label stack rendered above each NPC.
-- Label dict shape:
--   { teamName?, charName, r, g, b, maxHP }
-- teamName is optional (fodder skips it).
--
-- Viewer NPC stack (3 elements, raised high):
--   [TeamName]   sy - 0.050
--   CharName     sy - 0.032
--   [====HP==]   sy + 0.006
--
-- Fodder stack (2 elements, larger gap between name and bar):
--   Fodder       sy - 0.028
--   [====HP==]   sy + 0.014

LmsLabels = {}

local function hpColour(pct)
    if pct > 0.6 then return 74,  222, 128
    elseif pct > 0.3 then return 250, 204, 21
    else             return 248, 113, 113 end
end

local function drawText(text, sx, sy, scale, r, g, b, a)
    SetTextScale(scale, scale)
    SetTextFont(4)
    SetTextColour(r, g, b, a)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(sx, sy)
end

local function drawBar(sx, barY, barW, barH, pct)
    DrawRect(sx, barY, barW, barH, 10, 10, 10, 185)
    local fillW = barW * pct
    if fillW > 0.0003 then
        local r, g, b = hpColour(pct)
        DrawRect(sx - barW * 0.5 + fillW * 0.5, barY, fillW, barH * 0.72, r, g, b, 235)
    end
end

CreateThread(function()
    while true do
        Wait(0)
        for entity, info in pairs(LmsLabels) do
            if not DoesEntityExist(entity) or IsEntityDead(entity) then
                LmsLabels[entity] = nil
            else
                local coords = GetEntityCoords(entity) + vector3(0.0, 0.0, 1.3)
                local ok, sx, sy = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
                if ok then
                    local tr, tg, tb = info.r or 255, info.g or 255, info.b or 255

                    if info.teamName then
                        -- ── Viewer NPC: team / name / bar  (all raised) ──────
                        drawText('[' .. info.teamName .. ']', sx, sy - 0.050, 0.34, tr, tg, tb, 200)
                        drawText(info.charName or '?',        sx, sy - 0.032, 0.44, 255, 255, 255, 230)
                        if info.maxHP and info.maxHP > 0 then
                            local hp  = math.max(0, GetEntityHealth(entity) - 100) + GetPedArmour(entity)
                            local pct = math.min(1.0, hp / info.maxHP)
                            drawBar(sx, sy + 0.006, 0.058, 0.009, pct)
                        end
                    else
                        -- ── Fodder: name / bar  (larger gap) ─────────────────
                        drawText(info.charName or 'Fodder', sx, sy - 0.028, 0.34, tr, tg, tb, 200)
                        if info.maxHP and info.maxHP > 0 then
                            local hp  = math.max(0, GetEntityHealth(entity) - 100) + GetPedArmour(entity)
                            local pct = math.min(1.0, hp / info.maxHP)
                            drawBar(sx, sy + 0.014, 0.048, 0.008, pct)
                        end
                    end
                end
            end
        end
    end
end)
