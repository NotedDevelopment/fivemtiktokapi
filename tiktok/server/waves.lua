Waves = {}

-- ---------------------------------------------------------------------------
-- calculateComposition
-- Given a point budget, returns the best wave the viewer can afford.
--
-- Returns:
--   composition  : array of { tier, tierName, count }
--   totalCost    : points that will be deducted
--   totalPeds    : total ped count across all tiers
-- ---------------------------------------------------------------------------
function Waves.calculateComposition(points)
    local composition = {}
    local remaining   = points
    local totalPeds   = 0

    local maxPeds = Config.WaveCapEnabled and Config.MaxPedsPerWave or math.huge
    local maxTier = Config.MaxTierPerWave  or #Config.Tiers

    -- Greedy: fill with highest affordable tier first, then drop down
    for tier = maxTier, 1, -1 do
        local cfg = Config.Tiers[tier]
        if cfg and remaining >= cfg.cost and totalPeds < maxPeds then
            local canAfford = math.floor(remaining / cfg.cost)
            local allowed   = math.min(canAfford, maxPeds - totalPeds)
            if allowed > 0 then
                table.insert(composition, {
                    tier     = tier,
                    tierName = cfg.name,
                    count    = allowed,
                })
                remaining  = remaining - (allowed * cfg.cost)
                totalPeds  = totalPeds + allowed
            end
        end
        if totalPeds >= maxPeds then break end
    end

    return {
        composition = composition,
        totalCost   = points - remaining,
        totalPeds   = totalPeds,
    }
end

-- ---------------------------------------------------------------------------
-- describeWave
-- Human-readable summary string for chat notifications.
-- ---------------------------------------------------------------------------
function Waves.describeWave(result)
    if result.totalPeds == 0 then return 'empty wave' end
    local parts = {}
    for _, c in ipairs(result.composition) do
        table.insert(parts, c.count .. 'x ' .. c.tierName)
    end
    return table.concat(parts, ', ') .. ' (' .. result.totalCost .. ' pts)'
end
