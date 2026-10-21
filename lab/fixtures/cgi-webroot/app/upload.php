<?php
header('Content-Type: text/plain');
echo "PHP=" . PHP_VERSION . "\n";
echo "SAPI=" . php_sapi_name() . "\n";
echo "handler=" . ini_get('session.serialize_handler') . "\n";
echo "upload_progress=" . ini_get('session.upload_progress.enabled') . "\n";
echo "APP\n";
