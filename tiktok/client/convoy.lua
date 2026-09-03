-- =============================================================================
-- Convoy Gamemode — Client
-- =============================================================================

-- ─── State ────────────────────────────────────────────────────────────────────

ConvoyState = {
    active           = false,
    vipVeh           = nil,
    convoyVehicles   = {},
    attackerVehicles = {},
    mode             = 'passive',
    lastAttackerSeen = 0,
    routeEnd         = nil,
    totalRouteDist   = 1.0,
    escortTimer      = 0,
    driveTimer       = 0,
}

local CONVOY_GROUP            = nil
local convoyViewerGroups      = {}
local ConvoyVehicleLabels     = {}  -- [vehHandle] = { text, r, g, b }
local convoyEngagementTimer   = 0

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function loadModel(hash)
    RequestModel(hash)
    local t = 0
    while not HasModelLoaded(hash) do
        Wait(100); t = t + 100
        if t > 6000 then break end
    end
end

local function combinedPedHP(ped)
    if not ped or not DoesEntityExist(ped) then return 0 end
    return math.max(0, GetEntityHealth(ped) - 100) + GetPedArmour(ped)
end

-- ─── Relationship Groups ──────────────────────────────────────────────────────

local function initConvoyGroups()
    if CONVOY_GROUP then return end
    AddRelationshipGroup('CONVOY_TEAM')
    CONVOY_GROUP = GetHashKey('CONVOY_TEAM')
    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())
    SetRelationshipBetweenGroups(0, CONVOY_GROUP, playerGroup)
    SetRelationshipBetweenGroups(0, playerGroup, CONVOY_GROUP)
end

local function getOrCreateViewerGroup(username)
    if convoyViewerGroups[username] then return convoyViewerGroups[username] end
    local safe = username:gsub('[^%w]', '_'):upper():sub(1, 20)
    AddRelationshipGroup('CONVOY_V_' .. safe)
    local hash = GetHashKey('CONVOY_V_' .. safe)
    convoyViewerGroups[username] = hash
    local playerGroup = GetPedRelationshipGroupHash(PlayerPedId())
    SetRelationshipBetweenGroups(0, hash, playerGroup)
    SetRelationshipBetweenGroups(0, playerGroup, hash)
    SetRelationshipBetweenGroups(5, hash, CONVOY_GROUP)
    SetRelationshipBetweenGroups(5, CONVOY_GROUP, hash)
    for _, other in pairs(convoyViewerGroups) do
        if other ~= hash then
            -- All attacker groups are allies — only hate the convoy
            SetRelationshipBetweenGroups(0, hash, other)
            SetRelationshipBetweenGroups(0, other, hash)
        end
    end
    return hash
end

-- ─── Ped Setup ────────────────────────────────────────────────────────────────

local function setupConvoyPed(ped, relGroup, health, armor)
    SetPedRelationshipGroupHash(ped, relGroup)
    SetEntityHealth(ped, 100 + (health or 200))
    SetPedMaxHealth(ped, 100 + (health or 200))
    SetPedArmour(ped, armor or 50)
    SetPedCombatAttributes(ped, 2,  true)   -- DisableBulletReaction (keeps fighting when hit)
    SetPedCombatAttributes(ped, 3,  true)   -- CanDriveBy
    SetPedCombatAttributes(ped, 5,  true)   -- AlwaysFight
    SetPedCombatAttributes(ped, 13, true)   -- DisableVehicleExplosionReaction
    SetPedCombatAttributes(ped, 46, true)   -- CanFightArmedPedsWhenNotArmed
    SetPedFleeAttributes(ped, 0, false)
    SetPedAlertness(ped, 3)
    SetPedCanBeTargettedByPlayer(ped, PlayerId(), false)
    SetPedAccuracy(ped, 65)
    SetPedCombatRange(ped, 2)
    -- Drivers get SetBlockingOfNonTemporaryEvents applied explicitly after this call.
    -- Passengers must NOT have it or they are invisible to the attacker hate-relationship scan.
    if Config.DisableBlood then SetPedSuffersCriticalHits(ped, false) end
end

