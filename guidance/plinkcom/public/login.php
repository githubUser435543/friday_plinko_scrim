<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
start_session();

if (!empty($_SESSION['user'])) {
    header('Location: /dashboard.php');
    exit;
}

$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!hash_equals(csrf_token(), (string) ($_POST['csrf'] ?? ''))) {
        $error = 'Session validation failed. Reload and try again.';
    } else {
        try {
            $username = trim((string) ($_POST['username'] ?? ''));
            $stmt = db()->prepare('SELECT id, username, display_name, role, password_hash FROM users WHERE username = ? AND active = 1 LIMIT 1');
            $stmt->bind_param('s', $username);
            $stmt->execute();
            $user = $stmt->get_result()->fetch_assoc();
            if ($user && password_verify((string) ($_POST['password'] ?? ''), $user['password_hash'])) {
                session_regenerate_id(true);
                unset($user['password_hash']);
                $_SESSION['user'] = $user;
                header('Location: /dashboard.php');
                exit;
            }
            $error = 'ACCESS DENIED // INVALID OPERATOR CREDENTIALS';
        } catch (Throwable $exception) {
            error_log($exception->getMessage());
            $error = 'GUIDANCE DATABASE LINK UNAVAILABLE';
        }
    }
}
?>
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Operator Access · PLINKCOM</title><link rel="stylesheet" href="/assets/plinkcom.css"></head>
<body class="login-body">
<section class="login-panel">
  <div class="login-crest">♞</div>
  <p class="eyebrow">IHPL // GUIDANCE NETWORK</p>
  <h1>PLINKCOM</h1>
  <p class="muted">Mission operations terminal</p>
  <?php if ($error): ?><div class="login-error"><?= e($error) ?></div><?php endif; ?>
  <form method="post">
    <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
    <label>OPERATOR ID<input name="username" autocomplete="username" required autofocus></label>
    <label>ACCESS CODE<input type="password" name="password" autocomplete="current-password" required></label>
    <button type="submit">AUTHENTICATE</button>
  </form>
  <small>AUTHORIZED PERSONNEL ONLY · ALL ACTIVITY MONITORED</small>
</section>
</body>
</html>
