#!/bin/bash

## Проверено на bitrixenv 9.0.4
version=1.3.2

## Группа пользователей для разработчиков
user_group=dev-group

## Путь к файлу конфигурации
config_file=/home/bitrix/.dev.cnf
## Путь к файлу конфигурации для стороннего сервера
remote_file=/root/.dev.remote.cnf

## Путь к mysql доступам
mysql_root_config_file=/root/.my.cnf

## Путь к функциям bitrixenv
bitrix_helper_file=/opt/webdir/bin/bitrix_utils.sh

## Полный путь этого файла
self_file=$(readlink -f "${BASH_SOURCE:-$0}")

## Установочный путь
global_file=/usr/local/bin/dev.sh

## Актуальная версия скрипта
update_url=https://raw.githubusercontent.com/william-aqn/bitrix.devops/main/dev.sh

## Путь к домашней директории пользователя bitrix
bitrix_home_dir=/home/bitrix/

## Путь к адресам cloudflare
CLOUDFLARE_IP_RANGES_FILE_PATH=/etc/nginx/bx/maps/cloudflare.conf
CLOUDFLARE_DIRECT_BLOCK_FILE_PATH=/etc/nginx/bx/maps/cloudflare_direct_block.conf

## Задание для cloudflare crontab
cloudflare_croncmd="$global_file -c > /dev/null 2>&1"
cloudflare_cronjob="0 1 * * * $cloudflare_croncmd"
cloudflare_cronfile=/etc/cron.d/dev.sh.cloudflare

## webhook
webhook_subdomain=webhook
# Заготовка вебкуха
webhook_download_url=https://raw.githubusercontent.com/william-aqn/bitrix.devops/main/.dev.github.webhook.php
# Имя вебхука
webhook_name=".dev.github.webhook.php"

## Права рута?
is_root() {
    if [ "$EUID" -ne 0 ]; then
        false
    else
        true
    fi
}

## Пауза
wait() {
    read -t 3 -r >/dev/null
}

## Заглушка
no_menu() {
    echo -e ""
}

## Линия
line() {
    printf "\x2d%.0s" $(seq 1 85)
    printf "\n"
}

## Сделать текст красным
warning_text() {
    echo -e "\033[31m$1\033[m"
}

## Устанавливаем битрикс окружение
install_bitrixenv() {
    echo "Bitrixenv не обнаружен, устанавливаем..."
    yum clean all && yum -y update
    yum install -y wget
    wget -O bitrix-env-9.sh https://repo.bitrix.info/dnf/bitrix-env-9.sh && chmod +x bitrix-env-9.sh && ./bitrix-env-9.sh
    exit
}

## Проверяем команду arg1 на существование
check_command() {
    if ! command -v "$1" >/dev/null; then
        echo -e "Command $1 not found!"
        false
    else
        true
    fi
}

## Проверим/установим необходимые утилиты
init_service_tools() {
    if ! check_command "dig"; then
        yum install -y bind-utils
    fi
    if ! check_command "rsync"; then
        yum install -y rsync
    fi
}
init_service_tools

## Подгружаем битрикс окружение
init_bitrixenv() {
    if test -f "$bitrix_helper_file"; then
        . "${bitrix_helper_file}"
    else
        install_bitrixenv
    fi
}
init_bitrixenv

## Текущий глобальный IP
global_ip=$(dig @resolver4.opendns.com myip.opendns.com +short -4)

## Текущий локальный IP
current_ip=$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')

## Текущий ssh порт
current_ssh_port=$(netstat -tpln | grep 'sshd' | awk '/::/{gsub(":",""); print $4 }')

## Сравним локальный и глобальынй ip
check_ip() {
    echo -e "IP Глобальный $global_ip | IP Локальный $current_ip | SSH порт: $current_ssh_port"
    if [[ "$current_ip" != "$global_ip" ]]; then
        warning_text "IP отличаются!"
        ## TODO: Проверить
    fi
}

## Проверяем наличие служебный скриптов
check_install_master_site() {
    if test -f "$bitrix_home_dir"www/restore.php || test -f "$bitrix_home_dir"www/bitrixsetup.php; then
        warning_text "Обнаружены служебные скрипты в "$bitrix_home_dir"www/, возможно Битрикс не установлен. Исправьте для продолжения работы."
        echo -e "http://$current_ip/ || http://$global_ip/"
        exit
    fi
}

## Проверить dns A поддомена
check_dns_a_record() {
    dig "$1" A +short | xargs | sed -e 's/ /,/g'
}

## Проверить dns A поддомена (ручной ввод)
check_dns_a_record_one() {
    local user=""
    until [[ "$user" ]]; do
        IFS= read -p "Какой поддомен.$domain_name проверить?: " -r user
    done
    local check=$(check_dns_a_record "$user.$domain_name")
    if [[ $check != "" ]]; then
        echo -e "A: $check"
    else
        echo -e "'A' Запись не установлена у $user.$domain_name"
    fi
}

## Запустить bitrixenv
start_bitrixenv() {
    exec /root/menu.sh
}

## Получить статус задания bitrixenv по id
get_task_status() {
    /opt/webdir/bin/bx-process -a status -t "$1" | cut -d':' -f 7
}

## Получить id задания bitrixenv
get_task_id() {
    ## info:bxDaemon:site_create_0646371381:2934:1654865708::running:::
    echo "$1" | cut -d':' -f 3
}

## Ждём выполнение задания bitrixenv по id
wait_task() {
    local task_status=""
    until [[ "$task_status" == "finished" ]]; do
        task_status=$(get_task_status "$1")
        echo "$task_status; "
        sleep 1
    done
}

## Получить случайную строку
get_random_string() {
    date +%s | sha256sum | base64 | head -c 12
    echo
}

## Проверить наличие вебхука
check_webhook() {
    if [ -f /home/bitrix/ext_www/"$webhook_subdomain.$domain_name"/$webhook_name ]; then
        true
    else
        false
    fi
}

## Установить вебхук
set_webhook() {
    webhook_override=""

    local webhook_fill_domain="$webhook_subdomain.$domain_name"
    local webhook_domain_path=/home/bitrix/ext_www/"$webhook_fill_domain"
    local webhook_full_path="$webhook_domain_path/$webhook_name"

    if check_webhook; then
        until [[ "$webhook_override" ]]; do
            IFS= read -p "Пересоздать вебхук $webhook_full_path? [y/N]: " -r webhook_override
        done
        if [[ $webhook_override != "y" ]]; then
            return 0
        fi
    fi

    if [ ! -d "$webhook_domain_path" ]; then
        local task=$(/opt/webdir/bin/bx-sites -a create -s "$webhook_fill_domain" -t kernel --charset UTF-8) # --cron
        local task_id=$(get_task_id "$task")
        echo -e "Задание $task_id для создания сайта $webhook_fill_domain - запущено, ждём"
        wait_task "$task_id"
        echo -e "$webhook_fill_domain - создан"
    fi

    echo -e "Удаляем лишнее"
    rm -rf "$webhook_domain_path"
    mkdir "$webhook_domain_path"
    echo -e "Скачиваем заготовку для вебхука"
    wget -O "$webhook_full_path" "$webhook_download_url" && chown bitrix:bitrix "$webhook_full_path"
    local webhook_token=$(get_random_string)
    clear
    warning_text "Webhook token: $webhook_token"
    echo "Добавить вебхук можно тут: $git_url/settings/hooks" | sed -r "s/\.git//"
    echo -e "Можно посмотреть в файле: $webhook_full_path"
    sed -i "s/#TOKEN#/$webhook_token/" "$webhook_full_path"
    wait
    wait
    wait
}