local function setupAttackerPed(ped, relGroup, tierCfg)
    SetPedRelationshipGroupHash(ped, relGroup)
    SetEntityHealth(ped, 100 + (tierCfg.health or 100))
    SetPedMaxHealth(ped, 100 + (tierCfg.health or 100))
    SetPedArmour(ped, tierCfg.armor or 0)
    SetPedCombatAttributes(ped, 2,  true)   -- DisableBulletReaction
    SetPedCombatAttributes(ped, 3,  true)   -- CanDriveBy
    SetPedCombatAttributes(ped, 5,  true)   -- AlwaysFight
    SetPedCombatAttributes(ped, 13, true)   -- DisableVehicleExplosionReaction
    SetPedCombatAttributes(ped, 46, true)   -- CanFightArmedPedsWhenNotArmed
    SetPedCombatAttributes(ped, 52, true)   -- WillChaseTarget
    SetPedFleeAttributes(ped, 0, false)
    SetPedAlertness(ped, 3)
    SetPedCombatMovement(ped, 2)
    SetPedCombatRange(ped, 3)              -- long range
    SetPedCanBeTargettedByPlayer(ped, PlayerId(), false)
    SetPedAccuracy(ped, tierCfg.accuracy or 40)
    if Config.DisableBlood then SetPedSuffersCriticalHits(ped, false) end
end

-- ─── Ground Z ─────────────────────────────────────────────────────────────────
-- Forces collision to stream in, then finds the real surface Z.
-- Must be called from a thread (uses Wait).

local function findGroundZ(x, y, z)
    RequestCollisionAtCoord(x, y, z)
    SetFocusPosAndVel(x, y, z, 0, 0, 0)

    local gz = z + 2.0
    for _ = 1, 30 do
        Wait(100)
        local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 200.0, false)
        if found then gz = groundZ + 0.5; break end
    end

    ClearFocus()
    return gz
end

-- Non-blocking road snap for attacker vehicles.
-- Does one immediate ground Z lookup (no looping Wait); SetVehicleOnGroundProperly
-- handles any remaining offset after spawn.
local function quickSpawnPos(x, y, z)
    for n = 0, 4 do
        local nodePos, nodeHeading = GetNthClosestVehicleNodeWithHeading(x, y, z, n, 1, 3, 0)
        if nodePos
            and #(vector3(x, y, z) - nodePos) < 50.0
            and IsPointOnRoad(nodePos.x, nodePos.y, nodePos.z, 0)
        then
            local ok, gz = GetGroundZFor_3dCoord(nodePos.x, nodePos.y, nodePos.z + 100.0, false)
            return nodePos.x, nodePos.y, ok and (gz + 0.5) or (z + 1.0), nodeHeading
        end
    end
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 100.0, false)
    return x, y, ok and (gz + 0.5) or (z + 1.0), 0.0
end

-- Returns the best ped target for attacker passengers to shoot at.
local function findConvoyShootTarget()
    if ConvoyState.vipVeh and DoesEntityExist(ConvoyState.vipVeh) then
        local d = GetPedInVehicleSeat(ConvoyState.vipVeh, -1)
        if d and d ~= 0 and DoesEntityExist(d) and not IsEntityDead(d) then return d end
    end
    for _, entry in ipairs(ConvoyState.convoyVehicles) do
        for _, pd in ipairs(entry.peds) do
            if pd.alive and DoesEntityExist(pd.ped) and not IsEntityDead(pd.ped) then
                return pd.ped
            end
        end
    end
    return nil
end

-- ─── Spawn Convoy Vehicle ─────────────────────────────────────────────────────
-- Must be called from inside a CreateThread.

