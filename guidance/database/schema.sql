CREATE DATABASE IF NOT EXISTS plinkcom CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE plinkcom;

CREATE TABLE IF NOT EXISTS users (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL UNIQUE,
    display_name VARCHAR(128) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('operator','admin') NOT NULL DEFAULT 'operator',
    active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS rockets (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    callsign VARCHAR(64) NOT NULL UNIQUE,
    mission VARCHAR(128) NOT NULL,
    status ENUM('NOMINAL','HOLD','ABORT') NOT NULL DEFAULT 'NOMINAL',
    phase VARCHAR(64) NOT NULL,
    altitude_km DECIMAL(10,2) NOT NULL DEFAULT 0,
    velocity_kms DECIMAL(8,3) NOT NULL DEFAULT 0,
    fuel_percent DECIMAL(5,2) NOT NULL DEFAULT 100,
    engine_temp_c DECIMAL(7,2) NOT NULL DEFAULT 21,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS mission_events (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    rocket_id INT UNSIGNED NOT NULL,
    severity ENUM('INFO','NOTICE','WARNING') NOT NULL DEFAULT 'INFO',
    event_text VARCHAR(255) NOT NULL,
    occurred_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_event_rocket FOREIGN KEY (rocket_id) REFERENCES rockets(id) ON DELETE CASCADE
);

INSERT INTO users (username, display_name, password_hash, role, active)
VALUES
    ('jmoney', 'J-Money', '$2b$12$5YJoIlMy4qpRdwC9W9fTDegu0kYa9j0T/HOz.QiqEHhs/ZsQiSDHi', 'operator', 1),
    ('plinktern', 'Plinktern Administrator', '$2b$12$5YJoIlMy4qpRdwC9W9fTDegu0kYa9j0T/HOz.QiqEHhs/ZsQiSDHi', 'admin', 1)
ON DUPLICATE KEY UPDATE display_name = VALUES(display_name), active = 1;

INSERT INTO rockets (callsign, mission, status, phase, altitude_km, velocity_kms, fuel_percent, engine_temp_c)
VALUES ('EQUUS I', 'Mission Fortuna', 'NOMINAL', 'ORBITAL INSERTION', 384402.00, 1.287, 67.40, 118.60)
ON DUPLICATE KEY UPDATE mission = VALUES(mission);

INSERT INTO mission_events (rocket_id, severity, event_text)
SELECT id, 'INFO', 'Guidance uplink authenticated; vehicle telemetry nominal.'
FROM rockets r
WHERE callsign = 'EQUUS I'
  AND NOT EXISTS (SELECT 1 FROM mission_events WHERE event_text = 'Guidance uplink authenticated; vehicle telemetry nominal.');

INSERT INTO mission_events (rocket_id, severity, event_text)
SELECT id, 'NOTICE', 'Plinko Sauce mixture holding at flight specification.'
FROM rockets r
WHERE callsign = 'EQUUS I'
  AND NOT EXISTS (SELECT 1 FROM mission_events WHERE event_text = 'Plinko Sauce mixture holding at flight specification.');