## Проверим наличие мастер ветки в директории
git_check_master_in_dir() {
    cd "${1}" || false
    if [[ "$(git symbolic-ref --short -q HEAD)" == "$git_branch_master_name" ]]; then
        true
    else
        false
    fi
}

## Проверка на существование БД
check_db_mysql_exists() {
    if [ -f /var/lib/mysql/"$1" ]; then
        return 1
    fi
    return 0
}

## Берём название БД из .settings.php файла
get_bitrix_mysql_credentials_db_name() {
    if test -f "$1"/bitrix/.settings.php; then
        grep -Po "(?<='database' => ').*(?=',)" "$1"/bitrix/.settings.php
    fi
}

select_db_to_clone() {
    # local clone_site_path=""
    until [[ "$clone_site_path" ]]; do
        IFS= read -p "$1 для клонирования (/home/bitrix/www): " -r clone_site_path
    done
    db_name="$(get_bitrix_mysql_credentials_db_name "$clone_site_path")"
    if [[ $db_name == "" ]]; then
        echo -e "Не удаётся получить настройки для БД из $clone_site_path/bitrix/.settings.php"
        return 0
    fi
    return 1
}

## Скопировать из БД в БД
clone_db_mysql() {
    if ! check_db_mysql_exists "$1"; then
        warning_text "БД-источника $1 не существует. Отмена."
        return 0
    fi

    if ! check_db_mysql_exists "$2"; then
        warning_text "БД-назначения $2 не существует. Отмена."
        return 0
    fi

    if [[ "$1" == "$2" ]]; then
        warning_text "Ошибка! Базы должны отличаться $1/$2"
        return 0
    fi

    if test -f "$mysql_root_config_file"; then
        . "$mysql_root_config_file"

        if [[ $user != "root" || $password = "" || $socket = "" ]]; then
            echo -e "В файле $mysql_root_config_file недостаточно данных"
            return 0
        fi
        #echo -e "Начинаем копировать БД $1 -> $2 [root:$password@localhost], логи в файле /var/log/mysqldbcopy.log"
        #mysqldbcopy --force --source=root:"$password"@localhost:0:"$socket" --destination=root:"$password"@localhost:0:"$socket" "$1":"$2" > /var/log/mysqldbcopy.log

        echo -e "Начинаем копировать БД $1 -> $2 [root:$password@localhost]"
        mysqldbcopy --force --source=root:"$password"@localhost:0:"$socket" --destination=root:"$password"@localhost:0:"$socket" "$1":"$2"

        # 1. Очищаем все таблицы в целевой базе, но НЕ удаляем их
        #echo "Очищаем данные в таблицах БД $2..."
        #tables=$(mysql -u root -p"$password" -N -B -e "SELECT table_name FROM information_schema.tables WHERE table_schema = '$2';")
        #for table in $tables; do
        #    mysql -u root -p"$password" -e "SET FOREIGN_KEY_CHECKS=0; TRUNCATE TABLE $2.$table; SET FOREIGN_KEY_CHECKS=1;"
        #done

        # 2. Копируем структуру и данные ИЗ $1 В $2
        #echo "Копируем структуру и данные..."
        #mysqldump -u root -p"$password" --socket=$socket "$1" | mysql -u root -p"$password" --socket=$socket "$2"

        # TODO: Не копировать grants
    else
        echo -e "Файла $mysql_root_config_file с root паролем для mysql не существует"
    fi
}

## Синхронизируем 2 сайта
sync_sites() {
    if [[ "$1" == "$2" ]]; then
        warning_text "Ошибка! Директории должны отличаться [$1]->[$2]"
        return 0
    fi
    # Проверяем находится ли ядро в источнике и существует ли конечный путь
    if test -d "$1/bitrix" && test -d "$1/upload" && test -d "$1"; then
        #echo -e "Начинаем синхронизацию [$1]->[$2], логи в файле /var/log/rsync.log"
        #rsync -av --delete --exclude .git --exclude /bitrix/.settings.php --exclude /bitrix/php_interface/dbconn.php --exclude bitrix/backup --exclude bitrix/cache --exclude bitrix/managed_cache --exclude bitrix/stack_cache --progress "$1/" "$2" > /var/log/rsync.log

        echo -e "Начинаем синхронизацию [$1]->[$2]"
        rsync -a --delete --exclude .git --exclude /robots.txt --exclude /bitrix/.settings.php --exclude /bitrix/.isprod --exclude /bitrix/.settings_extra.php --exclude /bitrix/php_interface/dbconn.php --exclude bitrix/backup --exclude bitrix/cache --exclude bitrix/html_pages --exclude bitrix/managed_cache --exclude bitrix/stack_cache --exclude local/logs --progress "$1/" "$2"
        warning_text "Обязательно очищайте кэш в админке"
        wait
    else
        echo -e "Ошибка при вводе путей [$1]->[$2]"
    fi
}

## Актуализация из консоли
console_site_clone() {
    db_name_from="$(get_bitrix_mysql_credentials_db_name "$clone_site_path_from")"
    if [[ $db_name_from == "" ]]; then
        warning_text "#BD_FROM_NOT_FOUND# $clone_site_path_from"
        exit 1
    fi

    db_name_to="$(get_bitrix_mysql_credentials_db_name "$clone_site_path_to")"
    if [[ $db_name_to == "" ]]; then
        warning_text "#BD_TO_NOT_FOUND# $clone_site_path_to"
        exit 2
    fi

    ## Защищаем мастер ветку
    if git_check_master_in_dir "$clone_site_path_to"; then
        warning_text "#MASTER_TREE_DETECTED#"
        exit 3
    fi

    clone_db_mysql "$db_name_from" "$db_name_to"
    sync_sites "$clone_site_path_from" "$clone_site_path_to"

    cd "$clone_site_path_to" || exit 4
    current_branch_name=$(git symbolic-ref --short -q HEAD)
    echo -e "Git: $current_branch_name"
    if [[ "$current_branch_name" != "" ]]; then
        git_get_credential_helper
        ##  Устанавливаем настройки
        git config --local user.name "server"
        git config --local user.email "$git_user"
        ##  Принимаем изменения
        git -c credential.helper="$HELPER" fetch --all
        git reset --hard origin/"$current_branch_name"
        ## Сбрасываем права
        chown -R bitrix:bitrix "$PWD"
        cd "$HOME" >/dev/null || exit
        warning_text "#GIT_OK#"
    fi

    warning_text "#OPERATION_OK#"
}

