# bitrix.devops
* Работает только с Bitrixenv
* Сам установит Bitrixenv

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
