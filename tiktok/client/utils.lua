--- A simple wrapper around SendNUIMessage that you can use to
--- dispatch actions to the React frame.
---
---@param action string The action you wish to target
---@param data any The data you wish to send along with this action
function SendReactMessage(action, data)
  SendNUIMessage({
    action = action,
    data = data
  })
end

-- ---------------------------------------------------------------------------
-- SchedulePedDeath — wait, smoke poof, then delete the ped
-- Controlled by Config.PedsDisappearOnDeath / Config.PedDeathFadeDelay
-- ---------------------------------------------------------------------------
local _POOF_DICT = 'core'
local _POOF_FX   = 'exp_grd_smoke'

function SchedulePedDeath(ped)
    if not Config.PedsDisappearOnDeath then return end
    local delay = Config.PedDeathFadeDelay or 3000
    CreateThread(function()
        Wait(delay)
        if not DoesEntityExist(ped) then return end
        RequestNamedPtfxAsset(_POOF_DICT)
        local t = 0
        while not HasNamedPtfxAssetLoaded(_POOF_DICT) do
            Wait(50); t = t + 50
            if t > 2000 then break end
        end
        if DoesEntityExist(ped) then
            if HasNamedPtfxAssetLoaded(_POOF_DICT) then
                UseParticleFxAssetNextCall(_POOF_DICT)
                local p = GetEntityCoords(ped)
                StartParticleFxNonLooped(_POOF_FX, p.x, p.y, p.z, 0.0, 0.0, 0.0, 1.2, false, false, false)
            end
            DeletePed(ped)
        end
        RemoveNamedPtfxAsset(_POOF_DICT)
    end)
end

local currentResourceName = GetCurrentResourceName()

local debugIsEnabled = GetConvarInt(('%s-debugMode'):format(currentResourceName), 0) == 1

--- A simple debug print function that is dependent on a convar
--- will output a nice prettfied message if debugMode is on
function debugPrint(...)
  if not debugIsEnabled then return end
  local args <const> = { ... }

  local appendStr = ''
  for _, v in ipairs(args) do
    appendStr = appendStr .. ' ' .. tostring(v)
  end
  local msgTemplate = '^3[%s]^0%s'
  local finalMsg = msgTemplate:format(currentResourceName, appendStr)
  print(finalMsg)
end