## Выбор сайта для актуализации
select_site_to_clone() {
    db_name_from=""
    db_name_to=""

    until [[ "$clone_mode" == "db" || "$clone_mode" == "file" || "$clone_mode" == "all" ]]; do
        IFS= read -p "Выберите режим клонирования [db/file/all]: " -r clone_mode
    done

    until [[ "$db_name_from" ]]; do
        until [[ "$clone_site_path_from" ]]; do
            IFS= read -p "Сайт-источник файлов (например: /home/bitrix/www) в котором находится файл /bitrix/.settings.php: " -r clone_site_path_from
        done
        db_name_from="$(get_bitrix_mysql_credentials_db_name "$clone_site_path_from")"
        if [[ $db_name_from == "" ]]; then
            echo -e "Не удаётся получить настройки для БД из $clone_site_path_from/bitrix/.settings.php"
            clone_site_path_from=""
        fi
    done

    until [[ "$db_name_to" ]]; do
        until [[ "$clone_site_path_to" ]]; do
            IFS= read -p "Сайт для актуализации (например: /home/bitrix/ext_www/domain) в котором находится файл /bitrix/.settings.php: " -r clone_site_path_to
        done
        db_name_to="$(get_bitrix_mysql_credentials_db_name "$clone_site_path_to")"
        if [[ $db_name_to == "" ]]; then
            echo -e "Не удаётся получить настройки для БД из $clone_site_path_to/bitrix/.settings.php"
            clone_site_path_to=""
        fi

        ## Защищаем мастер ветку
        if git_check_master_in_dir "$clone_site_path_to"; then
            if [[ "$git_pull_master_allow" == "y" ]]; then
                warning_text "Обнаружена $git_branch_master_name ветка"
                # Всё равно защищаем
                exit
            else
                warning_text "Обнаружена защищённая $git_branch_master_name ветка. Введите другой путь."
                db_name_to=""
                clone_site_path_to=""
            fi
        fi
    done

    if [[ "$clone_mode" == "db" || "$clone_mode" == "all" ]]; then
        clone_db_mysql "$db_name_from" "$db_name_to"
    fi

    if [[ "$clone_mode" == "file" || "$clone_mode" == "all" ]]; then
        sync_sites "$clone_site_path_from" "$clone_site_path_to"
    fi
}

## Установить случайный пароль для пользователя
set_user_random_password() {
    user_pswd=$(get_random_string)
    echo "$1:$user_pswd" | chpasswd
    echo -e "Для $1 установлен пароль: $user_pswd"
}

## Проверим наличие группы для разработчиков
init_user_group() {
    if ! grep -q $user_group /etc/group; then
        groupadd $user_group
        echo "Группа $user_group создана"
    fi
}
init_user_group

## Проверим настройки sshd
check_openssh_chroot() {
    if ! grep -q -F "$user_group" /etc/ssh/sshd_config; then
        warning_text "Необходимо внести правки в файл /etc/ssh/sshd_config"
        echo "Subsystem sftp internal-sftp"
        echo "Match Group $user_group"
        echo "ChrootDirectory /home/%u"
        echo "Match User root"
        echo "ChrootDirectory none"
        line
    fi
}

## Проверяем ssh порт
check_openssh_port() {
    if [[ $current_ssh_port == 22 ]]; then
        warning_text "Установлен стандартный ssh $current_ssh_port порт. Необходимо изменить."
    fi
}

## Проверим /etc/hosts на наличие домена
# TODO: Расширить на поддомены
check_hosts() {
    if ! grep -q -F "$domain_name" /etc/hosts; then
        warning_text "Домен $domain_name отсутствует в файле /etc/hosts"
        line
    fi
}

## Добавляем точку монтирования для пользователя в его домашний каталог
add_mount_point() {
    if ! grep -q "/home/$1/www" /etc/fstab; then
        {
            printf '\n# dev.sh %s start' "$1"
            printf '\n/home/bitrix/ext_www/%s /home/%s/www none bind 0 0' "$1.$domain_name" "$1"
            printf '\n# dev.sh %s end' "$1"
            printf '\n' ## Важно!
        } >>/etc/fstab
    fi
}

## Создаём сайт
create_kernel_site() {
    ## Проверяем наличие сайта
    if [ -d /home/bitrix/ext_www/"$1.$domain_name" ]; then
        override_site=""
        until [[ "$override_site" ]]; do
            IFS= read -p "Пересоздать сайт $1.$domain_name? [y/N]: " -r override_site
        done
        if [[ $override_site != "y" ]]; then
            echo -e "Создание сайта $1.$domain_name отменено"
            return 0
        fi
        local task_del=$(/opt/webdir/bin/bx-sites -a delete -r /home/bitrix/ext_www/"$1"."$domain_name" -s "$1"."$domain_name")
        local task_del_id=$(get_task_id "$task_del")
        echo -e "Задание $task_del_id для удаления сайта $1.$domain_name - запущено, ждём"
        wait_task "$task_del_id"
    fi

    ## TODO: /opt/webdir/bin/bx-sites -a create -s test3.local -t link --kernel_site test1.local --kernel_root /home/bitrix/ext_www/test1.local
    local task=$(/opt/webdir/bin/bx-sites -a create -s "$1"."$domain_name" -t kernel --charset UTF-8) # --cron
    local task_id=$(get_task_id "$task")
    echo -e "Задание $task_id для создания сайта $1.$domain_name - запущено, ждём"
    wait_task "$task_id"

    ## Копируем сайт+БД
    clone_site_path_from="/home/bitrix/www"
    clone_site_path_to="/home/bitrix/ext_www/$1.$domain_name"
    clone_mode="all"
    select_site_to_clone

    ## Создаём гит+ветку
    git_new_dir="/home/bitrix/ext_www/$1.$domain_name"
    git_new_branch="$1"
    git_new_dir_override="y"
    git_new_branch_create="y"
    git_init

    ## Создаём пользователя
    create_user "$1"
    ## Фиксим монтирование директории при пересоздании сайта (отображается пустота до перезагрузки)
    rebind_user_www "$1"

    ## Суммарная информация
    clear
    printf -v report 'Репозиторий: %s\nДомен: %s\nIP: %s:%s\nSFTP пользователь/гит-ветка: %s\nSFTP пароль: %s' "$git_url" "$1.$domain_name" "$current_ip" "$current_ssh_port" "$1" "$user_pswd"
    echo "$report" >"/root/.dev.$1.info"
    echo -e "Данные сохранены в файл /root/.dev.$1.info"
    echo -e "$report"
    wait
}

