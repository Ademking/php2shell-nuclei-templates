<?php
session_start();
header('Content-Type: text/plain');
echo "PHP=" . PHP_VERSION . "\n";
echo "SAPI=" . php_sapi_name() . "\n";
echo "upload_progress=" . ini_get('session.upload_progress.enabled') . "\n";
echo "serialize_handler=" . ini_get('session.serialize_handler') . "\n";
echo "session_id=" . session_id() . "\n";
echo "session_name=" . session_name() . "\n";
echo "OK\n";
