<?php
// Non-executing web-shell stand-in. It never invokes a shell or evaluates input.
header('Content-Type: text/plain');
http_response_code(403);
echo "IHPL TRAINING ARTIFACT\nCommand execution is disabled.\n";
