# bitrix.devops
* Работает только с Bitrixenv
* Сам установит Bitrixenv
* Сам создаст sftp chroot пользователей с гит ветками и отдельными сайтами на поддоменах
* Принимает входящие вебхуки от github.com через php файл (который надо разместить где нибудь) с последующим git pull

TODO: 
* Автоматическое создание поддомена для вебхука, размещение вебхука, генерация ключа для вебхука, вывод ссылки и инструкции для github.com
* Копирование БД и файлов в новые сайты с основного сайта

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
-b {git branch name} - для запуска процедуры git pull определённой ветки
```

Не забыть настроить вебхук
```
.dev.github.webhook.php
```

Если используется cloudflare
```
1. Добавляем список ip в Manage Account->Configuration->List = https://api.github.com/meta (секция вебхуков)
2. Добавляем правила WAF (http.request.uri.path eq "/.dev.github.webhook.php" and ip.src in $github_webhooks_ip)
3. Заходим в Configure Super Bot Fight Mode и меняем Definitely automated = Allow
```