local function spawnConvoyVehicle(modelName, driverModelName, x, y, z, heading, role, label, colorR, colorG, colorB)
    local spawnZ = findGroundZ(x, y, z)

    local hash = GetHashKey(modelName)
    loadModel(hash)

    local veh = CreateVehicle(hash, x, y, spawnZ, heading, false, false)
    if not veh or veh == 0 then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(veh, true, true)

    if role == 'vip' then
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehicleBodyHealth(veh, 1000.0)
        SetVehiclePetrolTankHealth(veh, 1000.0)
    end

    -- Spawn driver
    local driverHash = GetHashKey(driverModelName)
    loadModel(driverHash)
    local driver = CreatePedInsideVehicle(veh, 26, driverHash, -1, false, false)
    SetEntityAsMissionEntity(driver, true, true)
    SetModelAsNoLongerNeeded(driverHash)
    setupConvoyPed(driver, CONVOY_GROUP, 250, 75)
    -- Drivers must not have tasks cancelled by ambient AI events
    SetBlockingOfNonTemporaryEvents(driver, true)
    SetPedKeepTask(driver, true)
    GiveWeaponToPed(driver, GetHashKey('WEAPON_ASSAULTRIFLE'), 250, true, false)
    pcall(function() exports['actioncam']:AddTrackedPed(driver) end)

    -- Let physics settle the vehicle onto the surface
    SetVehicleEngineOn(veh, true, true, false)
    Wait(500)
    SetVehicleOnGroundProperly(veh)

    local pedsList = {
        { ped = driver, tierName = 'Driver', maxHP = 325, alive = true }
    }

    -- Fill every available passenger seat
    local maxPassengers = GetVehicleMaxNumberOfPassengers(veh)
    for seat = 0, maxPassengers - 1 do
        local passHash = GetHashKey(driverModelName)
        loadModel(passHash)
        local pass = CreatePedInsideVehicle(veh, 26, passHash, seat, false, false)
        if pass and pass ~= 0 then
            SetEntityAsMissionEntity(pass, true, true)
            SetModelAsNoLongerNeeded(passHash)
            setupConvoyPed(pass, CONVOY_GROUP, 200, 50)
            GiveWeaponToPed(pass, GetHashKey('WEAPON_SMG'), 250, true, false)
            pcall(function() exports['actioncam']:AddTrackedPed(pass) end)
            pedsList[#pedsList + 1] = { ped = pass, tierName = 'Passenger', maxHP = 250, alive = true }
        else
            SetModelAsNoLongerNeeded(passHash)
        end
    end

    local entry = {
        veh      = veh,
        role     = role,
        label    = label,
        alive    = true,
        maxVehHP = 1000,
        colorR   = colorR,
        colorG   = colorG,
        colorB   = colorB,
        peds     = pedsList,
    }

    ConvoyVehicleLabels[veh] = { text = label, r = colorR, g = colorG, b = colorB }
    return entry
end

-- ─── Driving Tasks ────────────────────────────────────────────────────────────

local function issueDrivingTasks(force)
    local now  = GetGameTimer()
    local cfg  = Config.Convoy
    local dest = ConvoyState.routeEnd
    if not dest then return end

    if not (force or now >= ConvoyState.driveTimer) then return end
    ConvoyState.driveTimer = now + 4000

    local isAggro = (ConvoyState.mode == 'aggressive')
    local speed   = isAggro and cfg.AggressiveSpeed or cfg.PassiveSpeed

    for _, entry in ipairs(ConvoyState.convoyVehicles) do
        if not entry.alive or not entry.peds[1] then goto nextEntry end
        local driver = entry.peds[1].ped
        if not DoesEntityExist(driver) or IsEntityDead(driver) then goto nextEntry end
        if not IsPedInVehicle(driver, entry.veh, false) then
            SetPedIntoVehicle(driver, entry.veh, -1)
        end
        -- All convoy vehicles drive to the route end.
        -- Escorts run 4 m/s faster so they naturally catch up to VIP without
        -- needing formation math. GTA avoidance handles spacing between vehicles.
        local vehSpeed = (entry.role == 'escort') and (speed + 4.0) or speed
        TaskVehicleDriveToCoord(driver, entry.veh,
            dest.x, dest.y, dest.z, vehSpeed,
            1.0, GetEntityModel(entry.veh), 786603, 5.0, false)
        ::nextEntry::
    end
end

-- ─── Start / Stop ─────────────────────────────────────────────────────────────

function StartConvoy()
    if ConvoyState.active then return end

    CreateThread(function()
        initConvoyGroups()

        local cfg = Config.Convoy
        ConvoyState.active           = true
        ConvoyState.convoyVehicles   = {}
        ConvoyState.attackerVehicles = {}
        ConvoyState.mode             = 'passive'
        ConvoyState.lastAttackerSeen = 0
        ConvoyState.routeEnd         = vector3(cfg.End.x, cfg.End.y, cfg.End.z)
        ConvoyState.totalRouteDist   = 1.0  -- set after VehicleSpawns loop below
        ConvoyState.escortTimer      = 0
        ConvoyState.driveTimer       = 0

        -- Derive route start from first VIP entry for progress tracking
        local vipSpawn = cfg.VehicleSpawns[1]
        local startV   = vector3(vipSpawn.x, vipSpawn.y, vipSpawn.z)
        ConvoyState.totalRouteDist = math.max(1.0, #(ConvoyState.routeEnd - startV))

        -- Spawn all vehicles from VehicleSpawns config
        for _, spawnCfg in ipairs(cfg.VehicleSpawns) do
            local col   = spawnCfg.color or { 255, 215, 50 }
            local entry = spawnConvoyVehicle(
                spawnCfg.model,
                spawnCfg.driverModel or 's_m_y_swat_01',
                spawnCfg.x, spawnCfg.y, spawnCfg.z, spawnCfg.w,
                spawnCfg.role,
                spawnCfg.label or spawnCfg.role,
                col[1], col[2], col[3])
            if entry then
                table.insert(ConvoyState.convoyVehicles, entry)
                if spawnCfg.role == 'vip' and not ConvoyState.vipVeh then
                    ConvoyState.vipVeh = entry.veh
                end
            end
            Wait(300)
        end

        Wait(2000)
        issueDrivingTasks(true)

        -- ActionCam center between vip spawn and route end
        local midX = (vipSpawn.x + cfg.End.x) * 0.5
        local midY = (vipSpawn.y + cfg.End.y) * 0.5
        local midZ = (vipSpawn.z + cfg.End.z) * 0.5
        pcall(function()
            exports['actioncam']:StartActionCam({ center = { x = midX, y = midY, z = midZ } })
        end)

        SendReactMessage('updateConvoy', GetConvoyUIData())
        print('[Convoy] Started.')
    end)
end

function StopConvoy()
    if not ConvoyState.active then return end
    ConvoyState.active = false

    for _, entry in ipairs(ConvoyState.convoyVehicles) do
        for _, pd in ipairs(entry.peds) do
            ArenaLabels[pd.ped] = nil
            if DoesEntityExist(pd.ped) then
                pcall(function() exports['actioncam']:RemoveTrackedPed(pd.ped) end)
                DeletePed(pd.ped)
            end
        end
        if DoesEntityExist(entry.veh) then DeleteVehicle(entry.veh) end
        ConvoyVehicleLabels[entry.veh] = nil
    end

    for _, entry in ipairs(ConvoyState.attackerVehicles) do
        for _, pd in ipairs(entry.peds) do
            ArenaLabels[pd.ped] = nil
            if DoesEntityExist(pd.ped) then
                pcall(function() exports['actioncam']:RemoveTrackedPed(pd.ped) end)
                DeletePed(pd.ped)
            end
        end
        if DoesEntityExist(entry.veh) then DeleteVehicle(entry.veh) end
        ConvoyVehicleLabels[entry.veh] = nil
    end

    ConvoyState.convoyVehicles   = {}
    ConvoyState.attackerVehicles = {}
    ConvoyState.vipVeh           = nil
    ConvoyVehicleLabels          = {}

    pcall(function() exports['actioncam']:StopActionCam() end)
    SendReactMessage('updateConvoy', { active = false })
    print('[Convoy] Stopped.')
end

-- ─── Spawn Attacker Wave ──────────────────────────────────────────────────────

function SpawnConvoyAttackers(spawnData)
    if not ConvoyState.active or not ConvoyState.vipVeh then return end
    if not DoesEntityExist(ConvoyState.vipVeh) then return end

    CreateThread(function()
        local tierCfg = Config.Tiers[spawnData.tier]
        if not tierCfg then return end

        -- Spawn ahead of VIP so the convoy drives INTO the attackers immediately.
        local vipPos = GetEntityCoords(ConvoyState.vipVeh)
        local fwd    = GetEntityForwardVector(ConvoyState.vipVeh)
        local ahead  = Config.Convoy.AttackerSpawnAhead or 80.0
        local tx = vipPos.x + fwd.x * ahead
        local ty = vipPos.y + fwd.y * ahead
        local sx, sy, sz, sh = quickSpawnPos(tx, ty, vipPos.z)

        local vehModels = Config.Convoy.AttackerVehicleModels or { 'sultan' }
        local vehModel  = vehModels[math.random(#vehModels)]
        local vehHash   = GetHashKey(vehModel)
        loadModel(vehHash)

        local veh = CreateVehicle(vehHash, sx, sy, sz, sh, false, false)
        if not veh or veh == 0 then SetModelAsNoLongerNeeded(vehHash); return end
        SetModelAsNoLongerNeeded(vehHash)
        SetEntityAsMissionEntity(veh, true, true)
        SetVehicleEngineOn(veh, true, true, false)

        -- Orient toward VIP, then let physics settle briefly
        local dx = vipPos.x - sx
        local dy = vipPos.y - sy
        SetEntityHeading(veh, math.deg(math.atan(dx, dy)) % 360)
        Wait(100)
        SetVehicleOnGroundProperly(veh)

        local color     = Config.ViewerColors[spawnData.colorIndex] or { 255, 80, 80 }
        local relGroup  = getOrCreateViewerGroup(spawnData.owner)
        local pedModels = tierCfg.models or { tierCfg.model }
        local peds      = {}
        local maxSeat   = GetVehicleMaxNumberOfPassengers(veh) + 1

        for seatIdx = 0, maxSeat - 1 do
            local seat     = seatIdx - 1
            local pedModel = pedModels[math.random(#pedModels)]
            local pedHash  = GetHashKey(pedModel)
            loadModel(pedHash)
            local ped = CreatePedInsideVehicle(veh, 26, pedHash, seat, false, false)
            if not ped or ped == 0 then SetModelAsNoLongerNeeded(pedHash); goto nextSeat end
            SetEntityAsMissionEntity(ped, true, true)
            SetModelAsNoLongerNeeded(pedHash)
            setupAttackerPed(ped, relGroup, tierCfg)
            local weapons = tierCfg.weapons or { tierCfg.weapon }
            GiveWeaponToPed(ped, GetHashKey(weapons[math.random(#weapons)]), 250, true, false)
            -- Micro SMG is guaranteed drive-by capable; rifles/snipers from higher tiers
            -- cannot be used from a vehicle seat so peds just holster and re-draw endlessly.
            GiveWeaponToPed(ped, GetHashKey('WEAPON_MICRO_SMG'), 999, false, false)
            pcall(function() exports['actioncam']:AddTrackedPed(ped) end)
            local maxHP = (tierCfg.health or 100) + (tierCfg.armor or 0)
            table.insert(peds, { ped = ped, tierName = tierCfg.name, maxHP = maxHP, alive = true })
            ::nextSeat::
        end

        local maxVehHP = GetVehicleEngineHealth(veh)
        local label    = spawnData.owner .. ' · ' .. tierCfg.name
        ConvoyVehicleLabels[veh] = { text = label, r = color[1], g = color[2], b = color[3] }

        table.insert(ConvoyState.attackerVehicles, {
            veh        = veh,
            owner      = spawnData.owner,
            colorIndex = spawnData.colorIndex,
            alive      = true,
            maxVehHP   = maxVehHP,
            color      = color,
            label      = label,
            peds       = peds,
        })

        if #peds > 0 and ConvoyState.vipVeh and DoesEntityExist(ConvoyState.vipVeh) then
            local driver = peds[1].ped
            if not IsPedInVehicle(driver, veh, false) then
                SetPedIntoVehicle(driver, veh, -1)
            end
            TaskVehicleChase(driver, ConvoyState.vipVeh)
            -- Passengers: immediately start scanning for hated targets.
            -- Combined with CanDriveBy + Micro SMG this triggers drive-by behavior.
            for i = 2, #peds do
                if DoesEntityExist(peds[i].ped) then
                    TaskCombatHatedTargetsAroundPed(peds[i].ped, 150.0, 0)
                end
            end
        end
    end)
end

-- ─── HP Update ────────────────────────────────────────────────────────────────

local function updateHP()
    for _, entry in ipairs(ConvoyState.convoyVehicles) do
        if entry.alive then
            if not DoesEntityExist(entry.veh) or IsEntityDead(entry.veh)
                or GetVehicleEngineHealth(entry.veh) <= 0 then
                entry.alive = false
                ConvoyVehicleLabels[entry.veh] = nil
            end
        end
        for _, pd in ipairs(entry.peds) do
            if pd.alive and (not DoesEntityExist(pd.ped) or IsEntityDead(pd.ped)) then
                pd.alive = false
                ArenaLabels[pd.ped] = nil
                pcall(function() exports['actioncam']:RemoveTrackedPed(pd.ped) end)
                SchedulePedDeath(pd.ped)
            end
        end
        -- Crew wipe: if all occupants are dead, mark vehicle entry as dead too
        if entry.alive and #entry.peds > 0 then
            local anyAlive = false
            for _, pd in ipairs(entry.peds) do
                if pd.alive then anyAlive = true; break end
            end
            if not anyAlive then
                entry.alive = false
                ConvoyVehicleLabels[entry.veh] = nil
            end
        end
    end

    for _, entry in ipairs(ConvoyState.attackerVehicles) do
        if entry.alive then
            if not DoesEntityExist(entry.veh) or IsEntityDead(entry.veh)
                or GetVehicleEngineHealth(entry.veh) <= 0 then
                entry.alive = false
                ConvoyVehicleLabels[entry.veh] = nil
            end
        end
        for _, pd in ipairs(entry.peds) do
            if pd.alive and (not DoesEntityExist(pd.ped) or IsEntityDead(pd.ped)) then
                pd.alive = false
                ArenaLabels[pd.ped] = nil
                pcall(function() exports['actioncam']:RemoveTrackedPed(pd.ped) end)
                SchedulePedDeath(pd.ped)
            end
        end
        -- Crew wipe
        if entry.alive and #entry.peds > 0 then
            local anyAlive = false
            for _, pd in ipairs(entry.peds) do
                if pd.alive then anyAlive = true; break end
            end
            if not anyAlive then
                entry.alive = false
                ConvoyVehicleLabels[entry.veh] = nil
            end
        end
    end
end

-- ─── Foot Labels ──────────────────────────────────────────────────────────────
-- Show ArenaLabels for peds on foot; hide them when back inside any vehicle.

local function updateFootLabels()
    for _, entry in ipairs(ConvoyState.convoyVehicles) do
        local cr = entry.colorR or 255
        local cg = entry.colorG or 215
        local cb = entry.colorB or 50
        for _, pd in ipairs(entry.peds) do
            if pd.alive and DoesEntityExist(pd.ped) and not IsEntityDead(pd.ped) then
                if IsPedInAnyVehicle(pd.ped, false) then
                    ArenaLabels[pd.ped] = nil
                else
                    if not ArenaLabels[pd.ped] then
                        ArenaLabels[pd.ped] = { text = entry.label .. ' · ' .. pd.tierName, r = cr, g = cg, b = cb }
                    end
                end
            else
                ArenaLabels[pd.ped] = nil
            end
        end
    end
    for _, entry in ipairs(ConvoyState.attackerVehicles) do
        local col = entry.color or { 255, 80, 80 }
        for _, pd in ipairs(entry.peds) do
            if pd.alive and DoesEntityExist(pd.ped) and not IsEntityDead(pd.ped) then
                if IsPedInAnyVehicle(pd.ped, false) then
                    ArenaLabels[pd.ped] = nil
                else
                    if not ArenaLabels[pd.ped] then
                        ArenaLabels[pd.ped] = { text = entry.owner .. ' · ' .. pd.tierName, r = col[1], g = col[2], b = col[3] }
                    end
                end
            else
                ArenaLabels[pd.ped] = nil
            end
        end
    end
end

-- ─── Mode Check ───────────────────────────────────────────────────────────────

local function checkMode()
    if not ConvoyState.active or not ConvoyState.vipVeh then return end
    if not DoesEntityExist(ConvoyState.vipVeh) then return end

    local vipPos    = GetEntityCoords(ConvoyState.vipVeh)
    local radius    = Config.Convoy.AggroRadius
    local hasNearby = false

    for _, atk in ipairs(ConvoyState.attackerVehicles) do
        if atk.alive and DoesEntityExist(atk.veh) then
            if #(GetEntityCoords(atk.veh) - vipPos) < radius then
                hasNearby = true; break
            end
        end
    end

    local now = GetGameTimer()
    if hasNearby then
        ConvoyState.lastAttackerSeen = now
        if ConvoyState.mode ~= 'aggressive' then
            ConvoyState.mode = 'aggressive'
            SendReactMessage('convoyMode', 'aggressive')
            issueDrivingTasks(true)
        end
    else
        local cooldownMs = (Config.Convoy.PassiveCooldown or 12.0) * 1000
        if ConvoyState.mode == 'aggressive' and (now - ConvoyState.lastAttackerSeen) > cooldownMs then
            ConvoyState.mode = 'passive'
            SendReactMessage('convoyMode', 'passive')
            issueDrivingTasks(true)
        end
    end
end

-- ─── Completion Check ─────────────────────────────────────────────────────────

local function checkComplete()
    if not ConvoyState.active or not ConvoyState.vipVeh then return end

    if not DoesEntityExist(ConvoyState.vipVeh) or IsEntityDead(ConvoyState.vipVeh)
        or GetVehicleEngineHealth(ConvoyState.vipVeh) <= 0 then
        TriggerServerEvent('convoy:vipDestroyed')
        StopConvoy()
        SendReactMessage('convoyResult', { result = 'failure', reason = 'VIP destroyed' })
        return
    end

    local vipPos    = GetEntityCoords(ConvoyState.vipVeh)
    local distToEnd = #(vipPos - ConvoyState.routeEnd)
    if distToEnd < 20.0 then
        TriggerServerEvent('convoy:vipArrived')
        StopConvoy()
        SendReactMessage('convoyResult', { result = 'success', reason = 'VIP reached destination' })
    end
end

-- ─── NUI Data ─────────────────────────────────────────────────────────────────

function GetConvoyUIData()
    if not ConvoyState.active then return { active = false } end

    local progress = 0.0
    if ConvoyState.vipVeh and DoesEntityExist(ConvoyState.vipVeh) then
        local d = #(GetEntityCoords(ConvoyState.vipVeh) - ConvoyState.routeEnd)
        progress = math.max(0.0, math.min(1.0, 1.0 - d / ConvoyState.totalRouteDist))
    end

    local convoyOut = {}
    for _, entry in ipairs(ConvoyState.convoyVehicles) do
        local vehHP  = (entry.alive and DoesEntityExist(entry.veh)) and GetVehicleEngineHealth(entry.veh) or 0
        local vehPct = math.max(0, math.min(1, vehHP / math.max(1, entry.maxVehHP)))
        local peds   = {}
        for _, pd in ipairs(entry.peds) do
            local hp  = combinedPedHP(pd.ped)
            local pct = pd.alive and math.max(0, math.min(1, hp / math.max(1, pd.maxHP))) or 0
            table.insert(peds, { tierName = pd.tierName, pct = pct, alive = pd.alive })
        end
        table.insert(convoyOut, {
            role   = entry.role,
            label  = entry.label,
            vehPct = vehPct,
            alive  = entry.alive,
            colorR = entry.colorR,
            colorG = entry.colorG,
            colorB = entry.colorB,
            peds   = peds,
        })
    end

    local byOwner = {}
    for _, entry in ipairs(ConvoyState.attackerVehicles) do
        if not byOwner[entry.owner] then
            byOwner[entry.owner] = { owner = entry.owner, color = entry.color, vehicles = {} }
        end
        local vehHP  = (entry.alive and DoesEntityExist(entry.veh)) and GetVehicleEngineHealth(entry.veh) or 0
        local vehPct = math.max(0, math.min(1, vehHP / math.max(1, entry.maxVehHP)))
        local peds   = {}
        for _, pd in ipairs(entry.peds) do
            local hp  = combinedPedHP(pd.ped)
            local pct = pd.alive and math.max(0, math.min(1, hp / math.max(1, pd.maxHP))) or 0
            table.insert(peds, { tierName = pd.tierName, pct = pct, alive = pd.alive })
        end
        table.insert(byOwner[entry.owner].vehicles, {
            label  = entry.label,
            vehPct = vehPct,
            alive  = entry.alive,
            peds   = peds,
        })
    end
    local attackers = {}
    for _, g in pairs(byOwner) do table.insert(attackers, g) end

    return {
        active    = true,
        mode      = ConvoyState.mode,
        progress  = progress,
        convoy    = convoyOut,
        attackers = attackers,
    }
end

-- ─── Convoy Passenger Engagement ─────────────────────────────────────────────
-- Drivers stay on their drive task (SetBlockingOfNonTemporaryEvents + SetPedKeepTask).
-- Passengers get explicit shoot tasks issued every 4 s with a 6 s duration so the
-- animation state machine isn't constantly reset (the old 1 s / 2 s rhythm did that).

local function checkConvoyEngagement()
    if ConvoyState.mode ~= 'aggressive' then return end
    local now = GetGameTimer()
    if now < convoyEngagementTimer then return end
    convoyEngagementTimer = now + 8000

    for _, entry in ipairs(ConvoyState.convoyVehicles) do
        if not entry.alive or not DoesEntityExist(entry.veh) then goto nextVeh end
        -- Kick all passengers into active combat scan; drivers stay on drive task.
        -- TaskCombatHatedTargetsAroundPed persists until all targets are gone so we
        -- only need to re-issue every 8 s if somehow the combat state dropped.
        for i = 2, #entry.peds do
            local pd = entry.peds[i]
            if pd.alive and DoesEntityExist(pd.ped) and not IsEntityDead(pd.ped)
                and not IsPedInCombat(pd.ped)
            then
                TaskCombatHatedTargetsAroundPed(pd.ped, 150.0, 0)
            end
        end
        ::nextVeh::
    end
end

-- ─── Attacker Re-entry ────────────────────────────────────────────────────────
-- If an attacker ped exits their vehicle and is no longer in combat, send them
-- back to their seat so they can continue chasing the VIP.

local function checkAttackerReentry()
    if not ConvoyState.vipVeh or not DoesEntityExist(ConvoyState.vipVeh) then return end

    for _, entry in ipairs(ConvoyState.attackerVehicles) do
        if entry.alive and DoesEntityExist(entry.veh) and not IsEntityDead(entry.veh) then
            for pedIdx, pd in ipairs(entry.peds) do
                if pd.alive and DoesEntityExist(pd.ped) and not IsEntityDead(pd.ped) then
                    if IsPedInAnyVehicle(pd.ped, false) then
                        if pedIdx == 1 then
                            if GetEntitySpeed(entry.veh) < 0.5 and not IsPedInCombat(pd.ped) then
                                TaskVehicleChase(pd.ped, ConvoyState.vipVeh)
                            end
                        else
                            -- Passenger idle — kick into active combat scan
                            if not IsPedInCombat(pd.ped) then
                                TaskCombatHatedTargetsAroundPed(pd.ped, 150.0, 0)
                            end
                        end
                    elseif not IsPedInCombat(pd.ped) then
                        local seat = (pedIdx == 1) and -1 or (pedIdx - 2)
                        TaskEnterVehicle(pd.ped, entry.veh, 10000, seat, 2.0, 1, 0)
                    end
                end
            end
        end
    end
end

-- ─── Threads ──────────────────────────────────────────────────────────────────

-- Logic tick (1 s): HP, mode, foot labels, re-entry, driving re-issue, completion
CreateThread(function()
    while true do
        Wait(1000)
        if ConvoyState.active then
            updateHP()
            checkMode()
            updateFootLabels()
            checkConvoyEngagement()
            checkAttackerReentry()
            issueDrivingTasks(false)
            checkComplete()
        end
    end
end)

-- Vehicle label draw thread
CreateThread(function()
    while true do
        Wait(0)
        if ConvoyState.active then
            for veh, info in pairs(ConvoyVehicleLabels) do
                if DoesEntityExist(veh) and not IsEntityDead(veh) then
                    local coords = GetEntityCoords(veh)
                    local onScreen, sx, sy = World3dToScreen2d(coords.x, coords.y, coords.z + 1.6)
                    if onScreen then
                        local camPos = GetGameplayCamCoords()
                        local dist   = #(camPos - coords)
                        if dist < Config.LabelDrawDistance then
                            local scale = math.max(0.28, 0.42 * (1.0 - dist / Config.LabelDrawDistance * 0.6))
                            local sz    = scale / 0.28
                            local bgW   = (math.max(0.04, #info.text * 0.0055) + 0.014) * sz
                            local bgH   = 0.024 * sz
                            DrawRect(sx, sy, bgW, bgH, 0, 0, 0, 160)
                            SetTextScale(scale, scale)
                            SetTextFont(4)
                            SetTextProportional(true)
                            SetTextColour(info.r, info.g, info.b, 230)
                            SetTextOutline()
                            SetTextEntry('STRING')
                            SetTextCentre(true)
                            AddTextComponentString(info.text)
                            DrawText(sx, sy - 0.008)
                        end
                    end
                else
                    ConvoyVehicleLabels[veh] = nil
                end
            end
        end
    end
end)

-- ─── Net Events ───────────────────────────────────────────────────────────────

RegisterNetEvent('convoy:start', function()
    StartConvoy()
end)

RegisterNetEvent('convoy:stop', function()
    StopConvoy()
end)

RegisterNetEvent('convoy:spawnAttackers', function(data)
    SpawnConvoyAttackers(data)
end)
