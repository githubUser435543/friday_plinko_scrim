<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
require_auth();
page_top('Crew Manifest', '/crew-manifest.php');
?>
<div class="page-heading"><p class="eyebrow">MISSION FORTUNA</p><h1>Crew Manifest</h1><p>Authorized mission personnel and payload riders.</p></div>
<div class="cards"><article class="card"><b>JMONEY</b><span>FLIGHT DIRECTOR</span><small>GUIDANCE AUTHORITY // ACTIVE</small></article><article class="card"><b>PLINKAI™</b><span>AUTONOMOUS PILOT</span><small>MODEL LINK // ACTIVE</small></article><article class="card"><b>HORSE UNIT 07</b><span>MISSION SPECIALIST</span><small>VITALS // NOMINAL</small></article></div>
<?php page_bottom(); ?>
