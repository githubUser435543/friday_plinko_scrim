<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
require_auth();

$events = [];
try {
    $events = db()->query('SELECT r.callsign, e.severity, e.event_text, e.occurred_at FROM mission_events e JOIN rockets r ON r.id=e.rocket_id ORDER BY e.occurred_at DESC LIMIT 50')->fetch_all(MYSQLI_ASSOC);
} catch (Throwable $exception) {
    error_log($exception->getMessage());
}

$source = (string) ($_GET['source'] ?? (__DIR__ . '/logs/fortuna.log'));
ob_start();
// Intentionally vulnerable: the requested local path is included without validation.
include $source;
$archive = (string) ob_get_clean();

page_top('Mission Logs', '/mission-logs.php');
?>
<div class="page-heading"><p class="eyebrow">OPERATIONS / FLIGHT RECORDS</p><h1>Mission Logs</h1><p>Authenticated events and archived Guidance relay output.</p></div>
<section class="card"><table><thead><tr><th>UTC TIME</th><th>VEHICLE</th><th>LEVEL</th><th>EVENT</th></tr></thead><tbody><?php foreach ($events as $event): ?><tr><td><?= e($event['occurred_at']) ?></td><td><?= e($event['callsign']) ?></td><td><?= e($event['severity']) ?></td><td><?= e($event['event_text']) ?></td></tr><?php endforeach; ?></tbody></table></section>
<section class="card top-gap"><div class="card-heading"><div><p class="eyebrow">ARCHIVE VIEWER</p><h2>RAW FLIGHT LOG</h2></div><form method="get" class="source-form"><input name="source" value="<?= e($source) ?>"><button type="submit">OPEN SOURCE</button></form></div><pre class="terminal-output"><?= e($archive) ?></pre></section>
<?php page_bottom(); ?>
