-- =============================================================================
-- Action Camera — client side
--
-- Exports:
--   StartActionCam(opts)   StopActionCam()   IsActionCamActive()
--   AddTrackedPed(ped)     RemoveTrackedPed(ped)   ClearTrackedPeds()
--   ForceAerial()
--
-- opts fields:
--   center     vector3/{x,y,z}  — arena centre for overview shots
--   venueCams  table            — array of venue camera configs from tiktok config
--
-- Camera modes:  ped | idle_orbit | aerial | overview | venue
-- =============================================================================

local isActive       = false
local cam            = nil
local activeOpts     = {}

local mode           = 'ped'
local targetPed      = nil
local smoothPos      = nil
local modeStart      = 0
local pedSwitchCount = 0
local orbitAngle     = 0.0

-- venue-specific state
local venueCamIndex  = 1
local venuePanT      = 0.0
local venuePanDir    = 1
local venueCranePhase = 0.0


local trackedPeds    = {}   -- [ped] = priority (2=viewer NPC, 1=fodder/default)

-- Throttle for mid-venue/aerial combat interrupt checks (ms)
local lastCombatCheck = 0
-- Throttle for snapping to a newly-fighting ped while on an idle ped (ms)
local lastActionCheck = 0

-- vehicle camera: side chosen once per target switch so the angle varies without cycling
local vehCamSide = 1   -- 1 = right, -1 = left

-- heat table: tracks approximate damage events per ped for smarter selection
local pedHeat        = {}   -- [ped] = { hp = lastHP, heat = score }
local HEAT_DECAY     = 0.85 -- multiplied each selection cycle

-- ─── helpers ──────────────────────────────────────────────────────────────────

local function safeDestroyCam(c)
    if c and DoesCamExist(c) then SetCamActive(c, false); DestroyCam(c, false) end
end

local function toV3(t)
    if not t then return nil end
    if type(t) == 'vector3' then return t end
    return vector3(t.x, t.y, t.z)
end

local function getCenter() return toV3(activeOpts.center) end

local function pedAlive(ped)
    return ped and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped)
end

-- ─── wall-clip guard ──────────────────────────────────────────────────────────

