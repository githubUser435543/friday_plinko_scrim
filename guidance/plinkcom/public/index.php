<?php
require_once dirname(__DIR__) . '/app/bootstrap.php';
start_session();
header('Location: ' . (!empty($_SESSION['user']) ? '/dashboard.php' : '/login.php'));
exit;
