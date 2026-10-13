<?php
require_once dirname(__DIR__, 2) . '/app/bootstrap.php';
header('Content-Type: application/json');
try {
    $rocket = db()->query("SELECT callsign, mission, status, phase, altitude_km, velocity_kms, fuel_percent, engine_temp_c, updated_at FROM rockets WHERE callsign='EQUUS I' LIMIT 1")->fetch_assoc();
    if (!$rocket) { http_response_code(404); echo json_encode(['ok' => false, 'error' => 'rocket not found']); exit; }
    echo json_encode(['ok' => true, 'rocket' => $rocket], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
} catch (Throwable $exception) {
    error_log($exception->getMessage());
    http_response_code(503);
    echo json_encode(['ok' => false, 'error' => 'manifest link unavailable']);
}