local function clipToLOS(pedPos, idealPos, ignorePed)
    local origin = vector3(pedPos.x, pedPos.y, pedPos.z + 0.65)
    local handle = StartShapeTestRay(origin.x, origin.y, origin.z,
        idealPos.x, idealPos.y, idealPos.z, 1 + 16, ignorePed, 4)
    local _, hit, hitCoords = GetShapeTestResult(handle)
    if hit ~= 1 then return idealPos end
    local ray = idealPos - origin
    local len = #ray
    if len < 0.01 then return idealPos end
    return origin + (ray / len) * math.max(0.6, #(hitCoords - origin) - 0.3)
end

-- ─── ped selection with heat scoring ──────────────────────────────────────────

-- Priority tiers (highest wins):
--   4 = viewer / player NPCs
--   3 = guards / attackers
--   2 = fodder
--   ≤1 = default / scenic fallback (venue cam used when all are empty)
local function buildCandidates()
    local player = PlayerPedId()
    if next(trackedPeds) ~= nil then
        local t4, t3, t2, t1 = {}, {}, {}, {}
        for ped, priority in pairs(trackedPeds) do
            if ped ~= player and pedAlive(ped) then
                if     priority >= 4 then t4[#t4+1] = ped
                elseif priority >= 3 then t3[#t3+1] = ped
                elseif priority >= 2 then t2[#t2+1] = ped
                else                      t1[#t1+1] = ped end
            end
        end
        if #t4 > 0 then return t4 end
        if #t3 > 0 then return t3 end
        if #t2 > 0 then return t2 end
        if #t1 > 0 then return t1 end
        return {}   -- all tracked peds dead → advanceMode falls back to venue cam
    end
    local list = {}
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= player and not IsPedAPlayer(ped) and pedAlive(ped)
            and IsPedHuman(ped) and IsPedArmed(ped, 15)
        then list[#list + 1] = ped end
    end
    return list
end

local function updateHeat()
    for ped in pairs(pedHeat) do
        if not pedAlive(ped) then pedHeat[ped] = nil end
    end
    for _, ped in ipairs(buildCandidates()) do
        local hp = GetEntityHealth(ped)
        local entry = pedHeat[ped]
        if not entry then
            pedHeat[ped] = { hp = hp, heat = 0 }
        else
            if hp < entry.hp then
                entry.heat = entry.heat + (entry.hp - hp)
            end
            entry.hp   = hp
            entry.heat = entry.heat * HEAT_DECAY
        end
    end
end

local function findActionPed()
    local candidates = buildCandidates()
    local hot, shooting, combat, covering, idle = {}, {}, {}, {}, {}

    for _, ped in ipairs(candidates) do
        local h            = pedHeat[ped] and pedHeat[ped].heat or 0
        local shooting_now = IsPedShooting(ped)
        local combat_now   = IsPedInCombat(ped)
        local covering_now = IsPedInCover(ped) and not shooting_now

        if h >= 60 then
            -- kill-boosted by LMS — top priority regardless of current action
            hot[#hot + 1] = { ped = ped, heat = h }
        elseif h > 8 and shooting_now then
            -- recently damaged AND actively shooting — high priority
            hot[#hot + 1] = { ped = ped, heat = h }
        elseif shooting_now then
            shooting[#shooting + 1] = ped
        elseif combat_now and not covering_now then
            combat[#combat + 1] = ped
        elseif covering_now then
            -- hiding behind cover but not shooting — lowest priority above idle
            covering[#covering + 1] = ped
        else
            idle[#idle + 1] = ped
        end
    end

    if #hot      > 0 then
        -- Kill-boosted peds (heat >= 60) always win; otherwise pick among top 2
        table.sort(hot, function(a, b) return a.heat > b.heat end)
        local topCount = hot[1].heat >= 60 and 1 or math.min(2, #hot)
        return hot[math.random(topCount)].ped
    end
    if #shooting > 0 then return shooting[math.random(#shooting)] end
    if #combat   > 0 then return combat  [math.random(#combat)]   end
    if #covering > 0 then return covering[math.random(#covering)] end
    if #idle     > 0 then return idle    [math.random(#idle)]     end
    return nil
end

-- Returns true if any candidate ped is actively shooting or in combat
local function anyCombatActive()
    for _, ped in ipairs(buildCandidates()) do
        if IsPedShooting(ped) or IsPedInCombat(ped) then return true end
    end
    return false
end

-- ─── combat centroid (for aerial) ─────────────────────────────────────────────

local function combatCentroid()
    local candidates = buildCandidates()
    if #candidates == 0 then return nil, 0 end
    local sx, sy, sz = 0, 0, 0
    for _, ped in ipairs(candidates) do
        local p = GetEntityCoords(ped); sx = sx+p.x; sy = sy+p.y; sz = sz+p.z
    end
    local n   = #candidates
    local cen = vector3(sx/n, sy/n, sz/n)
    local spread = 0
    for _, ped in ipairs(candidates) do
        local d = #(GetEntityCoords(ped) - cen)
        if d > spread then spread = d end
    end
    return cen, spread
end

-- ─── venue camera helpers ─────────────────────────────────────────────────────

local function getVenueCams()
    local v = activeOpts.venueCams
    if type(v) == 'table' and #v > 0 then return v end
    return nil
end

-- Returns true if any active ped is within proximity of the given position.
local function actionNearPos(pos, radius)
    local candidates = buildCandidates()
    for _, ped in ipairs(candidates) do
        if pedAlive(ped) and IsPedInCombat(ped) then
            if #(GetEntityCoords(ped) - pos) <= radius then return true end
        end
    end
    return false
end

-- Pick a venue cam: prefers one that has proximity to current action.
local function pickVenueCam(venueCams)
    if not venueCams then return 1 end
    local eligible = {}
    for i, vc in ipairs(venueCams) do
        if vc.proximityPos and vc.proximity then
            local p = toV3(vc.proximityPos)
            if p and actionNearPos(p, vc.proximity) then
                eligible[#eligible + 1] = i
            end
        end
    end
    if #eligible > 0 then return eligible[math.random(#eligible)] end
    return math.random(#venueCams)
end

-- Apply a venue camera's position/aim this frame. Returns false if cam type unknown.
local function applyVenueCam(vc, dt)
    local ct = vc.camType
    if ct == 'spin' then
        orbitAngle = (orbitAngle + (vc.speed or 5) * dt) % 360
        local rad  = math.rad(orbitAngle)
        local loc  = toV3(vc.location)
        local r, h = vc.radius or 50, vc.height or 20
        SetCamCoord(cam, loc.x + math.sin(rad)*r, loc.y + math.cos(rad)*r, loc.z + h)
        PointCamAtCoord(cam, loc.x, loc.y, loc.z)

    elseif ct == 'crane' then
        orbitAngle   = (orbitAngle + (vc.speed or 5) * dt) % 360
        venueCranePhase = (venueCranePhase + (vc.craneSpeed or 0.15) * 360 * dt) % 360
        local rad  = math.rad(orbitAngle)
        local loc  = toV3(vc.location)
        local r, h, amp = vc.radius or 50, vc.height or 20, vc.amplitude or 12
        local cz = loc.z + h + math.sin(math.rad(venueCranePhase)) * amp
        SetCamCoord(cam, loc.x + math.sin(rad)*r, loc.y + math.cos(rad)*r, cz)
        PointCamAtCoord(cam, loc.x, loc.y, loc.z)

    elseif ct == 'static' then
        local pos = toV3(vc.position)
        SetCamCoord(cam, pos.x, pos.y, pos.z)
        if vc.target then
            local tgt = toV3(vc.target)
            PointCamAtCoord(cam, tgt.x, tgt.y, tgt.z)
        end

    elseif ct == 'pan' then
        local spd  = vc.speed or 8
        local pA   = toV3(vc.pointA)
        local pB   = toV3(vc.pointB)
        local dist = #(pB - pA)
        if dist < 0.1 then return true end
        venuePanT = venuePanT + venuePanDir * (spd * dt / dist)
        if venuePanT >= 1 then venuePanT = 1; venuePanDir = -1
        elseif venuePanT <= 0 then venuePanT = 0; venuePanDir = 1 end
        local cx = pA.x + (pB.x - pA.x) * venuePanT
        local cy = pA.y + (pB.y - pA.y) * venuePanT
        local cz = pA.z + (pB.z - pA.z) * venuePanT
        SetCamCoord(cam, cx, cy, cz)
        if vc.target then
            local tgt = toV3(vc.target)
            PointCamAtCoord(cam, tgt.x, tgt.y, tgt.z)
        end
    else
        return false
    end
    return true
end

-- ─── mode switches ────────────────────────────────────────────────────────────

local function switchToPed(ped)
    targetPed      = ped
    smoothPos      = nil
    modeStart      = GetGameTimer()
    mode           = 'ped'
    pedSwitchCount = pedSwitchCount + 1
    vehCamSide     = (math.random(2) == 1) and 1 or -1
    if cam and DoesCamExist(cam) then SetCamFov(cam, ActionCamConfig.Fov) end
end

local function switchToAerial()
    orbitAngle = math.random(0, 359)
    smoothPos  = nil
    modeStart  = GetGameTimer()
    mode       = 'aerial'
    if cam and DoesCamExist(cam) then SetCamFov(cam, ActionCamConfig.AerialFov) end
end

local function switchToOverview()
    orbitAngle = math.random(0, 359)
    smoothPos  = nil
    modeStart  = GetGameTimer()
    mode       = 'overview'
    if cam and DoesCamExist(cam) then SetCamFov(cam, ActionCamConfig.OverviewFov) end
end

local function switchToVenue(idx)
    local venueCams = getVenueCams()
    if not venueCams then return false end
    venueCamIndex   = idx or pickVenueCam(venueCams)
    orbitAngle      = math.random(0, 359)
    venueCranePhase = math.random(0, 359)
    venuePanT       = 0.0
    venuePanDir     = 1
    modeStart       = GetGameTimer()
    mode            = 'venue'
    local vc = venueCams[venueCamIndex]
    if cam and DoesCamExist(cam) then SetCamFov(cam, vc.fov or ActionCamConfig.Fov) end
    return true
end

local function advanceMode()
    -- Always prefer a live tracked NPC — aerial and overview sky views removed
    local next = findActionPed()
    if next and pedAlive(next) then
        if next ~= targetPed then
            switchToPed(next)
        else
            modeStart = GetGameTimer()  -- same ped: just extend, no smoothPos reset / jerk
        end
        return
    end

    -- No active ped: use a low-angle venue cam as filler, or hold
    local venueCams = getVenueCams()
    if venueCams and #venueCams > 0 then
        switchToVenue(pickVenueCam(venueCams))
    else
        modeStart = GetGameTimer()
    end
end

-- ─── lerp helper ──────────────────────────────────────────────────────────────

local function lerpPos(cur, tgt, dt, speed)
    local t = math.min(1.0, (speed or ActionCamConfig.FollowSpeed) * dt)
    return vector3(cur.x+(tgt.x-cur.x)*t, cur.y+(tgt.y-cur.y)*t, cur.z+(tgt.z-cur.z)*t)
end

-- ─── per-frame update ─────────────────────────────────────────────────────────

local function updateCam()
    if not cam or not DoesCamExist(cam) then return end

    -- Keep the streaming / rendering system focused on wherever the camera is.
    -- Without this the game only loads assets around the player character.
    local cp = GetCamCoord(cam)
    SetFocusPosAndVel(cp.x, cp.y, cp.z, 0.0, 0.0, 0.0)
    RequestCollisionAtCoord(cp.x, cp.y, cp.z)

    local dt      = GetFrameTime()
    local elapsed = (GetGameTimer() - modeStart) / 1000.0

    -- ── PED or IDLE ORBIT ─────────────────────────────────────────────────────
    if mode == 'ped' then
        local targetGone = not pedAlive(targetPed)
        local pedVeh     = IsPedInAnyVehicle(targetPed, false) and GetVehiclePedIsIn(targetPed, false) or nil
        local inVehicle  = pedVeh ~= nil and pedVeh ~= 0 and DoesEntityExist(pedVeh)
        -- A ped driving counts as "in action" — keep camera on them even when not shooting
        local inAction   = pedAlive(targetPed) and (
            (IsPedShooting(targetPed) and not IsPedInCover(targetPed))
            or (inVehicle and GetEntitySpeed(pedVeh) > 1.0)
        )
        local timeUp = elapsed >= ActionCamConfig.PedDuration
            and (not inAction or elapsed >= ActionCamConfig.PedDuration * 3.0)

        if targetGone or timeUp then
            advanceMode(); return
        end

        local pedPos = GetEntityCoords(targetPed)

        if inVehicle then
            -- ── VEHICLE ───────────────────────────────────────────────────────
            local vehPos = GetEntityCoords(pedVeh)
            local fwd    = GetEntityForwardVector(pedVeh)
            local speed  = GetEntitySpeed(pedVeh)

            -- Pull back and up a little more at higher speeds for a wider view.
            -- No side offset — side offsets snap to the wrong angle every target switch.
            local back = math.min(14.0, 8.0 + speed * 0.12)
            local up   = math.min(5.0,  2.8 + speed * 0.05)
            local cx   = vehPos.x - fwd.x * back
            local cy   = vehPos.y - fwd.y * back
            local cz   = vehPos.z + up

            -- Keep the camera above the ground surface
            local gOk, gz = GetGroundZFor_3dCoord(cx, cy, cz, false)
            if gOk and cz < gz + 1.2 then cz = gz + 1.2 end

            -- Seed from the camera's current world position instead of teleporting
            if not smoothPos then
                local ccx, ccy, ccz = table.unpack(GetCamCoord(cam))
                smoothPos = vector3(ccx, ccy, ccz)
            end

            local ideal      = vector3(cx, cy, cz)
            local followSpeed = ActionCamConfig.FollowSpeed * (1.8 + speed * 0.04)
            smoothPos = lerpPos(smoothPos, ideal, dt, followSpeed)

            local lookAt = vector3(
                vehPos.x + fwd.x * 4.0,
                vehPos.y + fwd.y * 4.0,
                vehPos.z + 1.2)

            SetCamFov(cam, math.min(ActionCamConfig.Fov + speed * 0.25, ActionCamConfig.Fov + 12.0))
            SetCamCoord(cam, smoothPos.x, smoothPos.y, smoothPos.z)
            PointCamAtCoord(cam, lookAt.x, lookAt.y, lookAt.z)

        else
            -- ── ON FOOT ───────────────────────────────────────────────────────
            local inAction = IsPedInCombat(targetPed) or IsPedShooting(targetPed)
            if inAction then
                local forward = GetEntityForwardVector(targetPed)
                local ideal   = vector3(
                    pedPos.x - forward.x * ActionCamConfig.FollowDist,
                    pedPos.y - forward.y * ActionCamConfig.FollowDist,
                    pedPos.z + ActionCamConfig.FollowHeight)
                local safe = clipToLOS(pedPos, ideal, targetPed)
                smoothPos  = smoothPos and lerpPos(smoothPos, safe, dt) or safe
            else
                orbitAngle = (orbitAngle + ActionCamConfig.IdleOrbitSpeed * dt) % 360
                local rad  = math.rad(orbitAngle)
                local r    = ActionCamConfig.IdleOrbitRadius
                local h    = ActionCamConfig.IdleOrbitHeight
                local ideal = vector3(pedPos.x + math.sin(rad)*r, pedPos.y + math.cos(rad)*r, pedPos.z + h)
                smoothPos   = smoothPos and lerpPos(smoothPos, ideal, dt, 1.5) or ideal

                -- Current ped is idle — snap to a fighting ped, but only after
                -- we've watched this ped for at least 3 s and on a 3 s cooldown.
                local nowAC = GetGameTimer()
                if elapsed >= 3.0 and nowAC - lastActionCheck > 3000 then
                    lastActionCheck = nowAC
                    local hotPed = findActionPed()
                    if hotPed and hotPed ~= targetPed and pedAlive(hotPed)
                        and (IsPedInCombat(hotPed) or IsPedShooting(hotPed))
                    then
                        switchToPed(hotPed); return
                    end
                end
            end
            SetCamFov(cam, ActionCamConfig.Fov)
            SetCamCoord(cam, smoothPos.x, smoothPos.y, smoothPos.z)
            PointCamAtCoord(cam, pedPos.x, pedPos.y, pedPos.z + 0.85)
        end

    -- ── AERIAL ────────────────────────────────────────────────────────────────
    elseif mode == 'aerial' then
        if elapsed >= ActionCamConfig.AerialDuration then advanceMode(); return end

        -- Interrupt aerial if a fight starts
        local now = GetGameTimer()
        if now - lastCombatCheck > 400 then
            lastCombatCheck = now
            if anyCombatActive() then
                local next = findActionPed()
                if next and pedAlive(next) then switchToPed(next); return end
            end
        end

        local centroid, spread = combatCentroid()
        if not centroid then advanceMode(); return end

        local height = math.min(ActionCamConfig.AerialMaxHeight,
            ActionCamConfig.AerialBaseHeight + spread * ActionCamConfig.AerialSpreadMul)
        orbitAngle = (orbitAngle + ActionCamConfig.AerialSpeed * dt) % 360
        local rad  = math.rad(orbitAngle)
        local r    = ActionCamConfig.AerialRadius
        local ideal = vector3(centroid.x + math.sin(rad)*r, centroid.y + math.cos(rad)*r, centroid.z + height)

        if not smoothPos then smoothPos = ideal end
        smoothPos = lerpPos(smoothPos, ideal, dt, ActionCamConfig.FollowSpeed * 0.5)

        SetCamCoord(cam, smoothPos.x, smoothPos.y, smoothPos.z)
        PointCamAtCoord(cam, centroid.x, centroid.y, centroid.z)

    -- ── OVERVIEW ──────────────────────────────────────────────────────────────
    elseif mode == 'overview' then
        local center = getCenter()
        if not center then advanceMode(); return end
        if elapsed >= ActionCamConfig.OverviewDuration then advanceMode(); return end

        -- Interrupt overview if a fight starts
        local now = GetGameTimer()
        if now - lastCombatCheck > 400 then
            lastCombatCheck = now
            if anyCombatActive() then
                local next = findActionPed()
                if next and pedAlive(next) then switchToPed(next); return end
            end
        end

        orbitAngle = (orbitAngle + ActionCamConfig.OverviewSpeed * dt) % 360
        local rad  = math.rad(orbitAngle)
        SetCamCoord(cam,
            center.x + math.sin(rad) * ActionCamConfig.OverviewRadius,
            center.y + math.cos(rad) * ActionCamConfig.OverviewRadius,
            center.z + ActionCamConfig.OverviewHeight)
        PointCamAtCoord(cam, center.x, center.y, center.z)

    -- ── VENUE ─────────────────────────────────────────────────────────────────
    elseif mode == 'venue' then
        local venueCams = getVenueCams()
        if not venueCams then advanceMode(); return end
        if elapsed >= ActionCamConfig.VenueDuration then advanceMode(); return end

        -- Interrupt venue cam if a fight starts
        local now = GetGameTimer()
        if now - lastCombatCheck > 400 then
            lastCombatCheck = now
            if anyCombatActive() then
                local next = findActionPed()
                if next and pedAlive(next) then switchToPed(next); return end
            end
        end

        local vc = venueCams[venueCamIndex]
        if not vc then advanceMode(); return end
        applyVenueCam(vc, dt)
    end
end

-- ─── lifecycle ────────────────────────────────────────────────────────────────

local function startCamera(opts)
    if isActive then return end
    activeOpts     = opts or {}
    isActive       = true
    pedSwitchCount = 0
    smoothPos      = nil
    pedHeat        = {}

    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(cam, ActionCamConfig.Fov)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, true)
    DisplayHud(false)
    DisplayRadar(false)

    local first = findActionPed()
    if first and pedAlive(first) then
        switchToPed(first)
    elseif getVenueCams() then
        switchToVenue(1)
    elseif ActionCamConfig.AerialEvery > 0 then
        switchToAerial()
    else
        modeStart = GetGameTimer(); mode = 'ped'; targetPed = nil
    end

    local center = getCenter()
    if center then
        SetFocusPosAndVel(center.x, center.y, center.z, 0, 0, 0)
        RequestCollisionAtCoord(center.x, center.y, center.z)
    end
end

local function stopCamera()
    if not isActive then return end
    isActive  = false
    targetPed = nil
    smoothPos = nil

    ClearFocus()
    DisplayHud(true)
    DisplayRadar(true)

    RenderScriptCams(false, true, 600, true, false)
    Citizen.SetTimeout(650, function() safeDestroyCam(cam); cam = nil end)
end

-- ─── update thread ────────────────────────────────────────────────────────────

Citizen.CreateThread(function()
    while true do
        if not isActive then Citizen.Wait(500)
        else Citizen.Wait(0); HideHudAndRadarThisFrame(); updateCam() end
    end
end)

-- Background heat tracker — samples every 333ms so damage is recorded even
-- when we haven't switched targets recently.
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(333)
        if isActive then updateHeat() end
    end
end)

-- ─── manual perspective cycling (left / right mouse) ─────────────────────────
-- Left click  = previous ped (or last ped if currently on aerial/venue)
-- Right click = next ped (or first ped if currently on aerial/venue)
-- Both inputs are suppressed so the player doesn't shoot/aim.

local function cycleCam(forward)
    if not isActive then return end
    local cands = buildCandidates()
    if #cands == 0 then
        -- No peds available: fall back to aerial or venue
        if ActionCamConfig.AerialEvery > 0 then
            switchToAerial()
        elseif getVenueCams() then
            switchToVenue(pickVenueCam(getVenueCams()))
        end
        return
    end

    -- Locate where the current target sits in the candidate list
    local curIdx = 0
    for i, p in ipairs(cands) do
        if p == targetPed then curIdx = i; break end
    end

    local newIdx
    if curIdx == 0 then
        -- Currently on aerial/venue or target fell off list: jump to an edge
        newIdx = forward and 1 or #cands
    elseif forward then
        newIdx = (curIdx % #cands) + 1
    else
        newIdx = ((curIdx - 2 + #cands) % #cands) + 1
    end

    local ped = cands[newIdx]
    if pedAlive(ped) then
        switchToPed(ped)
    else
        -- Chosen ped is dead: find the next alive one
        for offset = 1, #cands - 1 do
            local idx = ((newIdx - 1 + (forward and offset or -offset) + #cands) % #cands) + 1
            if pedAlive(cands[idx]) then switchToPed(cands[idx]); return end
        end
    end
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if isActive then
            -- Suppress shoot / aim so clicks don't affect gameplay
            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)

            if IsDisabledControlJustPressed(0, 24) then
                cycleCam(false)   -- left mouse  → previous
            elseif IsDisabledControlJustPressed(0, 25) then
                cycleCam(true)    -- right mouse → next
            elseif IsControlJustPressed(0, 38) then
                cycleCam(true)    -- E → next
            end
        end
    end
end)

-- ─── client command ───────────────────────────────────────────────────────────

RegisterCommand('arenaviewstop', function() stopCamera() end, false)

-- ─── exports ──────────────────────────────────────────────────────────────────

exports('StartActionCam',    function(opts) startCamera(opts) end)
exports('StopActionCam',     function()     stopCamera()      end)
exports('IsActionCamActive', function()     return isActive   end)

exports('ForceAerial', function()
    if not isActive then return end
    switchToAerial()
end)

exports('ForceVenue', function(idx)
    if not isActive then return end
    switchToVenue(idx)
end)

exports('AddTrackedPed', function(ped, priority)
    if ped and ped ~= 0 then trackedPeds[ped] = priority or 1 end
end)

exports('RemoveTrackedPed', function(ped)
    trackedPeds[ped] = nil
    pedHeat[ped]     = nil
    if targetPed == ped then targetPed = nil end
end)

exports('ClearTrackedPeds', function()
    trackedPeds = {}
    pedHeat     = {}
    targetPed   = nil
end)

-- External kill notification: boosts this ped to top camera priority
exports('AddPedHeat', function(ped, amount)
    if not ped or ped == 0 then return end
    if not pedHeat[ped] then
        pedHeat[ped] = { hp = GetEntityHealth(ped), heat = 0 }
    end
    pedHeat[ped].heat = pedHeat[ped].heat + (amount or 30)
end)

-- ─── net events ───────────────────────────────────────────────────────────────

RegisterNetEvent('actioncam:start', true)
AddEventHandler('actioncam:start', function(opts) startCamera(opts or {}) end)

RegisterNetEvent('actioncam:stop', true)
AddEventHandler('actioncam:stop', function() stopCamera() end)