## Создаём сайт (ручной ввод)
create_site() {
    local user_name=""
    until [[ "$user_name" ]]; do
        IFS= read -p "Введите имя пользователя который будет одноимённым с веткой гита и поддоменом.$domain_name: " -r user_name
        if [[ $user_name = "root" || $user_name = "bitrix" ]]; then
            echo -e "Нельзя создать сайт для этого пользователя"
            user_name=""
        fi
    done
    create_kernel_site "$user_name"
}

## Разово (пере)монтируем каталог, что бы не перезагружать сервер
rebind_user_www() {
    umount /home/"$1"/www
    mount --bind /home/bitrix/ext_www/"$1.$domain_name" /home/"$1"/www
}

## Создаём пользователя, обновляем пароль
create_user() {
    if id "$1" &>/dev/null; then
        echo -e "Пользователь $1 существует"
        local override_pwd="y" ## TODO:?
        until [[ "$override_pwd" ]]; do
            IFS= read -p "Пересоздать пароль у пользователя $1? [y/N]: " -r override_pwd
        done
        if [[ $override_pwd == "y" ]]; then
            set_user_random_password "$1"
        fi
    else
        ## такой же id как у bitrix пользователя
        adduser "$1" -g600 -o -u600 -s /sbin/nologin -d /home/"$1"/
        usermod -aG $user_group "$1"
        mkdir /home/"$1"/www
        chown -R root:bitrix /home/"$1"/
        chmod 750 /home/"$1"/
        set_user_random_password "$1"
        add_mount_point "$1"

        rebind_user_www "$1"
    fi
}

## Создать/Изменить пользователя
change_password_exist_user() {
    local user_name=""
    until [[ "$user_name" ]]; do
        IFS= read -p "Введите имя пользователя: " -r user_name
        if id "$user_name" &>/dev/null; then
            set_user_random_password "$user_name"
        else
            echo -e "Пользователя не существует"
            user_name=""
        fi
    done
}

## Устанавливаем себя
install_self() {
    if [[ "$self_file" != "$global_file" ]]; then
        rm "$global_file"
        cp "$self_file" "$global_file"
        chmod +x "$global_file"
        chown bitrix:bitrix "$global_file"
        echo -e "Файл $self_file установлен в $global_file"
    else
        echo -e "Файл не может установиться сам в себя"
    fi
}

## Обновим сами себя и перезапустим
update_self() {
    wget -O "$global_file" "$update_url" && chmod +x "$global_file" && chown bitrix:bitrix "$global_file"
    echo -e "$global_file - обновлён"
    wait
    exec $global_file
}

## Проверяем свободное место
check_size() {
    local used=$(df -h / --output=pcent | awk 'END{ print $(NF-1) }' | tr -d '%')
    local free=$((100 - used))
    if [[ free -lt $1 ]]; then
        echo -e "Мало свободного места - $free%"
    fi
}

## Хелпер гита для авторизации
git_get_credential_helper() {
    printf -v HELPER "!f() { cat >/dev/null; echo 'username=%s'; echo 'password=%s'; }; f" "$git_user" "$git_pass"
}

## Вернёт errlvl 0 - если гит доступен
git_remote_url_reachable() {
    git_get_credential_helper
    git -c credential.helper="$HELPER" ls-remote "$1" CHECK_GIT_REMOTE_URL_REACHABILITY >/dev/null 2>&1
}

## Сохраняем конфиг
save_config() {
    {
        printf 'git_url=%s\n' "${git_url}"
        printf 'git_user=%s\n' "${git_user}"
        printf 'git_pass=%s\n' "${git_pass}"
        printf 'git_branch_master_name=%s\n' "${git_branch_master_name}"
        printf 'git_pull_master_allow=%s\n' "${git_pull_master_allow}"
        printf 'domain_name=%s\n' "${domain_name}"
        printf 'bitrix_home_dir=%s\n' "${bitrix_home_dir}"
    } >$config_file
    ## Обновляем права на файлы
    chown bitrix:bitrix $config_file
}

## Загружаем конфиг
load_config() {
    if test -f "$config_file"; then
        echo "Конфигурационный файл - $config_file существует"
        . "${config_file}"
        true
    else
        echo "Конфигурационный файл - $config_file не существует"
        false
    fi
}

## Очищаем настройки
clear_config() {
    git_status=""
    git_url=""
    git_user=""
    git_pass=""
    git_branch_master_name=""
    git_pull_master_allow=""
}

## Проверяем необходимые данные в конфигурационном файле
check_config() {
    if [[ -z $git_url ||
        -z $git_user ||
        -z $git_pass ||
        -z $git_branch_master_name ||
        -z $git_pull_master_allow ||
        -z $bitrix_home_dir ||
        -z $domain_name ]] \
        ; then
        if ! is_root; then
            echo "Надо заполнить файл с конфигурацией, запустите под root пользователем"
            exit
        fi
        echo -e "Надо заполнить файл с конфигурацией"
        first_run
    fi
}

## Сохраняем конфиг
save_remote() {
    {
        printf 'remote_user=%s\n' "${remote_user}"
        printf 'remote_password=%s\n' "${remote_password}"
        printf 'remote_host=%s\n' "${remote_host}"
        printf 'remote_port=%s\n' "${remote_port}"
        printf 'remote_mysql_user=%s\n' "${remote_mysql_user}"
        printf 'remote_mysql_password=%s\n' "${remote_mysql_password}"
    } >$remote_file
}
## Загружаем конфиг стороннего сервера
load_remote() {
    if test -f "$remote_file"; then
        echo "Конфигурационный файл - $remote_file существует"
        . "${remote_file}"
        true
    else
        echo "Конфигурационный файл - $remote_file не существует"
        false
    fi
}

## Очищаем настройки стороннего сервера
clear_remote() {
    remote_user=""
    remote_password=""
    remote_host=""
    remote_port=""
    remote_mysql_user=""
    remote_mysql_password=""
}

## Проверяем необходимые данные в конфигурационном файле
check_remote() {
    if [[ -z $remote_user ||
        -z $remote_password ||
        -z $remote_host ||
        -z $remote_port ||
        -z $remote_mysql_user ||
        -z $remote_mysql_password ]] \
        ; then
        if ! is_root; then
            echo "Надо заполнить файл с конфигурацией, запустите под root пользователем"
            exit
        fi
        echo -e "Надо заполнить файл с конфигурацией"
        remote_first_run
    fi
}

## Показать меню в зависимости от прав
select_menu() {
    if is_root; then
        menu
    else
        menu_bitrix
    fi
}

## Запустить команду на другом сервере
remote_ssh_command() {
    sshpass -p $remote_password ssh -p $remote_port -tt -o StrictHostKeyChecking=no $remote_user@$remote_host -q $1
}

