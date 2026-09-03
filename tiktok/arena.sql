-- Arena Attack & Defend — database setup
-- Run this once against your tiktok1 database, then restart the resource.

CREATE TABLE IF NOT EXISTS arena_viewers (
    id             INT AUTO_INCREMENT PRIMARY KEY,
    username       VARCHAR(100) NOT NULL UNIQUE,
    tiktok_user    VARCHAR(100) DEFAULT NULL,
    points         INT NOT NULL DEFAULT 0,
    team_id        INT DEFAULT NULL,
    total_damage   INT NOT NULL DEFAULT 0,
    total_kills    INT NOT NULL DEFAULT 0,
    waves_sent     INT NOT NULL DEFAULT 0,
    created_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS arena_teams (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(50)  NOT NULL UNIQUE,
    created_by  VARCHAR(100) NOT NULL,
    color_index INT NOT NULL DEFAULT 1,
    wins        INT NOT NULL DEFAULT 0,
    losses      INT NOT NULL DEFAULT 0,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS arena_wave_history (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    team_id      INT NOT NULL,
    team_name    VARCHAR(50)  NOT NULL,
    sent_by      VARCHAR(100) NOT NULL,
    wave_data    JSON DEFAULT NULL,
    total_cost   INT NOT NULL DEFAULT 0,
    damage_dealt INT NOT NULL DEFAULT 0,
    kills        INT NOT NULL DEFAULT 0,
    outcome      ENUM('ongoing','victory','defeat') NOT NULL DEFAULT 'ongoing',
    sent_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
