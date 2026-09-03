ActionCamConfig = {}

-- Close-up follow-behind settings
ActionCamConfig.PedDuration      = 5.0    -- seconds on one NPC before switching
ActionCamConfig.Fov              = 52.0
ActionCamConfig.FollowDist       = 7.0    -- units behind the NPC
ActionCamConfig.FollowHeight     = 2.2    -- height above feet
ActionCamConfig.FollowSpeed      = 4.5    -- lerp speed (2 = floaty, 8 = snappy)

-- Orbit speed when the tracked NPC is idle (not in combat)
ActionCamConfig.IdleOrbitSpeed   = 6.0    -- deg/s
ActionCamConfig.IdleOrbitRadius  = 5.5
ActionCamConfig.IdleOrbitHeight  = 1.8

-- Aerial mode (hover above centroid of all active peds)
-- Set to 0 (disabled) — only activates during downtime between rounds
ActionCamConfig.AerialEvery      = 0
ActionCamConfig.AerialDuration   = 7.0
ActionCamConfig.AerialBaseHeight = 30.0
ActionCamConfig.AerialMaxHeight  = 70.0
ActionCamConfig.AerialSpreadMul  = 0.9
ActionCamConfig.AerialRadius     = 12.0
ActionCamConfig.AerialSpeed      = 4.0
ActionCamConfig.AerialFov        = 65.0

-- Overview mode (fixed orbit around opts.center — disabled by default)
ActionCamConfig.OverviewEvery    = 0
ActionCamConfig.OverviewDuration = 5.0
ActionCamConfig.OverviewRadius   = 90.0
ActionCamConfig.OverviewHeight   = 45.0
ActionCamConfig.OverviewSpeed    = 5.0
ActionCamConfig.OverviewFov      = 62.0

-- Set true to enable /acamplace, /acamprev, /acamexport etc.
ActionCamConfig.EnableConfigTool     = true

-- Venue cameras (supplied via opts.venueCams)
-- How close the action centroid must be to a proximity-tagged venue cam for it
-- to be eligible during active fighting.
ActionCamConfig.VenueProximityRadius = 120.0
-- How long to stay on a venue camera before returning to ped/aerial tracking.
ActionCamConfig.VenueDuration        = 10.0
