# CI/CD
То что в ветке, то и на поддомене.
*Запуск через вебкук и/или action*


# Bitrix.Devops
* **Работает только с Bitrixenv**
* Установит Bitrixenv
* Создаст нужную группу пользователей и расскажет как правильно настроить sshd chroot
* **Создаст sftp chroot пользователей с гит ветками и отдельными сайтами на поддоменах**
* Актуализация БД и файлов с основного сайта
* Проверит наличие A записей у поддоменов
* Проверит свободное место на сервере
* Проверит ip адреса локальные и глобальные
* Проверит уникальность ssh порта
* Принимает входящие вебхуки от github.com через php файл (который надо разместить где нибудь) с последующим git pull
* Добавлена поддержка подстановки настоящего ip адреса от cloudflare в nginx
* Автоматическое создание поддомена для вебхука, размещение вебхука, генерация ключа для вебхука, вывод ссылки и инструкции для github.com
* Аккуратная работа с мастер веткой (на сколько это возможно)
* Набор **Github Actions** для реализации схемы [pull_request]->stage->[update]->[tests_selenium]->[telegram_notify]->main

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
-u {site_name} - папка в ext_www для актуализации сайта
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

Во время разработки, для различия копий prod/staging, используйте файл
```
/home/bitrix/www/bitrix/.isprod
```

Ленивая команда для git pull/push/fetch
```
su bitrix
set +H && git -c credential.helper="!f() { cat >/dev/null; echo 'username=логин'; echo 'password=пароль'; }; f" fetch
```

Для Actions заполнить secrets
```
secrets.GITHUB_TOKEN - с правами на создание пул реквест и чтение репозитория
secrets.TELEGRAM_TO - id чата телеграмм
secrets.TELEGRAM_TOKEN - токен бота
secrets.HOST - ip сервера
secrets.PORT - ssh порт сервера
secrets.LOGIN - root (только у него есть нужные права)
secrets.PASSWORD / secrets.KEY - пароль или rsa ключ
```

# Внимание! Удаление ветки удалит всё на поддомене. Осторожнее.