<?php
declare(strict_types=1);

const APP_NAME = 'PLINKCOM';

function db(): mysqli
{
    static $connection = null;
    if ($connection instanceof mysqli) {
        return $connection;
    }

    $databaseHost = getenv('PLINKCOM_DB_HOST');
    if ($databaseHost === false || $databaseHost === '') {
        throw new RuntimeException('PLINKCOM_DB_HOST is required.');
    }

    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    $connection = new mysqli(
        $databaseHost,
        getenv('PLINKCOM_DB_USER') ?: 'jmoney',
        getenv('PLINKCOM_DB_PASSWORD') ?: 'H00ves0nTheM00n',
        getenv('PLINKCOM_DB_NAME') ?: 'plinkcom',
        (int) (getenv('PLINKCOM_DB_PORT') ?: 3306)
    );
    $connection->set_charset('utf8mb4');
    return $connection;
}

function start_session(): void
{
    if (session_status() === PHP_SESSION_NONE) {
        session_name('plinkcom_session');
        session_set_cookie_params([
            'httponly' => true,
            'secure' => !empty($_SERVER['HTTPS']),
            'samesite' => 'Strict',
        ]);
        session_start();
    }
}

function require_auth(): void
{
    start_session();
    if (empty($_SESSION['user'])) {
        header('Location: /login.php');
        exit;
    }
}

function e(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function csrf_token(): string
{
    start_session();
    if (empty($_SESSION['csrf'])) {
        $_SESSION['csrf'] = bin2hex(random_bytes(24));
    }
    return $_SESSION['csrf'];
}

function nav_item(string $href, string $label, string $icon, string $active): string
{
    $class = $active === $href ? 'nav-item active' : 'nav-item';
    return '<a class="' . $class . '" href="' . e($href) . '"><span>' . e($icon) . '</span>' . e($label) . '</a>';
}

function page_top(string $title, string $active = '/dashboard.php'): void
{
    start_session();
    $user = e($_SESSION['user']['display_name'] ?? 'Flight Operator');
    $operatorMark = e(strtoupper(substr((string) ($_SESSION['user']['display_name'] ?? 'F'), 0, 1)));
    $role = e(strtoupper((string) ($_SESSION['user']['role'] ?? 'operator')));
    $safeTitle = e($title);
    echo <<<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{$safeTitle} · PLINKCOM</title>
  <link rel="stylesheet" href="/assets/plinkcom.css">
</head>
<body>
<header class="topbar">
  <a class="brand" href="/dashboard.php"><span class="crest">♞</span><span><b>PLINKCOM</b><small>IHPL OPS NETWORK</small></span></a>
  <div class="system-title">INTERNATIONAL HORSE PLINKO LEAGUE <strong>OPERATIONS DIVISION</strong></div>
  <div class="operator"><span class="operator-mark">{$operatorMark}</span><a class="operator-profile" href="/profile.php"><b>{$user}</b><small>{$role}</small></a><a href="/logout.php">SIGN OUT</a></div>
</header>
<div class="shell">
  <aside class="sidebar">
    <p class="nav-label">OVERVIEW</p>
HTML;
    echo nav_item('/dashboard.php', 'Dashboard', '◆', $active);
    echo '<p class="nav-label">FLIGHT</p>';
    echo nav_item('/my-rocket.php', 'My Rocket', '◇', $active);
    echo '<p class="nav-label">OPERATIONS</p>';
    echo nav_item('/cargo.php', 'Cargo', '▣', $active);
    echo nav_item('/mission-logs.php', 'Mission Logs', '⌁', $active);
    echo nav_item('/crew-manifest.php', 'Crew Manifest', '◌', $active);
    echo nav_item('/attachments.php', 'Attachments', '⌕', $active);
    echo '<p class="nav-label">ACCOUNT</p>';
    echo nav_item('/profile.php', 'Profile', '●', $active);
    echo '<div class="sidebar-foot"><span>IHPL // SECURE OPS</span><small>LINK ENCRYPTION: ACTIVE<br>NET: GUIDANCE / 01</small></div></aside><main class="content">';
}

function page_bottom(): void
{
    echo '<footer>IHPL GUIDANCE CONTROL · AUTHORIZED OPERATORS ONLY</footer></main></div><script src="/assets/plinkcom.js"></script></body></html>';
}
