<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
require_auth();
$events = [];
try { $events = db()->query('SELECT r.callsign, e.severity, e.event_text, e.occurred_at FROM mission_events e JOIN rockets r ON r.id=e.rocket_id ORDER BY e.occurred_at DESC LIMIT 50')->fetch_all(MYSQLI_ASSOC); } catch (Throwable $e) { error_log($e->getMessage()); }
page_top('Mission Logs', '/mission-logs.php');
?>
<div class="page-heading"><p class="eyebrow">FLIGHT RECORDS</p><h1>Mission Logs</h1><p>Authenticated events received through the Guidance relay.</p></div>
<section class="card"><table><thead><tr><th>UTC TIME</th><th>VEHICLE</th><th>LEVEL</th><th>EVENT</th></tr></thead><tbody><?php foreach ($events as $event): ?><tr><td><?= e($event['occurred_at']) ?></td><td><?= e($event['callsign']) ?></td><td><?= e($event['severity']) ?></td><td><?= e($event['event_text']) ?></td></tr><?php endforeach; ?></tbody></table></section>
<?php page_bottom(); ?>
