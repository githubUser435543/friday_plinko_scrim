<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
require_auth();

$uploadDirectory = __DIR__ . '/uploads';
$message = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['attachment'])) {
    // Intentionally vulnerable: executable extensions and original filenames are accepted.
    $filename = basename((string) $_FILES['attachment']['name']);
    $destination = $uploadDirectory . '/' . $filename;
    if (move_uploaded_file($_FILES['attachment']['tmp_name'], $destination)) {
        $message = 'UPLOAD COMPLETE: /uploads/' . $filename;
    } else {
        $message = 'UPLOAD FAILED';
    }
}

$files = is_dir($uploadDirectory) ? array_values(array_filter(glob($uploadDirectory . '/*') ?: [], 'is_file')) : [];
page_top('Attachments', '/attachments.php');
?>
<div class="page-heading"><p class="eyebrow">OPERATIONS / MISSION FILES</p><h1>Attachments</h1><p>Upload and retrieve flight plans, cargo documents, and operator notes.</p></div>
<?php if ($message): ?><div class="success-banner"><?= e($message) ?></div><?php endif; ?>
<div class="two-column">
  <section class="card"><h2>UPLOAD ATTACHMENT</h2><form method="post" enctype="multipart/form-data" class="ops-form"><label>MISSION FILE<input type="file" name="attachment" required></label><button type="submit">UPLOAD TO GUIDANCE</button></form></section>
  <section class="card"><h2>AVAILABLE FILES</h2><div class="file-list"><?php if (!$files): ?><p class="muted">No attachments have been uploaded.</p><?php endif; ?><?php foreach ($files as $file): $name = basename($file); ?><a href="/uploads/<?= e(rawurlencode($name)) ?>"><span>▱</span><b><?= e($name) ?></b><small>OPEN FILE ↗</small></a><?php endforeach; ?></div></section>
</div>
<?php page_bottom(); ?>
