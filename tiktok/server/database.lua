DB = {}
-- Tables are created via arena.sql — run that file once before starting the resource.

-- ---------------------------------------------------------------------------
-- Viewers
-- ---------------------------------------------------------------------------
function DB.getOrCreateViewer(username)
    local rows = MySQL.query.await('SELECT * FROM arena_viewers WHERE username = ?', { username })
    if rows and #rows > 0 then return rows[1] end

    local id = MySQL.insert.await('INSERT INTO arena_viewers (username) VALUES (?)', { username })
    return { id = id, username = username, points = 0, team_id = nil, total_damage = 0, total_kills = 0, waves_sent = 0 }
end

function DB.getViewer(username)
    local rows = MySQL.query.await('SELECT * FROM arena_viewers WHERE username = ?', { username })
    return rows and rows[1] or nil
end

function DB.addPoints(username, amount)
    MySQL.query.await('UPDATE arena_viewers SET points = GREATEST(0, points + ?) WHERE username = ?', { amount, username })
end

function DB.getPoints(username)
    local rows = MySQL.query.await('SELECT points FROM arena_viewers WHERE username = ?', { username })
    return rows and rows[1] and rows[1].points or 0
end

function DB.updateViewerStats(username, damage, kills)
    MySQL.query.await([[
        UPDATE arena_viewers
        SET total_damage = total_damage + ?,
            total_kills  = total_kills  + ?,
            waves_sent   = waves_sent   + 1
        WHERE username = ?
    ]], { damage, kills, username })
end

-- ---------------------------------------------------------------------------
-- Teams
-- ---------------------------------------------------------------------------
function DB.getTeamByName(name)
    local rows = MySQL.query.await('SELECT * FROM arena_teams WHERE name = ?', { name })
    return rows and rows[1] or nil
end

function DB.getTeamById(id)
    local rows = MySQL.query.await('SELECT * FROM arena_teams WHERE id = ?', { id })
    return rows and rows[1] or nil
end

function DB.createTeam(name, createdBy, colorIndex)
    local id = MySQL.insert.await(
        'INSERT INTO arena_teams (name, created_by, color_index) VALUES (?, ?, ?)',
        { name, createdBy, colorIndex }
    )
    return id
end

function DB.countTeams()
    local rows = MySQL.query.await('SELECT COUNT(*) as total FROM arena_teams', {})
    return rows and rows[1] and rows[1].total or 0
end

function DB.joinTeam(username, teamId)
    MySQL.query.await('UPDATE arena_viewers SET team_id = ? WHERE username = ?', { teamId, username })
end

function DB.recordTeamResult(teamId, outcome)
    if outcome == 'victory' then
        MySQL.query.await('UPDATE arena_teams SET wins = wins + 1 WHERE id = ?', { teamId })
    elseif outcome == 'defeat' then
        MySQL.query.await('UPDATE arena_teams SET losses = losses + 1 WHERE id = ?', { teamId })
    end
end

function DB.getTeamMembers(teamId)
    local rows = MySQL.query.await('SELECT * FROM arena_viewers WHERE team_id = ?', { teamId })
    return rows or {}
end

-- ---------------------------------------------------------------------------
-- Wave history
-- ---------------------------------------------------------------------------
function DB.recordWave(teamId, teamName, sentBy, waveData, totalCost)
    return MySQL.insert.await([[
        INSERT INTO arena_wave_history (team_id, team_name, sent_by, wave_data, total_cost)
        VALUES (?, ?, ?, ?, ?)
    ]], { teamId, teamName, sentBy, json.encode(waveData), totalCost })
end

-- Viewer-only variant — uses the viewer's own DB id as the team_id column.
function DB.recordViewerWave(username, waveData, totalCost)
    local viewer = DB.getOrCreateViewer(username)
    return MySQL.insert.await([[
        INSERT INTO arena_wave_history (team_id, team_name, sent_by, wave_data, total_cost)
        VALUES (?, ?, ?, ?, ?)
    ]], { viewer.id, username, username, json.encode(waveData), totalCost })
end

function DB.finaliseWave(waveId, damageDealt, kills, outcome)
    MySQL.query.await([[
        UPDATE arena_wave_history
        SET damage_dealt = ?, kills = ?, outcome = ?
        WHERE id = ?
    ]], { damageDealt, kills, outcome, waveId })
end

-- ---------------------------------------------------------------------------
-- Leaderboard
-- ---------------------------------------------------------------------------
function DB.getLeaderboard()
    return MySQL.query.await([[
        SELECT v.username, t.name AS team_name, t.color_index,
               v.points, v.total_damage, v.total_kills, v.waves_sent
        FROM arena_viewers v
        LEFT JOIN arena_teams t ON v.team_id = t.id
        ORDER BY v.total_damage DESC
        LIMIT 15
    ]], {}) or {}
end

function DB.getTeamLeaderboard()
    return MySQL.query.await([[
        SELECT t.name, t.color_index, t.wins, t.losses,
               COALESCE(SUM(v.total_damage), 0) AS total_damage
        FROM arena_teams t
        LEFT JOIN arena_viewers v ON v.team_id = t.id
        GROUP BY t.id
        ORDER BY total_damage DESC
        LIMIT 10
    ]], {}) or {}
end
