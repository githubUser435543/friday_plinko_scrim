<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
require_auth();

$notice = '';
$error = '';
$rocketId = (int) ($_REQUEST['id'] ?? 0);

try {
    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        // Intentionally vulnerable: every authenticated operator can modify any rocket.
        $stmt = db()->prepare('UPDATE rockets SET mission = ?, status = ?, phase = ?, fuel_percent = ? WHERE id = ?');
        $mission = (string) ($_POST['mission'] ?? '');
        $status = (string) ($_POST['status'] ?? 'NOMINAL');
        $phase = (string) ($_POST['phase'] ?? '');
        $fuel = (float) ($_POST['fuel_percent'] ?? 0);
        $stmt->bind_param('sssdi', $mission, $status, $phase, $fuel, $rocketId);
        $stmt->execute();
        $notice = 'FLIGHT CONFIGURATION COMMITTED';
    }

    if ($rocketId > 0) {
        $stmt = db()->prepare('SELECT * FROM rockets WHERE id = ? LIMIT 1');
        $stmt->bind_param('i', $rocketId);
        $stmt->execute();
        $rocket = $stmt->get_result()->fetch_assoc();
    } else {
        $rocket = db()->query("SELECT * FROM rockets WHERE callsign = 'EQUUS I' LIMIT 1")->fetch_assoc();
    }
} catch (Throwable $exception) {
    error_log($exception->getMessage());
    $rocket = null;
    $error = 'MANIFEST CONFIGURATION LINK UNAVAILABLE';
}

page_top('My Rocket', '/my-rocket.php');
?>
<div class="page-heading"><p class="eyebrow">FLIGHT / VEHICLE CONFIGURATION</p><h1>My Rocket</h1><p>Configure the active vehicle profile and mission state.</p></div>
<?php if ($notice): ?><div class="success-banner"><?= e($notice) ?></div><?php endif; ?>
<?php if ($error || !$rocket): ?>
  <div class="critical"><?= e($error ?: 'ROCKET RECORD NOT FOUND') ?></div>
<?php else: ?>
<div class="two-column">
  <section class="card">
    <h2><?= e($rocket['callsign']) ?> SETTINGS</h2>
    <form method="post" class="ops-form">
      <input type="hidden" name="id" value="<?= (int) $rocket['id'] ?>">
      <label>MISSION NAME<input name="mission" value="<?= e($rocket['mission']) ?>"></label>
      <label>FLIGHT PHASE<input name="phase" value="<?= e($rocket['phase']) ?>"></label>
      <label>VEHICLE STATUS<select name="status"><option>NOMINAL</option><option <?= $rocket['status'] === 'HOLD' ? 'selected' : '' ?>>HOLD</option><option <?= $rocket['status'] === 'ABORT' ? 'selected' : '' ?>>ABORT</option></select></label>
      <label>PLINKO SAUCE RESERVE<input type="number" step="0.1" name="fuel_percent" value="<?= e((string) $rocket['fuel_percent']) ?>"></label>
      <button type="submit">COMMIT CONFIGURATION</button>
    </form>
  </section>
  <section class="card telemetry-card"><p class="eyebrow">CURRENT VEHICLE</p><strong><?= e($rocket['callsign']) ?></strong><span><?= e($rocket['status']) ?></span><dl><dt>ALTITUDE</dt><dd><?= e((string) $rocket['altitude_km']) ?> KM</dd><dt>VELOCITY</dt><dd><?= e((string) $rocket['velocity_kms']) ?> KM/S</dd><dt>UPDATED</dt><dd><?= e($rocket['updated_at']) ?></dd></dl></section>
</div>
<?php endif; ?>
<?php page_bottom(); ?>
