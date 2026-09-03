-- =============================================================================
-- Action Camera — Freecam Config Tool
-- Guard: only loads when ActionCamConfig.EnableConfigTool = true
--
-- Enter/exit:  /acamconfig
-- Export only: /acamexport  (can call mid-session without exiting)
--
-- Controls (shown on-screen while active):
--   Mouse       Look around
--   W/A/S/D     Fly
--   Space       Fly up
--   L-Ctrl      Fly down
--   L-Shift     5× speed
--   Scroll ↑↓   Change fly speed
--   LMB         Place camera of current type
--   RMB         Preview last placed / stop preview
--   R           Cycle type  SPIN → CRANE → STATIC → PAN
--   E           Export all cameras to F8 + exit
--   Esc         Exit without exporting
-- =============================================================================

if not ActionCamConfig.EnableConfigTool then return end

-- ─── state ────────────────────────────────────────────────────────────────────

local configMode = false
local freecam    = nil
local camPos     = vector3(0, 0, 0)
local camYaw     = 0.0
local camPitch   = 0.0
local camSpeed   = 8.0

local TYPES      = { 'spin', 'crane', 'static', 'pan' }
local typeIdx    = 1
local placedCams = {}   -- array of complete camera configs
local panPointA  = nil  -- {x,y,z} pending pan first point

-- preview sub-state
local prevCam     = nil
local prevRunning = false

-- ─── draw helpers ─────────────────────────────────────────────────────────────

local function drawStr(x, y, str, scale, r, g, b)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextScale(0.0, scale)
    SetTextColour(r, g, b, 255)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(str)
    DrawText(x, y)
end

local function drawRect(x, y, w, h, r, g, b, a)
    DrawRect(x + w * 0.5, y + h * 0.5, w, h, r, g, b, a)
end

-- ─── geometry helpers ─────────────────────────────────────────────────────────

local function forwardFromAngles(yaw, pitch)
    local yr = math.rad(yaw)
    local pr = math.rad(pitch)
    return
        -math.sin(yr) * math.cos(pr),
         math.cos(yr) * math.cos(pr),
         math.sin(pr)
end

local function rightFromYaw(yaw)
    local yr = math.rad(yaw)
    return math.cos(yr), math.sin(yr)
end

local function v3pos()
    return { x = camPos.x, y = camPos.y, z = camPos.z }
end

local function lookAt(dist)
    local fx, fy, fz = forwardFromAngles(camYaw, camPitch)
    return { x = camPos.x + fx*(dist or 40),
             y = camPos.y + fy*(dist or 40),
             z = camPos.z + fz*(dist or 40) }
end

-- ─── place camera ─────────────────────────────────────────────────────────────

