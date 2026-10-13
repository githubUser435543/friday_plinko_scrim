<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
require_auth();
page_top('Alerts', '/alerts.php');
?>
<div class="page-heading"><p class="eyebrow">SYSTEM HEALTH</p><h1>Alerts</h1><p>Active mission exceptions requiring operator review.</p></div>
<section class="card empty-state"><div>✓</div><h2>NO ACTIVE ALERTS</h2><p>EQUUS I is operating within nominal flight tolerances.</p></section>
<?php page_bottom(); ?>