## Проверить доступность соединения другого сервера
remote_server_reachable() {
    status=$(remote_ssh_command "echo ok" 2>&1)
    if [ $? -eq 0 ]; then
        true
    else
        false
    fi
}

## Проверить доступность подключения к mysql на другом сервере
remote_mysql_reachable() {
    status=$(remote_ssh_command "mysql -u $remote_mysql_user -p$remote_mysql_password -e 'SHOW DATABASES;'" 2>&1)
    # Check the connection status
    if [ $? -eq 0 ]; then
        true
    else
        false
    fi
}

## Заполнение настроек другого сервера
remote_first_run() {
    until [[ "$remote_status" == "ok" ]]; do

        until [[ "$remote_host" ]]; do
            IFS= read -p "IP: " -r remote_host
        done

        until [[ "$remote_port" ]]; do
            IFS= read -p "Порт: " -r remote_port
        done

        until [[ "$remote_user" ]]; do
            IFS= read -p "Логин: " -r remote_user
        done

        until [[ "$remote_password" ]]; do
            IFS= read -p "Пароль от $remote_user: " -r remote_password
        done

        if remote_server_reachable; then
            echo "Сервер $remote_host:$remote_port доступен"
            remote_status="ok"
        else
            echo "Сервер $remote_host:$remote_port не доступен"
            remote_status="err"
            remote_host=""
            remote_port=""
            remote_user=""
            remote_password=""
        fi
    done

    until [[ "$remote_mysql_status" == "ok" ]]; do
        until [[ "$remote_mysql_user" ]]; do
            IFS= read -p "Логин mysql: " -r remote_mysql_user
        done

        until [[ "$remote_mysql_password" ]]; do
            IFS= read -p "Пароль mysql: " -r remote_mysql_password
        done

        if remote_mysql_reachable; then
            echo "Mysql на сервере $remote_host:$remote_port доступен"
            remote_mysql_status="ok"
        else
            echo "Mysql на сервере $remote_host:$remote_port не доступен"
            remote_mysql_status="err"
            remote_mysql_user=""
            remote_mysql_password=""
        fi
    done

    ## Сохраняем настройки
    save_remote
}

## Переезд на другой сервер
run_remote() {
    load_remote
    remote_first_run
    until [[ "$remote_allow_start" ]]; do
        IFS= read -p "Запустить синхронизацию файлов и mysql? [y/N]: " -r remote_allow_start
    done
    if [[ $remote_allow_start == "y" ]]; then
        remote_allow_start=""
        remote_start_time=$(date +%s.%N)
        ## Синхронизация файлов
        remote_dir_from="/home/bitrix/www/"
        remote_dir_to="/home/bitrix/www/"
        sshpass -p $remote_password rsync -v -ae "ssh -p $remote_port" --delete --exclude /bitrix/.settings.php --exclude /bitrix/.isprod --exclude /bitrix/.settings_extra.php --exclude /bitrix/php_interface/dbconn.php --exclude /bitrix/php_interface/after_connect.php --exclude /bitrix/php_interface/after_connect_d7.php --exclude bitrix/backup --exclude bitrix/cache --exclude bitrix/html_pages --exclude bitrix/managed_cache --exclude bitrix/stack_cache --exclude local/logs --progress "$remote_dir_from" "$remote_user@$remote_host:$remote_dir_to"
        echo "Синхронизация файлов завершена"

        ## Загружаем текущие настройки mysql
        . "$mysql_root_config_file"
        remote_mysql_db_from="sitemanager"
        remote_mysql_db_to="sitemanager"

        ## Метод 1, через mysqldump
        remote_temp_db_file="/root/migration.sql"
        remote_temp_db_file_gz="$remote_temp_db_file.gz"
        echo "Создаём дамп базы данных"
        mysqldump --verbose -u$user -p$password --socket=$socket $remote_mysql_db_from >$remote_temp_db_file
        echo "Создание дампа завершено, заменяем кодировку"
        sed -i 's/CHARSET=utf8/CHARSET=utf8mb4/g; s/utf8_unicode_ci/utf8mb4_0900_ai_ci/g; s/utf8_bin/utf8mb4_bin/g' $remote_temp_db_file
        echo "Замена кодировки завершена, архивируем"
        gzip --verbose --force $remote_temp_db_file
        echo "Архивация завершена, отправляем архив на сервер"
        sshpass -p $remote_password rsync -avze "ssh -p $remote_port" --progress $remote_temp_db_file_gz "$remote_user@$remote_host:$remote_temp_db_file_gz"
        echo "Файл отправлен, запускаем разархивацию и импорт"
        remote_ssh_command "gunzip -v -c $remote_temp_db_file_gz | mysql --default-character-set=utf8mb4 -u $remote_mysql_user -p$remote_mysql_password $remote_mysql_db_to"
        rm -f "$remote_temp_db_file_gz"
        echo "Импорт mysql базы $remote_mysql_db_to завершён"

        ## TODO: Метод 2, через mysqldbcopy и ssh тоннель к сокету

        ## Сколько затрачено времени
        remote_end_time=$(date +%s.%N)
        runtime=$(echo "$remote_end_time - $remote_start_time" | bc -l)
        echo "Затрачено времени: $runtime секунд"
        exit
    fi
}

## Задаём настройки
first_run() {
    until [[ "$git_status" == "ok" ]]; do
        until [[ "$git_url" ]]; do
            IFS= read -p "Введите ссылку на репозиторий (https://github.com/user/repo.git): " -r git_url
        done

        until [[ "$git_user" ]]; do
            IFS= read -p "Логин: " -r git_user
        done

        until [[ "$git_pass" ]]; do
            echo "Внимание! Github использует персональные ключи, обычный пароль не подойдёт"
            IFS= read -p "Пароль: " -r git_pass
        done

        if git_remote_url_reachable "$git_url"; then
            echo "Репозиторий доступен"
            git_status="ok"
        else
            echo "Репозиторий $git_url не доступен"
            git_status="err"
            git_user=""
            git_pass=""
        fi
    done

    git_branch_list
    until [[ "$git_branch_master_name" ]]; do
        IFS= read -p "Название основной ветки? (master): " -r git_branch_master_name
        if ! git_check_branch "$git_branch_master_name"; then
            echo -e "Ветка $git_branch_master_name не существует"
            git_branch_master_name=""
        fi
    done

    until [[ "$git_pull_master_allow" ]]; do
        IFS= read -p "Разрешить pull у $git_branch_master_name ветки? (y/N): " -r git_pull_master_allow
    done

    until [[ "$domain_name" ]]; do
        IFS= read -p "Основной домен (без http(s), например yandex.ru): " -r domain_name
        domain_name=$(sed -E -e 's_.*://([^/@]*@)?([^/:]+).*_\2_' <<<"$domain_name")
    done

    ## Сохраняем настройки
    save_config

    ## Устанавливаем себя глобально
    install_self

    ## Запускаем меню
    select_menu
}

