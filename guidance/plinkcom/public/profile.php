<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
require_auth();

$notice = '';
$error = '';
$userId = (int) ($_SESSION['user']['id'] ?? 0);
$profile = null;

try {
    $stmt = db()->prepare('SELECT id, username, display_name, role, active, created_at, password_hash FROM users WHERE id = ? LIMIT 1');
    $stmt->bind_param('i', $userId);
    $stmt->execute();
    $profile = $stmt->get_result()->fetch_assoc();
    if (!$profile || (int) $profile['active'] !== 1) {
        $_SESSION = [];
        session_destroy();
        header('Location: /login.php');
        exit;
    }

    if ($_SERVER['REQUEST_METHOD'] === 'POST') {
        if (!hash_equals(csrf_token(), (string) ($_POST['csrf'] ?? ''))) {
            $error = 'SESSION VALIDATION FAILED // RELOAD AND TRY AGAIN';
        } elseif (!password_verify((string) ($_POST['current_password'] ?? ''), $profile['password_hash'])) {
            $error = 'CURRENT ACCESS CODE IS INCORRECT';
        } else {
            $username = trim((string) ($_POST['username'] ?? ''));
            $newPassword = (string) ($_POST['new_password'] ?? '');
            $passwordConfirmation = (string) ($_POST['confirm_password'] ?? '');

            if (!preg_match('/\A[a-zA-Z0-9][a-zA-Z0-9._-]{2,63}\z/', $username)) {
                $error = 'OPERATOR ID MUST BE 3–64 CHARACTERS USING LETTERS, NUMBERS, DOTS, DASHES, OR UNDERSCORES';
            } elseif ($newPassword !== '' && strlen($newPassword) < 12) {
                $error = 'NEW ACCESS CODE MUST BE AT LEAST 12 CHARACTERS';
            } elseif ($newPassword !== $passwordConfirmation) {
                $error = 'NEW ACCESS CODE CONFIRMATION DOES NOT MATCH';
            } else {
                try {
                    if ($newPassword === '') {
                        $update = db()->prepare('UPDATE users SET username = ? WHERE id = ?');
                        $update->bind_param('si', $username, $userId);
                    } else {
                        $passwordHash = password_hash($newPassword, PASSWORD_BCRYPT);
                        $update = db()->prepare('UPDATE users SET username = ?, password_hash = ? WHERE id = ?');
                        $update->bind_param('ssi', $username, $passwordHash, $userId);
                    }
                    $update->execute();

                    $profile['username'] = $username;
                    if ($newPassword !== '') {
                        $profile['password_hash'] = $passwordHash;
                    }
                    $_SESSION['user']['username'] = $username;
                    session_regenerate_id(true);
                    $notice = 'OPERATOR PROFILE UPDATED';
                } catch (mysqli_sql_exception $exception) {
                    if ((int) $exception->getCode() === 1062) {
                        $error = 'THAT OPERATOR ID IS ALREADY ASSIGNED';
                    } else {
                        throw $exception;
                    }
                }
            }
        }
    }
} catch (Throwable $exception) {
    error_log($exception->getMessage());
    $error = 'MANIFEST PROFILE LINK UNAVAILABLE';
}

page_top('Profile', '/profile.php');
?>
<div class="page-heading"><p class="eyebrow">ACCOUNT / OPERATOR IDENTITY</p><h1>Profile</h1><p>Review your operator record and update your PlinkCom credentials.</p></div>
<?php if ($notice): ?><div class="success-banner"><?= e($notice) ?></div><?php endif; ?>
<?php if ($error): ?><div class="critical"><?= e($error) ?></div><?php endif; ?>

<?php if ($profile): ?>
<div class="two-column profile-layout">
  <section class="card identity-card">
    <div class="profile-avatar"><?= e(strtoupper(substr($profile['display_name'], 0, 1))) ?></div>
    <p class="eyebrow">ACTIVE OPERATOR</p>
    <h2><?= e($profile['display_name']) ?></h2>
    <dl class="account-facts">
      <dt>OPERATOR ID</dt><dd><?= e($profile['username']) ?></dd>
      <dt>ACCESS ROLE</dt><dd><?= e(strtoupper($profile['role'])) ?></dd>
      <dt>ACCOUNT STATUS</dt><dd class="nominal">ACTIVE</dd>
      <dt>ENROLLED</dt><dd><?= e($profile['created_at']) ?></dd>
    </dl>
  </section>

  <section class="card">
    <h2>UPDATE CREDENTIALS</h2>
    <form method="post" class="ops-form">
      <input type="hidden" name="csrf" value="<?= e(csrf_token()) ?>">
      <label>OPERATOR ID
        <input name="username" value="<?= e($profile['username']) ?>" minlength="3" maxlength="64" pattern="[A-Za-z0-9][A-Za-z0-9._-]{2,63}" autocomplete="username" required>
      </label>
      <label>CURRENT ACCESS CODE
        <input type="password" name="current_password" autocomplete="current-password" required>
      </label>
      <label>NEW ACCESS CODE
        <input type="password" name="new_password" minlength="12" autocomplete="new-password" aria-describedby="password-note">
      </label>
      <label>CONFIRM NEW ACCESS CODE
        <input type="password" name="confirm_password" minlength="12" autocomplete="new-password">
      </label>
      <p class="field-note" id="password-note">Leave both new access-code fields blank to keep your current password.</p>
      <button type="submit">COMMIT PROFILE</button>
    </form>
  </section>
</div>
<?php endif; ?>
<?php page_bottom(); ?>
