<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
require_auth();

$search = trim((string) ($_GET['q'] ?? ''));
$crew = [];
$error = '';
try {
    // Intentionally vulnerable: the search term is concatenated into SQL.
    $sql = "SELECT id, full_name, role, assignment, status FROM crew_members";
    if ($search !== '') {
        $sql .= " WHERE full_name LIKE '%$search%' OR role LIKE '%$search%' OR assignment LIKE '%$search%'";
    }
    $sql .= ' ORDER BY id';
    $crew = db()->query($sql)->fetch_all(MYSQLI_ASSOC);
} catch (Throwable $exception) {
    error_log($exception->getMessage());
    $error = 'MANIFEST SEARCH FAILED';
}

page_top('Crew Manifest', '/crew-manifest.php');
?>
<div class="page-heading"><p class="eyebrow">OPERATIONS / MISSION FORTUNA</p><h1>Crew Manifest</h1><p>Search authorized personnel, autonomous systems, and payload riders.</p></div>
<section class="card search-card"><form method="get" class="search-form"><input name="q" value="<?= e($search) ?>" placeholder="Search name, role, or assignment"><button type="submit">SEARCH MANIFEST</button></form></section>
<?php if ($error): ?><div class="critical"><?= e($error) ?></div><?php else: ?>
<section class="card top-gap"><table><thead><tr><th>ID</th><th>CREW MEMBER</th><th>ROLE</th><th>ASSIGNMENT</th><th>STATUS</th></tr></thead><tbody><?php foreach ($crew as $member): ?><tr><td><?= e((string) $member['id']) ?></td><td><?= e((string) $member['full_name']) ?></td><td><?= e((string) $member['role']) ?></td><td><?= e((string) $member['assignment']) ?></td><td><?= e((string) $member['status']) ?></td></tr><?php endforeach; ?></tbody></table><?php if (!$crew): ?><p class="muted">No matching crew records.</p><?php endif; ?></section>
<?php endif; ?>
<?php page_bottom(); ?>
