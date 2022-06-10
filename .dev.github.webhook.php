<?php

define("TOKEN", "TOKEN");
$content = file_get_contents("php://input");
$signature = "sha1=".hash_hmac('sha1', $content, TOKEN);

if (!$_SERVER['HTTP_X_HUB_SIGNATURE'] || $_SERVER['HTTP_X_HUB_SIGNATURE'] != $signature) {
    header("HTTP/1.0 404 Not Found");
    die();
}

$json = json_decode($content, true);
$ref = str_replace('refs/heads/', '', $json['ref']);
$ref = preg_replace("[^0-9a-zA-Z\-]", '', $ref);
if ($ref) {
    echo "dev.sh -b $ref";
    $command = exec("dev.sh -b $ref" . $script, $console);
    echo implode(";\n", $console);
}

die();