## Ручной ввод ветки для принятия коммитов
git_pull_one() {
    git_list
    branch_name=""
    until [[ "$branch_name" ]]; do
        IFS= read -p "Введите имя ветки для обновления: " -r branch_name
    done
    git_pull "$branch_name"
}

## Список существующих гитов/веток
git_list() {
    line
    local result=""
    ## Заголовок таблицы
    printf -v result '%s\t%s\t%s' "Ветка" "Коммит" "Директория"
    if [[ $1 == "dns" ]]; then
        printf -v result "%s\t%s\t%s" "$result" "Домен" "DNS-A"
    fi

    for dir in $(find $bitrix_home_dir -maxdepth 3 -type d -name ".git"); do
        cd "${dir%/*}" || exit
        current_branch_name=$(git symbolic-ref --short -q HEAD)

        ## Текущий коммит
        current_commit=$(git show -s --format='%h / %ai / %s')

        ## Проверяем наличие A записи у доменов
        local dns=""
        if [[ $1 == "dns" ]]; then
            local domain=$(pwd | sed 's#.*/##')""
            ## Переопределяем для основного домена
            if [[ $domain == "www" ]]; then
                domain="$domain_name"
            fi
            printf -v dns "%s\t%s" "$domain" "$(check_dns_a_record "$domain")"
        fi

        ## Ячейка таблицы
        printf -v result "%s\n%s\t%s\t%s\t%s\n" "$result" "$current_branch_name" "$current_commit" "$PWD" "$dns"
        cd - >/dev/null || exit
    done
    ## Строим таблицу
    echo "$result" | sed 's/\t/,|,/g' | column -s ',' -t
    cd "$HOME" || exit
}

## Запуск процедуры принятия коммитов
git_pull() {
    if [[ "$git_pull_master_allow" != "y" && $git_branch_master_name == "$1" ]]; then
        echo -e "$git_branch_master_name ветку запрещено автоматически обновлять"
        wait
        return 0
    fi

    echo -e "Пробуем найти ветку $1 в $bitrix_home_dir"
    for dir in $(find $bitrix_home_dir -maxdepth 3 -type d -name ".git"); do
        cd "${dir%/*}" || exit
        current_branch_name=$(git symbolic-ref --short -q HEAD)
        if [[ "$current_branch_name" == "$1" ]]; then
            echo -e "Найдена директория: $PWD; Ветка: $current_branch_name;"

            git_get_credential_helper

            ## Проверяем на совпадение директории и конфига
            current_remote_url=$(git_current_remote_url)
            if [[ "$current_remote_url" != "$git_url" ]]; then
                echo -e "Внимание!"
                echo -e "Репозиторий в каталоге = $current_remote_url"
                echo -e "Репозиторий в настройках = $git_url"

                if ! git_check_branch "$current_branch_name"; then
                    echo -e "Критическая ошибка! Ветка $current_branch_name не существует в $git_url"
                    exit
                else
                    echo -e "Ветка $current_branch_name существует в $git_url"
                fi
                echo -e "Переключаю репозиторий на $git_url"
                git remote set-url origin "$git_url"
            fi

            ##  Устанавливаем настройки
            git config --local user.name "server"
            git config --local user.email "$git_user"

            ## Аккуратная работа с мастер веткой.
            if [[ $git_branch_master_name == "$1" ]]; then
                echo -e "Проверяем наличие изменений в мастер ветке $git_branch_master_name"

                if [[ $(git status --porcelain) ]]; then
                    local git_new_branch_master="$git_branch_master_name-""$(date +%d%m%y-%H%I%S)"
                    warning_text "Обнаружены изменения в мастер ветке. Будет создана новая ветка $git_new_branch_master."
                    git checkout -b "$git_new_branch_master"
                    git add .
                    git commit -m "Master auto commit from server"
                    git -c credential.helper="$HELPER" push -u origin "$git_new_branch_master"
                    git checkout "$current_branch_name"
                    warning_text "Не забудьте слить ветку $git_new_branch_master с $git_branch_master_name"
                else
                    echo -e "Изменений в мастер ветке нет. Всё хорошо."
                fi
            fi
            ## https://stackoverflow.com/questions/17404316/the-following-untracked-working-tree-files-would-be-overwritten-by-merge-but-i
            ## 1я стратегия, не сработает, если есть не отслеживаемые файлы
            # git reset --hard
            # git -c credential.helper="$HELPER" pull

            ## 2я стратегия - чистим всё
            git -c credential.helper="$HELPER" fetch --all
            git reset --hard origin/"$current_branch_name"

            ## 3я стратегия, лайтовее, не сделает ничего не не отслеживаемыми файлами
            # git checkout -f donor-branch   # replace bothersome files with tracked versions
            # git checkout receiving-branch  # tracked bothersome files disappear
            # git merge donor-branch         # merge works

            ## 3.1 Или так
            # git fetch
            # git checkout -f origin/mybranch   # replace bothersome files with tracked versions
            # git checkout mybranch             # tracked bothersome files disappear
            # git pull origin/mybranch          # pull works

            ## Сбрасываем права
            chown -R bitrix:bitrix "$PWD"
            cd "$HOME" >/dev/null || exit
        fi
    done
    cd "$HOME" || exit
    wait
}

## Название текущей локальной активной ветки
git_current_local_branch() {
    git branch | awk '/\*/ { print $2; }'
}

## Текущий подключенный репозиторий
git_current_remote_url() {
    git config --local --get remote.origin.url
}

## Проверить существование ветки
git_check_branch() {
    git -c credential.helper="$HELPER" ls-remote --exit-code --heads "$git_url" "$1"
}

## Список существующих веток
git_branch_list() {
    echo -e "Существующие ветки:"
    git -c credential.helper="$HELPER" ls-remote --exit-code --heads "$git_url"
}

## Запуск создания нового .git
git_init_one() {
    git_new_dir=""
    git_new_branch=""
    git_new_dir_override=""
    git_new_branch_create=""
    git_init
}

