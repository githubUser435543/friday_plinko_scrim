<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
require_auth();

$rocket = null;
$events = [];
$dbError = false;
try {
    $rocket = db()->query("SELECT * FROM rockets WHERE callsign = 'EQUUS I' LIMIT 1")->fetch_assoc();
    if ($rocket) {
        $stmt = db()->prepare('SELECT severity, event_text, occurred_at FROM mission_events WHERE rocket_id = ? ORDER BY occurred_at DESC LIMIT 5');
        $stmt->bind_param('i', $rocket['id']);
        $stmt->execute();
        $events = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
    }
} catch (Throwable $exception) {
    error_log($exception->getMessage());
    $dbError = true;
}

page_top('Dashboard');
?>
<section class="mission-head">
  <div class="mission-emblem">♞</div>
  <div><p class="eyebrow">JMONEY // MISSION CONTROL</p><h1>EQUUS I</h1><p>Lunar Payload Mission</p></div>
  <div class="clockbox"><small>MISSION ELAPSED TIME</small><b id="mission-clock">T+ 5:14:01:11</b></div>
</section>

<section class="section-title"><span>FLIGHT DYNAMICS / MISSION RELAY</span><b>COMPRESSED SYSTEMS SCALE</b></section>
<div class="notice">LIVE CONFIGURATION / SCRIM MODE <span>Relay follows the mission packet; decorative controls are labeled.</span></div>

<?php if ($dbError || !$rocket): ?>
  <div class="critical">MANIFEST DATA LINK LOST — CHECK MARIA DB CONNECTIVITY</div>
<?php else: ?>
<section class="status-strip">
  <div><small>VEHICLE</small><strong><?= e($rocket['callsign']) ?></strong></div>
  <div><small>MISSION</small><strong><?= e($rocket['mission']) ?></strong></div>
  <div><small>PHASE</small><strong><?= e($rocket['phase']) ?></strong></div>
  <div><small>FLIGHT STATUS</small><strong class="nominal"><i></i><?= e($rocket['status']) ?></strong></div>
</section>

<div class="tabs"><button class="selected" data-panel="trajectory">TRAJECTORY</button><button data-panel="telemetry">TELEMETRY</button><button data-panel="events">MISSION LOG</button></div>
<section id="trajectory" class="panel active-panel">
  <div class="panel-label"><span>FLIGHT VIEW</span><small>EARTH–MOON TRANSFER / EQUUS 01</small></div>
  <div class="orbit-chart"><div class="earth">EARTH</div><div class="orbit-line"><span class="vehicle">PLK-0004-01 / EQUUS I</span></div><div class="moon">MOON</div><div class="grid"></div></div>
</section>
<section id="telemetry" class="panel">
  <div class="telemetry-grid">
    <article><small>ALTITUDE</small><b><?= number_format((float)$rocket['altitude_km'], 2) ?></b><span>KM</span></article>
    <article><small>VELOCITY</small><b><?= number_format((float)$rocket['velocity_kms'], 3) ?></b><span>KM/S</span></article>
    <article><small>PLINKO SAUCE</small><b><?= number_format((float)$rocket['fuel_percent'], 1) ?></b><span>PERCENT</span></article>
    <article><small>ENGINE TEMP</small><b><?= number_format((float)$rocket['engine_temp_c'], 1) ?></b><span>°C</span></article>
  </div>
</section>
<section id="events" class="panel">
  <table><thead><tr><th>TIME</th><th>LEVEL</th><th>EVENT</th></tr></thead><tbody>
  <?php foreach ($events as $event): ?><tr><td><?= e($event['occurred_at']) ?></td><td><?= e($event['severity']) ?></td><td><?= e($event['event_text']) ?></td></tr><?php endforeach; ?>
  </tbody></table>
</section>
<?php endif; ?>
<?php page_bottom(); ?>
