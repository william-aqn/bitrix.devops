<?php
define("TOKEN", "TOKEN");
$json = json_decode(file_get_contents("php://input"), true);
$ref = str_replace('refs/heads/', '', $json['ref']);
$ref = preg_replace("[^0-9a-zA-Z\-]", '', $ref);
$command = exec("dev.sh $ref" . $script, $console);
echo $console;
die();
