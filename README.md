# bitrix.devops
* Работает только с Bitrixenv
* Установит Bitrixenv
* Создаст нужную группу пользователей и предупредит как правильно настроить sshd
* Создаст sftp chroot пользователей с гит ветками и отдельными сайтами на поддоменах
* Актуализация БД и файлов с основного сайта
* Проверит наличие A записей у поддоменов
* Проверит свободное место на сервере
* Проверит ip адреса локальные и глобальные
* Проверит уникальность ssh порта
* Принимает входящие вебхуки от github.com через php файл (который надо разместить где нибудь) с последующим git pull
* Добавлена поддержка подстановки настоящего ip адреса от cloudflare в nginx
* Автоматическое создание поддомена для вебхука, размещение вебхука, генерация ключа для вебхука, вывод ссылки и инструкции для github.com


Установка
```
wget -O dev.sh https://raw.githubusercontent.com/william-aqn/bitrix.devops/main/dev.sh && chmod +x dev.sh && ./dev.sh
```
Запуск обычный
```
dev.sh
```
Ключи для запуска
```
-b {git branch name} - для запуска процедуры git pull 
определённой ветки
-s {минимальный процент для вывода сообщения} - проверить свободное место
-c - cloudflare nginx ip set (только от root)
```

Не забыть настроить вебхук
```
.dev.github.webhook.php
```

Если используется cloudflare
```
В ЛК cloudflare:
1. Добавляем список ip в Manage Account->Configuration->List = https://api.github.com/meta (секция вебхуков)
2. Добавляем правила WAF (http.request.uri.path eq "/.dev.github.webhook.php" and ip.src in $github_webhooks_ip)
3. Заходим в Configure Super Bot Fight Mode и меняем Definitely automated = Allow

На сервере:
1. Добавляем cron задание для запуска dev.sh с ключём -c в меню скрипта dev.sh
```

Однострочная команда для git pull/push/fetch
```
set +H && git -c credential.helper="!f() { cat >/dev/null; echo 'username=логин'; echo 'password=пароль'; }; f" fetch
```