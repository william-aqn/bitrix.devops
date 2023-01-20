<?php

$_SERVER["DOCUMENT_ROOT"] = realpath(dirname(__FILE__) . "/..");
$DOCUMENT_ROOT = $_SERVER["DOCUMENT_ROOT"];

if (file_exists($_SERVER['DOCUMENT_ROOT'] . "/bitrix/.isprod") === true) {
    return;
}

define("NO_KEEP_STATISTIC", true);
define("NOT_CHECK_PERMISSIONS", true);
define('BX_NO_ACCELERATOR_RESET', true);
define('CHK_EVENT', false);

require($_SERVER["DOCUMENT_ROOT"] . "/bitrix/modules/main/include/prolog_before.php");

@set_time_limit(0);
@ignore_user_abort(true);

BXClearCache(true);
$GLOBALS["CACHE_MANAGER"]->CleanAll();
$GLOBALS["stackCacheManager"]->CleanAll();
$taggedCache = \Bitrix\Main\Application::getInstance()->getTaggedCache();
$taggedCache->deleteAllTags();
$page = \Bitrix\Main\Composite\Page::getInstance();
$page->deleteAll();
echo "Clear - OK {$_SERVER["DOCUMENT_ROOT"]}";

require($_SERVER["DOCUMENT_ROOT"] . "/bitrix/modules/main/include/epilog_after.php");
?>