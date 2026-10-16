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

CREATE TABLE IF NOT EXISTS crew_members (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(128) NOT NULL,
    role VARCHAR(96) NOT NULL,
    assignment VARCHAR(160) NOT NULL,
    status VARCHAR(32) NOT NULL DEFAULT 'ACTIVE'
);



INSERT INTO users (id, username, display_name, password_hash, role, active)
VALUES
    (1, 'jmoney', 'J-Money', '$2b$12$5YJoIlMy4qpRdwC9W9fTDegu0kYa9j0T/HOz.QiqEHhs/ZsQiSDHi', 'operator', 1),
    (2, 'plinktern', 'Plinktern Administrator', '$2b$12$5YJoIlMy4qpRdwC9W9fTDegu0kYa9j0T/HOz.QiqEHhs/ZsQiSDHi', 'admin', 1)
ON DUPLICATE KEY UPDATE active = 1;

INSERT INTO crew_members (id, full_name, role, assignment, status)
VALUES
    (1, 'J-Money', 'Flight Director', 'Guidance authority and mission command', 'ACTIVE'),
    (2, 'PlinkAI', 'Autonomous Pilot', 'EQUUS I flight-control core', 'ACTIVE'),
    (3, 'Horse Unit 07', 'Mission Specialist', 'Lunar payload operations', 'NOMINAL'),
    (4, 'Dr. Hayley Trotter', 'Payload Scientist', 'Plinko Sauce stability', 'ACTIVE'),
    (5, 'Kevin Kiderchah XIV', 'Mission Director', 'Executive launch approval', 'REMOTE')
ON DUPLICATE KEY UPDATE full_name = VALUES(full_name), role = VALUES(role), assignment = VALUES(assignment), status = VALUES(status);


INSERT INTO rockets (callsign, mission, status, phase, altitude_km, velocity_kms, fuel_percent, engine_temp_c)
VALUES ('EQUUS I', 'Mission Fortuna', 'NOMINAL', 'ORBITAL INSERTION', 384402.00, 1.287, 67.40, 118.60)
ON DUPLICATE KEY UPDATE mission = VALUES(mission), status = VALUES(status);

INSERT INTO mission_events (rocket_id, severity, event_text)
SELECT id, 'INFO', 'Guidance uplink authenticated; vehicle telemetry nominal.' FROM rockets
WHERE callsign = 'EQUUS I' AND NOT EXISTS (SELECT 1 FROM mission_events WHERE event_text = 'Guidance uplink authenticated; vehicle telemetry nominal.');

INSERT INTO mission_events (rocket_id, severity, event_text)
SELECT id, 'NOTICE', 'Plinko Sauce mixture holding at flight specification.' FROM rockets
WHERE callsign = 'EQUUS I' AND NOT EXISTS (SELECT 1 FROM mission_events WHERE event_text = 'Plinko Sauce mixture holding at flight specification.');
