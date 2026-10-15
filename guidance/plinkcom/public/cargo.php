<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
require_auth();

$seal = trim((string) ($_GET['seal'] ?? 'PLK-CA-117'));
$scanOutput = '';
if (isset($_GET['seal'])) {
    // Intentionally vulnerable: the seal identifier is appended to a shell command.
    $scanOutput = (string) shell_exec('/usr/bin/printf "seal scan: %s\n" ' . $seal . ' 2>&1');
}

page_top('Cargo', '/cargo.php');
?>
<div class="page-heading"><p class="eyebrow">OPERATIONS / PAYLOAD CONTROL</p><h1>Cargo</h1><p>Vehicle route, payload status, and container seal diagnostics.</p></div>
<section class="status-strip">
  <div><small>ROCKET</small><strong>EQUUS I</strong></div><div><small>ROUTE</small><strong>HORSETON → LUNAR SOUTH</strong></div><div><small>CARGO MASS</small><strong>18,420 KG</strong></div><div><small>STATUS</small><strong class="nominal"><i></i>SECURED</strong></div>
</section>
<div class="two-column top-gap">
  <section class="card"><h2>PAYLOAD REGISTER</h2><table><thead><tr><th>CONTAINER</th><th>CONTENTS</th><th>STATE</th></tr></thead><tbody><tr><td>PLK-CA-117</td><td>PLINKO SAUCE // TYPE IV</td><td>SEALED</td></tr><tr><td>PLK-HU-007</td><td>HORSE LIFE SUPPORT</td><td>NOMINAL</td></tr><tr><td>PLK-AI-001</td><td>PLINKAI FLIGHT CORE</td><td>ONLINE</td></tr></tbody></table></section>
  <section class="card"><h2>SEAL SCANNER</h2><form method="get" class="ops-form inline-form"><label>CONTAINER OR SEAL ID<input name="seal" value="<?= e($seal) ?>"></label><button type="submit">RUN DIAGNOSTIC</button></form><?php if ($scanOutput !== ''): ?><pre class="terminal-output"><?= e($scanOutput) ?></pre><?php endif; ?></section>
</div>
<?php page_bottom(); ?>
