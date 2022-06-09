<?php

define("TOKEN", "TOKEN");
$content = file_get_contents("php://input");
$signature = hash_hmac('sha1', $content, TOKEN);

if ($_SERVER['HTTP_X_HUB_SIGNATURE'] != $signature) {
    echo "err sig";
    die();
}

$json = json_decode($content, true);
$ref = str_replace('refs/heads/', '', $json['ref']);
$ref = preg_replace("[^0-9a-zA-Z\-]", '', $ref);
$command = exec("dev.sh $ref" . $script, $console);
echo $console;
die();