## Инициализация репозитория
git_init() {
    until [[ "$git_new_dir" ]]; do
        IFS= read -p "Директория для создания гита: " -r git_new_dir
        if [[ ! -d $git_new_dir ]]; then
            echo -e "Директория $git_new_dir не существует"
            ## TODO: Создать?
            git_new_dir=""
        fi
        if [[ -d "$git_new_dir/.git" ]]; then
            echo -e "В директории $git_new_dir уже присуствует .git"
            until [[ "$git_new_dir_override" ]]; do
                IFS= read -p "Пересоздать гит? [y/N]: " -r git_new_dir_override
            done
            if [[ $git_new_dir_override != "y" ]]; then
                git_new_dir=""
                git_new_dir_override=""
            fi
        fi
    done

    git_get_credential_helper
    git_branch_list
    until [[ "$git_new_branch" ]]; do
        IFS= read -p "Название ветки: " -r git_new_branch
        if [[ "$git_new_branch" == "$git_branch_master_name" ]]; then
            echo -e "Сам инициализируй $git_new_branch ветку, это важно. Не ленись."
            exit
        fi

        if ! git_check_branch "$git_new_branch"; then
            echo -e "Ветка $git_new_branch не существует"

            until [[ "$git_new_branch_create" ]]; do
                IFS= read -p "Создать новую ветку (от $git_branch_master_name), будет reset --hard? [y/N]: " -r git_new_branch_create
            done

            if [[ $git_new_branch_create != "y" ]]; then
                git_new_branch=""
            fi
        fi
    done

    ## Перемещаем старый гит
    if [[ $git_new_dir_override == "y" ]]; then
        mv "$git_new_dir/.git" "$git_new_dir/.git.""$(date +%d%m%y.%H%I%S)"
    fi

    cd "$git_new_dir" || exit

    ##  Устанавливаем настройки
    git config --global --add safe.directory "$git_new_dir"
    git config --global user.name "server"
    git config --global user.email "$git_user"
    git config --global push.default simple

    ##  Создаём новый гит
    git init
    git remote add origin "$git_url"
    if [[ $git_new_branch_create == "y" ]]; then

        if ! git_check_branch "$git_branch_master_name"; then
            echo -e "Критическая ошибка! Ветка $git_branch_master_name не существует"
            exit
        fi
        ## Делаем новую ветку от мастера
        git -c credential.helper="$HELPER" fetch origin
        git branch "$git_branch_master_name" origin/"$git_branch_master_name"

        git -c credential.helper="$HELPER" fetch --all
        git reset --hard origin/"$git_branch_master_name"

        git checkout -b "$git_new_branch"
        if [[ $(git_current_local_branch) == "$git_new_branch" ]]; then
            git -c credential.helper="$HELPER" push --set-upstream origin "$git_new_branch"
        else
            echo -e "Ошибка при создании $git_new_branch ветки!"
            exit
        fi
    else
        ## Если существующая ветка
        git checkout -b "$git_new_branch"
        git -c credential.helper="$HELPER" fetch origin
        git branch "$git_new_branch" origin/"$git_new_branch"
        git branch --set-upstream-to=origin/"$git_new_branch" "$git_new_branch"
    fi

    chown -R bitrix:bitrix "$git_new_dir"

    git status
    echo -e "Текущие ветки:"
    git branch -a
}

## Ручной выбор сайта для актуализации
select_site_to_clone_one() {
    clear
    git_list ""
    clone_site_path_from=""
    clone_site_path_to=""
    clone_mode=""
    select_site_to_clone
}

## Проверить наличие cron задания
check_cloudflare_cron() {
    if ! test -f "$cloudflare_cronfile"; then
        warning_text "Cron задание для обновления $CLOUDFLARE_IP_RANGES_FILE_PATH отключено"
    fi
}

## Удалить cron задание
remove_cloudflare_cron() {
    if [ "$(check_cloudflare_cron)" != "" ]; then
        echo -e "Нечего удалять"
    else
        rm -rf "$cloudflare_cronfile"
        echo -e "Файл с cron заданием $cloudflare_cronfile удалён"
    fi
}

## Установить cron задание
set_cloudflare_cron() {
    echo "$cloudflare_cronjob" >"$cloudflare_cronfile"
    echo -e "Задание добавлено: $cloudflare_cronjob"
    service crond restart
}

## Проверить наличие файла с настройками set_real_ip_from cloudflare для nginx
check_cloudflare() {
    if ! test -f "$CLOUDFLARE_IP_RANGES_FILE_PATH"; then
        warning_text "Файл $CLOUDFLARE_IP_RANGES_FILE_PATH отсуствует"
    fi
}

## Проверить наличие файла с настройками блокировки прямого захода cloudflare для nginx
check_cloudflare_direct_block() {
    if ! test -f "$CLOUDFLARE_DIRECT_BLOCK_FILE_PATH"; then
        warning_text "Файл $CLOUDFLARE_DIRECT_BLOCK_FILE_PATH отсуствует"
    fi
}

## Удалить файл с настройками cloudflare для nginx
remove_cloudflare() {
    if [ "$(check_cloudflare)" != "" ]; then
        echo -e "Нечего удалять"
    else
        rm -rf "$CLOUDFLARE_IP_RANGES_FILE_PATH"
        echo -e "Файл $CLOUDFLARE_IP_RANGES_FILE_PATH удалён"
    fi
}

## Подстановка настоящего ip адреса, если сайт защищён cloudflare
set_cloudflare() {
    # https://dev.1c-bitrix.ru/support/forum/forum32/topic76006/

    CLOUDFLARE_IPSV4_REMOTE_FILE="https://www.cloudflare.com/ips-v4"
    CLOUDFLARE_IPSV6_REMOTE_FILE="https://www.cloudflare.com/ips-v6"
    CLOUDFLARE_IPSV4_LOCAL_FILE="/tmp/cloudflare-ips-v4"
    CLOUDFLARE_IPSV6_LOCAL_FILE="/tmp/cloudflare-ips-v6"

    echo -e "Скачиваем файл $CLOUDFLARE_IPSV4_REMOTE_FILE"
    wget -q $CLOUDFLARE_IPSV4_REMOTE_FILE -O $CLOUDFLARE_IPSV4_LOCAL_FILE --no-check-certificate
    echo -e "Скачиваем файл $CLOUDFLARE_IPSV6_REMOTE_FILE"
    wget -q $CLOUDFLARE_IPSV6_REMOTE_FILE -O $CLOUDFLARE_IPSV6_LOCAL_FILE --no-check-certificate

    {
        echo "# CloudFlare IP Ranges"
        echo "# Generated at $(date) by $0"
        echo ""
        echo "# IPs v4"
        awk '{ print "set_real_ip_from " $0 ";" }' $CLOUDFLARE_IPSV4_LOCAL_FILE
        echo ""
        echo "# IPs v6"
        awk '{ print "set_real_ip_from " $0 ";" }' $CLOUDFLARE_IPSV6_LOCAL_FILE
        echo ""
        echo "# Getting real ip from CF-Connecting-IP header"
        echo "real_ip_header CF-Connecting-IP;"
        echo ""
    } >$CLOUDFLARE_IP_RANGES_FILE_PATH

    chown bitrix:bitrix $CLOUDFLARE_IP_RANGES_FILE_PATH

    rm -rf $CLOUDFLARE_IPSV4_LOCAL_FILE
    rm -rf $CLOUDFLARE_IPSV6_LOCAL_FILE
    echo -e "Файл $CLOUDFLARE_IP_RANGES_FILE_PATH записан"
    systemctl reload nginx.service
    echo -e "systemctl reload nginx.service"
}