local function placeCamera()
    local t   = TYPES[typeIdx]
    local pos = v3pos()
    local tgt = lookAt(40)
    local lbl = ('Cam %d'):format(#placedCams + 1)

    if t == 'spin' then
        placedCams[#placedCams + 1] = {
            camType  = 'spin',  label = lbl,
            location = pos,     radius = 30.0,
            height   = 15.0,    speed  = 5.0,
            fov      = 60.0,    duration = 20,
        }

    elseif t == 'crane' then
        placedCams[#placedCams + 1] = {
            camType    = 'crane',  label      = lbl,
            location   = pos,      radius     = 30.0,
            height     = 15.0,     amplitude  = 10.0,
            craneSpeed = 0.1,      speed      = 5.0,
            fov        = 60.0,     duration   = 20,
        }

    elseif t == 'static' then
        placedCams[#placedCams + 1] = {
            camType  = 'static', label    = lbl,
            position = pos,      target   = tgt,
            fov      = 60.0,     duration = 20,
        }

    elseif t == 'pan' then
        if not panPointA then
            panPointA = pos
        else
            placedCams[#placedCams + 1] = {
                camType = 'pan',   label    = lbl,
                pointA  = panPointA, pointB = pos,
                target  = tgt,
                speed   = 6.0,     fov      = 60.0,
                duration = 20,
            }
            panPointA = nil
        end
    end
end

-- ─── preview ──────────────────────────────────────────────────────────────────

local function stopPreview()
    prevRunning = false
    if prevCam and DoesCamExist(prevCam) then
        SetCamActive(freecam, true)
        SetCamActive(prevCam, false)
        DestroyCam(prevCam, false)
        prevCam = nil
    end
end

local function startPreview()
    if #placedCams == 0 then return end
    stopPreview()

    local vc = placedCams[#placedCams]
    prevCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamFov(prevCam, vc.fov or 60.0)
    SetCamActive(freecam, false)
    SetCamActive(prevCam, true)
    prevRunning = true

    local angle = math.random(0, 359) * 1.0
    local cranePhase = math.random(0, 359) * 1.0
    local panT, panDir = 0.0, 1

    Citizen.CreateThread(function()
        while prevRunning and configMode do
            Citizen.Wait(0)
            local dt = GetFrameTime()
            local t  = vc.camType

            if t == 'spin' and vc.location then
                angle = (angle + (vc.speed or 5) * dt) % 360
                local r = math.rad(angle)
                local l = vc.location
                SetCamCoord(prevCam,
                    l.x + math.sin(r)*(vc.radius or 30),
                    l.y + math.cos(r)*(vc.radius or 30),
                    l.z + (vc.height or 15))
                PointCamAtCoord(prevCam, l.x, l.y, l.z)

            elseif t == 'crane' and vc.location then
                angle      = (angle      + (vc.speed      or 5)   * dt) % 360
                cranePhase = (cranePhase + (vc.craneSpeed or 0.1) * 360 * dt) % 360
                local r = math.rad(angle)
                local l = vc.location
                local cz = l.z + (vc.height or 15) + math.sin(math.rad(cranePhase)) * (vc.amplitude or 10)
                SetCamCoord(prevCam,
                    l.x + math.sin(r)*(vc.radius or 30),
                    l.y + math.cos(r)*(vc.radius or 30),
                    cz)
                PointCamAtCoord(prevCam, l.x, l.y, l.z)

            elseif t == 'static' and vc.position then
                local p = vc.position
                SetCamCoord(prevCam, p.x, p.y, p.z)
                if vc.target then PointCamAtCoord(prevCam, vc.target.x, vc.target.y, vc.target.z) end

            elseif t == 'pan' and vc.pointA and vc.pointB then
                local pA, pB = vc.pointA, vc.pointB
                local dist = #(vector3(pB.x-pA.x, pB.y-pA.y, pB.z-pA.z))
                if dist > 0.1 then
                    panT = panT + panDir * ((vc.speed or 6) * dt / dist)
                    if panT >= 1 then panT = 1; panDir = -1
                    elseif panT <= 0 then panT = 0; panDir = 1 end
                    SetCamCoord(prevCam,
                        pA.x+(pB.x-pA.x)*panT,
                        pA.y+(pB.y-pA.y)*panT,
                        pA.z+(pB.z-pA.z)*panT)
                    if vc.target then
                        PointCamAtCoord(prevCam, vc.target.x, vc.target.y, vc.target.z)
                    end
                end
            end

            local cp = GetCamCoord(prevCam)
            SetFocusPosAndVel(cp.x, cp.y, cp.z, 0, 0, 0)
        end
    end)
end

-- ─── export ───────────────────────────────────────────────────────────────────

local function exportAll()
    if #placedCams == 0 then
        print('[acam] No cameras placed yet.')
        return
    end

    local function fv(t)
        return ('{ x = %.2f, y = %.2f, z = %.2f }'):format(t.x, t.y, t.z)
    end

    print('\n── ACAM EXPORT ── paste into Config.ArenaCameras ────────────────────────')
    for _, c in ipairs(placedCams) do
        local t = c.camType
        local lines = { '    {' }
        if t == 'spin' then
            lines[#lines+1] = "        camType  = 'spin',"
            lines[#lines+1] = ("        label    = '%s',"):format(c.label)
            lines[#lines+1] = ('        location = %s,'):format(fv(c.location))
            lines[#lines+1] = ('        radius   = %.1f,'):format(c.radius)
            lines[#lines+1] = ('        height   = %.1f,'):format(c.height)
            lines[#lines+1] = ('        speed    = %.1f,'):format(c.speed)
            lines[#lines+1] = ('        fov      = %.1f,'):format(c.fov)
            lines[#lines+1] = ('        duration = %d,'):format(c.duration)
        elseif t == 'crane' then
            lines[#lines+1] = "        camType    = 'crane',"
            lines[#lines+1] = ("        label      = '%s',"):format(c.label)
            lines[#lines+1] = ('        location   = %s,'):format(fv(c.location))
            lines[#lines+1] = ('        radius     = %.1f,'):format(c.radius)
            lines[#lines+1] = ('        height     = %.1f,'):format(c.height)
            lines[#lines+1] = ('        amplitude  = %.1f,'):format(c.amplitude)
            lines[#lines+1] = ('        craneSpeed = %.2f,'):format(c.craneSpeed)
            lines[#lines+1] = ('        speed      = %.1f,'):format(c.speed)
            lines[#lines+1] = ('        fov        = %.1f,'):format(c.fov)
            lines[#lines+1] = ('        duration   = %d,'):format(c.duration)
        elseif t == 'static' then
            lines[#lines+1] = "        camType  = 'static',"
            lines[#lines+1] = ("        label    = '%s',"):format(c.label)
            lines[#lines+1] = ('        position = %s,'):format(fv(c.position))
            if c.target then lines[#lines+1] = ('        target   = %s,'):format(fv(c.target)) end
            lines[#lines+1] = ('        fov      = %.1f,'):format(c.fov)
            lines[#lines+1] = ('        duration = %d,'):format(c.duration)
        elseif t == 'pan' then
            lines[#lines+1] = "        camType = 'pan',"
            lines[#lines+1] = ("        label   = '%s',"):format(c.label)
            lines[#lines+1] = ('        pointA  = %s,'):format(fv(c.pointA))
            lines[#lines+1] = ('        pointB  = %s,'):format(fv(c.pointB))
            if c.target then lines[#lines+1] = ('        target  = %s,'):format(fv(c.target)) end
            lines[#lines+1] = ('        speed   = %.1f,'):format(c.speed)
            lines[#lines+1] = ('        fov     = %.1f,'):format(c.fov)
            lines[#lines+1] = ('        duration = %d,'):format(c.duration)
        end
        lines[#lines+1] = '    },'
        print(table.concat(lines, '\n'))
    end
    print('─────────────────────────────────────────────────────────────────────────')
    print(('[acam] %d camera(s) exported.'):format(#placedCams))
end

-- ─── enter / exit config mode ─────────────────────────────────────────────────

local function exitConfig()
    if not configMode then return end
    configMode  = false
    prevRunning = false

    if prevCam and DoesCamExist(prevCam) then
        SetCamActive(prevCam, false); DestroyCam(prevCam, false); prevCam = nil
    end
    if freecam and DoesCamExist(freecam) then
        RenderScriptCams(false, true, 500, true, false)
        Citizen.SetTimeout(550, function()
            if freecam and DoesCamExist(freecam) then
                SetCamActive(freecam, false); DestroyCam(freecam, false); freecam = nil
            end
        end)
    end

    ClearFocus()
    DisplayHud(true)
    DisplayRadar(true)
end

local function enterConfig()
    if configMode then exitConfig(); return end
    configMode = true
    placedCams = {}
    panPointA  = nil
    typeIdx    = 1

    local ped = PlayerPedId()
    local p   = GetEntityCoords(ped)
    camPos    = vector3(p.x, p.y, p.z + 2.0)
    camYaw    = GetEntityHeading(ped)
    camPitch  = 0.0
    camSpeed  = 8.0

    freecam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(freecam, camPos.x, camPos.y, camPos.z)
    SetCamRot(freecam, 0.0, 0.0, camYaw, 2)
    SetCamFov(freecam, 70.0)
    SetCamActive(freecam, true)
    RenderScriptCams(true, true, 500, true, false)
    DisplayHud(false)
    DisplayRadar(false)
end

-- ─── on-screen HUD ────────────────────────────────────────────────────────────

local function drawHUD()
    local t    = TYPES[typeIdx]
    local n    = #placedCams

    -- Panel background
    local px, pw, py, ph = 0.006, 0.295, 0.006, 0.235
    drawRect(px, py, pw, ph, 0, 0, 0, 165)

    -- Title bar
    drawRect(px, py, pw, 0.028, 30, 30, 30, 200)
    drawStr(px + 0.010, py + 0.005, 'ACAM CONFIG TOOL', 0.35, 255, 210, 50)

    -- Camera type row
    local ty = py + 0.036
    drawStr(px + 0.010, ty, 'Type:', 0.28, 180, 180, 180)
    local tx = px + 0.068
    for i, name in ipairs(TYPES) do
        local r, g, b = 140, 140, 140
        if i == typeIdx then r, g, b = 80, 220, 80 end
        drawStr(tx, ty, name:upper(), 0.28, r, g, b)
        tx = tx + 0.058
    end

    -- Pan state hint
    if t == 'pan' and panPointA then
        drawStr(px + 0.010, ty + 0.022, 'Point A set — LMB for Point B', 0.25, 255, 170, 60)
    end

    -- Position + count
    drawStr(px + 0.010, py + 0.074,
        ('Pos  %.0f  %.0f  %.0f    Cams: %d'):format(camPos.x, camPos.y, camPos.z, n),
        0.25, 160, 200, 255)

    -- Speed
    drawStr(px + 0.010, py + 0.092,
        ('Speed: %.0f  (Scroll to change)'):format(camSpeed),
        0.25, 160, 160, 160)

    -- Last placed
    if n > 0 then
        local last = placedCams[n]
        local active = prevRunning and '  [PREVIEW]' or ''
        drawStr(px + 0.010, py + 0.110,
            ('Last: [%d] %s%s'):format(n, last.camType:upper(), active),
            0.25, 100, 220, 180)
    end

    -- Divider
    DrawRect(px + pw*0.5, py + 0.130, pw - 0.008, 0.001, 255, 255, 255, 55)

    -- Controls
    local lines = {
        { 'Mouse',    'Look around'                },
        { 'W A S D',  'Fly  |  Space/Ctrl  Up/Down'},
        { 'LMB',      'Place camera here'          },
        { 'RMB',      prevRunning and 'Stop preview' or 'Preview last placed' },
        { 'R',        'Cycle type'                 },
        { 'E',        'Export all + Exit'          },
        { 'Esc',      'Exit (no export)'           },
    }
    local cy = py + 0.137
    for _, l in ipairs(lines) do
        drawStr(px + 0.010, cy, l[1], 0.26, 255, 200, 80)
        drawStr(px + 0.075, cy, l[2], 0.26, 200, 200, 200)
        cy = cy + 0.018
    end
end

-- 3D markers + labels for placed cameras
local function drawMarkers()
    local camCoords = GetGameplayCamCoords()

    for i, cam in ipairs(placedCams) do
        local p
        if cam.camType == 'static'  then p = vector3(cam.position.x, cam.position.y, cam.position.z)
        elseif cam.camType == 'pan' then p = vector3(cam.pointA.x,   cam.pointA.y,   cam.pointA.z)
        elseif cam.location         then p = vector3(cam.location.x,  cam.location.y,  cam.location.z)
        end
        if not p then goto nextMarker end

        DrawMarker(28, p.x, p.y, p.z + 0.5,
            0, 0, 0, 0, 0, 0, 0.35, 0.35, 0.35,
            80, 220, 80, 200, false, false, 2, false, nil, nil, false)

        -- line to pointB for pan cams
        if cam.camType == 'pan' and cam.pointB then
            DrawMarker(28,
                cam.pointB.x, cam.pointB.y, cam.pointB.z + 0.5,
                0, 0, 0, 0, 0, 0, 0.35, 0.35, 0.35,
                255, 170, 60, 200, false, false, 2, false, nil, nil, false)
        end

        -- floating label
        local dist = #(camCoords - p)
        if dist < 90 then
            local onScreen, sx, sy = World3dToScreen2d(p.x, p.y, p.z + 1.1)
            if onScreen then
                local sc = math.max(0.22, 0.34 * (1 - dist/90 * 0.5))
                SetTextFont(4); SetTextProportional(true); SetTextScale(0.0, sc)
                SetTextColour(80, 220, 80, 230); SetTextOutline(); SetTextCentre(true)
                SetTextEntry('STRING')
                AddTextComponentString(('[%d] %s'):format(i, cam.camType:upper()))
                DrawText(sx, sy)
            end
        end

        ::nextMarker::
    end

    -- Pending pan Point A
    if panPointA then
        local p = vector3(panPointA.x, panPointA.y, panPointA.z)
        DrawMarker(28, p.x, p.y, p.z + 0.5,
            0, 0, 0, 0, 0, 0, 0.35, 0.35, 0.35,
            255, 170, 60, 200, false, false, 2, false, nil, nil, false)
        local dist = #(camCoords - p)
        if dist < 90 then
            local onScreen, sx, sy = World3dToScreen2d(p.x, p.y, p.z + 1.1)
            if onScreen then
                SetTextFont(4); SetTextProportional(true); SetTextScale(0.0, 0.28)
                SetTextColour(255, 170, 60, 230); SetTextOutline(); SetTextCentre(true)
                SetTextEntry('STRING'); AddTextComponentString('PAN  A')
                DrawText(sx, sy)
            end
        end
    end
end

-- Simple crosshair
local function drawCrosshair()
    DrawRect(0.5,       0.5,       0.022, 0.0012, 255, 255, 255, 200)
    DrawRect(0.5,       0.5,       0.0007, 0.040, 255, 255, 255, 200)
    -- Small dot
    DrawRect(0.5,       0.5,       0.003,  0.005, 80, 220, 80, 220)
end

-- ─── main thread ──────────────────────────────────────────────────────────────

Citizen.CreateThread(function()
    while true do
        if not configMode then
            Citizen.Wait(200)
        else
            Citizen.Wait(0)

            DisableAllControlActions(0)

            -- Mouse look
            local mx = GetDisabledControlNormal(0, 1) * 4.8
            local my = GetDisabledControlNormal(0, 2) * 4.8
            camYaw   = (camYaw - mx) % 360.0
            camPitch = math.max(-88.0, math.min(88.0, camPitch - my))

            -- Speed scroll
            if IsDisabledControlJustPressed(0, 14) then
                camSpeed = math.min(60.0, camSpeed + 2.0)
            end
            if IsDisabledControlJustPressed(0, 15) then
                camSpeed = math.max(1.0, camSpeed - 2.0)
            end

            -- WASD movement (only when not previewing)
            if not prevRunning then
                local fx, fy, fz = forwardFromAngles(camYaw, camPitch)
                local rx, ry     = rightFromYaw(camYaw)
                local dt         = GetFrameTime()
                local spd        = camSpeed * (IsDisabledControlPressed(0, 21) and 5.0 or 1.0)
                local dx, dy, dz = 0.0, 0.0, 0.0

                if IsDisabledControlPressed(0, 32) then dx=dx+fx*spd*dt; dy=dy+fy*spd*dt; dz=dz+fz*spd*dt end
                if IsDisabledControlPressed(0, 33) then dx=dx-fx*spd*dt; dy=dy-fy*spd*dt; dz=dz-fz*spd*dt end
                if IsDisabledControlPressed(0, 34) then dx=dx-rx*spd*dt; dy=dy-ry*spd*dt end
                if IsDisabledControlPressed(0, 35) then dx=dx+rx*spd*dt; dy=dy+ry*spd*dt end
                if IsDisabledControlPressed(0, 22) then dz=dz+spd*dt end
                if IsDisabledControlPressed(0, 36) then dz=dz-spd*dt end

                camPos = vector3(camPos.x+dx, camPos.y+dy, camPos.z+dz)

                if freecam and DoesCamExist(freecam) then
                    SetCamCoord(freecam, camPos.x, camPos.y, camPos.z)
                    SetCamRot(freecam, camPitch, 0.0, camYaw, 2)
                    SetFocusPosAndVel(camPos.x, camPos.y, camPos.z, 0, 0, 0)
                    RequestCollisionAtCoord(camPos.x, camPos.y, camPos.z)
                end
            end

            -- LMB — place
            if IsDisabledControlJustPressed(0, 24) then
                placeCamera()
            end

            -- RMB — toggle preview
            if IsDisabledControlJustPressed(0, 25) then
                if prevRunning then stopPreview() else startPreview() end
            end

            -- R — cycle type
            if IsDisabledControlJustPressed(0, 45) then
                typeIdx   = typeIdx % #TYPES + 1
                panPointA = nil
            end

            -- E — export + exit
            if IsDisabledControlJustPressed(0, 51) then
                exportAll()
                exitConfig()
            end

            -- Esc — exit only
            if IsDisabledControlJustPressed(0, 202) then
                exitConfig()
            end

            drawHUD()
            drawMarkers()
            if not prevRunning then drawCrosshair() end
            HideHudAndRadarThisFrame()
        end
    end
end)

-- ─── commands ─────────────────────────────────────────────────────────────────

RegisterCommand('acamconfig', function()
    if configMode then exitConfig() else enterConfig() end
end, false)

RegisterCommand('acamexport', function()
    exportAll()
end, false)