## Для консольного запуска
usage() {
    echo -e "-u {path_to_update} - актуализировать определённый сайт"
    echo -e "-b {git branch name} - для запуска процедуры git pull определённой ветки"
    echo -e "-s {минимальный процент для вывода сообщения} - проверить свободное место"
    echo -e "-c - cloudflare nginx ip set (только от root)"
    echo -e "-h - вывести это сообщение"
}

## Меню не root пользователя
menu_bitrix() {
    until [[ "$TARGET_SELECTION" == "0" ]]; do
        header

        echo -e "\t\t1. Принять изменения определённой ветки"
        echo -e "\t\t*. Запустите от root, для доступа к другим пунктам меню"
        echo -e "\t\t0. Выход"

        IFS= read -p "Пункт меню: " -r TARGET_SELECTION
        case "$TARGET_SELECTION" in
        "1" | pull) git_pull_one ;;
        0 | z) exit ;;
        *) no_menu ;;
        esac
    done
}

## Заголовок
title() {
    clear
    echo -e "\033[1m\t\t\tBitrix.DevOps" "$version" "(c)DCRM\n\033[m"
}

## Шапка
header() {
    title
    ## Проверяем установку основного сайта
    check_install_master_site
    ## Проверяем настройки sftp
    check_openssh_chroot
    ## Проверим /etc/hosts
    check_hosts
    ## Проверим свободное место
    check_size 10
    ## Сразу проверим ip
    check_ip
    ## Проверим текущий ssh порт
    check_openssh_port
    ## Информация о домене
    echo -e "Домен: $domain_name"
    ## Информация о репозитории
    echo -e "Репозиторий: $git_url\n"
    git_list "dns"
    line
    echo -e "Доступные действия:"
}

## Вывод основного меню
menu() {
    until [[ "$TARGET_SELECTION" == "0" ]]; do
        header

        echo -e "\t\t1. Принять изменения определённой ветки"
        echo -e "\t\t2. (Пере)Создать репозиторий с определённой веткой"
        echo -e "\t\t3. (Пере)Создать пользователя=гитветку=поддомен=клон основного сайта файлов и бд"
        echo -e "\t\t4. Изменить пароль у существующего пользователя"
        echo -e "\t\t5. Актуализировать сайт"
        echo -e "\t\t6. (Пере)Создать вебхук"

        echo -e "\t\t7. Cloudflare для nginx (определение ip адреса)"
        echo -e "\t\t8. Настройки dev.sh"

        echo -e "\t\t9. Переезд на другой сервер"
        echo -e "\t\t10. Запустить bitrixenv"
        echo -e "\t\t0. Выход\n"

        IFS= read -p "Пункт меню: " -r TARGET_SELECTION
        case "$TARGET_SELECTION" in
        "1" | pull)
            git_pull_one
            wait
            ;;
        "2" | init)
            git_init_one
            wait
            ;;
        "3" | site)
            create_site
            wait
            ;;
        "4" | pwd)
            change_password_exist_user
            wait
            ;;
        "5" | sync)
            select_site_to_clone_one
            wait
            ;;
        "6" | webhook) set_webhook ;;
        "7" | cloudflare) menu_cloudflare ;;
        "8" | settings) menu_settings ;;

        "9" | env)
            run_remote
            ;;

        "10" | env)
            start_bitrixenv
            exit
            ;;

        0 | z) exit ;;
        *) no_menu ;;
        esac
    done
}

## Меню с настройками
menu_settings() {
    until [[ "$SETTINGS_SELECTION" == "0" ]]; do
        title
        echo -e "Настройки dev.sh"
        line
        echo -e "Доступные действия:"

        echo -e "\t\t1. Переустановить конфигурацию этого скрипта"
        echo -e "\t\t2. Обновить установленный скрипт"
        echo -e "\t\t3. Установить текущий скрипт"
        # echo -e "\t\t400. Проверить наличие DNS A записи у поддомена"
        echo -e "\t\t0. Назад\n"

        IFS= read -p "Пункт меню: " -r SETTINGS_SELECTION
        case "$SETTINGS_SELECTION" in
        "1" | clear)
            clear_config
            first_run
            wait
            ;;
        "2" | install)
            update_self
            wait
            ;;
        "3" | update)
            install_self
            wait
            ;;
        "400" | dns)
            check_dns_a_record_one
            wait
            ;;

        0 | z) return ;;
        *) no_menu ;;
        esac
    done
}

## Меню с cloudflare
menu_cloudflare() {
    until [[ "$CLOUDFLARE_SELECTION" == "0" ]]; do
        title
        echo -e "Cloudflare для nginx (определение ip адреса)"
        check_cloudflare
        check_cloudflare_cron
        check_cloudflare_direct_block
        line
        echo -e "Доступные действия:"

        echo -e "\t\t1. Включить периодическое обновление файла для nginx"
        if [ "$(check_cloudflare_cron)" == "" ]; then
            echo -e "\t\t2. Отключить периодическое обновление файла для nginx"
        fi

        echo -e "\t\t3. (Пере)Создать файл с определением ip адресов от cloudflare для nginx"
        if [ "$(check_cloudflare)" == "" ]; then
            echo -e "\t\t4. Удалить файл для подстановки ip адресов от cloudflare для nginx"
        fi
        echo -e "\t\t0. Назад\n"

        IFS= read -p "Пункт меню: " -r CLOUDFLARE_SELECTION
        case "$CLOUDFLARE_SELECTION" in
        "1" | cron)
            set_cloudflare_cron
            wait
            ;;
        "2" | crondel)
            remove_cloudflare_cron
            wait
            ;;
        "3" | set)
            set_cloudflare
            wait
            ;;
        "4" | del)
            remove_cloudflare
            wait
            ;;

        0 | z) return ;;
        *) no_menu ;;
        esac
    done
}

## Проверка на первый запуск скрипта
if load_config; then

    ## Проверяем, всего ли хватает
    check_config

    ## Если запустили с флагами
    while getopts "hcb:s:u:" flag; do
        case "$flag" in
        u)
            clone_site_path_from="/home/bitrix/www"
            clone_site_path_to=${OPTARG}
            console_site_clone
            exit
            ;;
        b)
            branch=${OPTARG}
            git_pull "$branch"
            exit
            ;;
        s)
            free_limit=${OPTARG}
            clear
            check_size "$free_limit"
            exit
            ;;
        c)
            if is_root; then set_cloudflare; fi
            exit
            ;;
        \? | h)
            usage
            exit
            ;;
        esac
    done

    ## Обычное или ограниченное меню
    select_menu
else
    if ! is_root; then
        echo "Скрипт не инициализирован, запустите под root пользователем"
        exit
    fi
    echo -e "Первый запуск скрипта"
    ## Устанавливаем себя глобально
    install_self

    first_run
fi
