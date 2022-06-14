#!/bin/bash

## Проверено на bitrixenv 7.5.2
version=1.0

## Группа пользователей для разработчиков
user_group=dev-group

## Путь к файлу конфигурации
config_file=/home/bitrix/.dev.cnf

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
    read -t 3 -r > /dev/null
}

# Заглушка
no_menu() {
    echo -e ""
}

# Линия
line() {
    printf "\x2d%.0s"  $(seq 1 85)
    printf "\n"
}

## Устанавливаем битрикс окружение
install_bitrixenv() {
    echo "Bitrixenv не обнаружен, устанавливаем..."
    yum clean all && yum -y update
    yum install -y wget
    wget -O bitrix-env.sh https://repo.bitrix.info/yum/bitrix-env.sh && chmod +x bitrix-env.sh && ./bitrix-env.sh
    exit
}

## Проверяем команду arg1 на существование
check_command() {
    if ! command -v $1 > /dev/null; then
        echo -e "Command $1 not found!"
        false
    else
        true
    fi
}

## Подгрузим необходимые утилиты
init_service_tools() {
    if ! check_command "dig"; then
        yum install -y bind-utils
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
init_global_ip() {
    global_ip=$(dig @resolver4.opendns.com myip.opendns.com +short -4)
}
init_global_ip

## Текущий локальный IP
init_local_ip() {
    current_ip=$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p')
}
init_local_ip

## Сравним локальный и глобальынй ip
check_ip() {
    if [[ "$current_ip" != "$global_ip" ]]; then
        echo "IP Глобальный $global_ip и локальный $current_ip отличаются"
    fi
}

## Проверить dns A поддомена
check_dns_a_record() {
    dig "$1" A +short
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
wait_task(){
    local task_status=""
    until [[ "$task_status" == "finished" ]]; do
        task_status=$(get_task_status "$1")
        echo "$task_status; "
        sleep 1
    done
}

## Получить случайную строку
get_random_string(){
    date +%s | sha256sum | base64 | head -c 12 ; echo
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
check_openssh_chroot(){
    if ! grep -q -F "$user_group" /etc/ssh/sshd_config; then
        echo "Необходимо внести правки в файл /etc/ssh/sshd_config"
        echo "Subsystem sftp internal-sftp"
        echo "Match Group $user_group"
        echo "ChrootDirectory /home/%u"
        line
    fi   
}

## Добавляем точку монтирования для пользователя в его домашний каталог
add_mount_point() {
    if ! grep -q "/home/$1/www" /etc/fstab; then
        {
            printf '\n# dev.sh %s start' "$1";
            printf '\n/home/bitrix/ext_www/%s /home/%s/www none bind 0 0' "$1.$domain_name" "$1";
            printf '\n# dev.sh %s end' "$1";
            printf '\n'; ## Важно!
        } >> /etc/fstab
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
    local task=$(/opt/webdir/bin/bx-sites -a create -s "$1"."$domain_name" -t kernel --charset UTF-8 --cron)
    local task_id=$(get_task_id "$task")
    echo -e "Задание $task_id для создания сайта $1.$domain_name - запущено, ждём"
    wait_task "$task_id"

    ## TODO:
    ## Копируем сайт+БД

    ## Создаём гит+ветку
    git_new_dir="/home/bitrix/ext_www/$1.$domain_name"
    git_new_branch="$1"
    git_new_dir_override="y"
    git_new_branch_create="y"
    git_init

    ## Создаём пользователя
    create_user "$1"

    ## Суммарная информация
    clear
    printf -v report 'Репозиторий: %s\nДомен: %s\nIP: %s\nSFTP пользователь/гит-ветка: %s\nSFTP пароль: %s' "$git_url" "$1.$domain_name" "$current_ip" "$1" "$user_pswd"
    echo "$report" > "/root/.dev.$1.info"
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
        chown root:bitrix /home/"$1"/
        chmod 750 /home/"$1"/
        set_user_random_password "$1"
        add_mount_point "$1"
        ## Разово монтируем каталог, что бы не перезагружать сервер
        mount --bind /home/bitrix/ext_www/"$1.$domain_name" /home/"$1"/www
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
    wget -O "$global_file" "$update_url" && chmod +x "$global_file" && bitrix:bitrix "$global_file"
    echo -e "$global_file - обновлён"
    wait
    exec $global_file
}

## Проверяем свободное место
check_size() {
    local used=$( df -h / --output=pcent | awk 'END{ print $(NF-1) }' | tr -d '%' )
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
        printf 'git_url=%s\n' "${git_url}";
        printf 'git_user=%s\n' "${git_user}";
        printf 'git_pass=%s\n' "${git_pass}";
        printf 'git_branch_master_name=%s\n' "${git_branch_master_name}";
        printf 'git_pull_master_allow=%s\n' "${git_pull_master_allow}";
        printf 'bitrix_home_dir=%s\n' "${bitrix_home_dir}";
        printf 'domain_name=%s\n' "${domain_name}";
    } > $config_file
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
check_config(){
    if [[ -n $git_url || -n $git_user || -n $git_pass || -n $git_branch_master_name || -n $git_pull_master_allow || -n $bitrix_home_dir || -n $domain_name ]]; then
        first_run
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
        domain_name=$(sed -E -e 's_.*://([^/@]*@)?([^/:]+).*_\2_' <<< "$domain_name")
    done
    
    ## Сохраняем настройки
    save_config

    ## Устанавливаем себя глобально
    install_self

    ## Запускаем основное меню
    menu
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
    printf -v result '%s\t%s\t%s\n' "Ветка" "Директория" "DNS"
    for dir in $(find $bitrix_home_dir -maxdepth 3 -type d -name ".git")
        do cd "${dir%/*}" || exit
            current_branch_name=$(git symbolic-ref --short -q HEAD)
            
            ## Проверяем наличие A записи у доменов
            local dns=""
            if [[ $1 == "dns" ]]; then
                local domain=$(pwd | sed 's#.*/##')""
                ## Переопределяем для основного домена
                if [[ $domain == "www" ]]; then
                    domain="$domain_name"
                fi
                dns="$domain A: $(check_dns_a_record "$domain")"
            fi
            ## Ячейка таблицы
            printf -v result "%s%s\t%s\t%s\n" "$result" "$current_branch_name" "$PWD" "$dns"
            cd - > /dev/null || exit
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
    for dir in $(find $bitrix_home_dir -maxdepth 3 -type d -name ".git")
        do cd "${dir%/*}" || exit
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

                ## https://stackoverflow.com/questions/17404316/the-following-untracked-working-tree-files-would-be-overwritten-by-merge-but-i
                ## 1я стратегия, не сработает, если есть не отслеживаемые файлы
                # git reset --hard
                # git -c credential.helper="$HELPER" pull

                ## 2я стратегия - чистим всё
                git -c credential.helper="$HELPER" fetch --all
                git reset --hard origin/$current_branch_name

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
                cd "$HOME" > /dev/null || exit
            fi
        done
    cd "$HOME" || exit
    wait
}

## Название текущей локальной активной ветки
git_current_local_branch(){
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
            fi
        fi
    done
    
    ## Перемещаем старый гит
    if [[ $git_new_dir_override == "y" ]]; then
        mv "$git_new_dir/.git" "$git_new_dir/.git.""$(date +%d%m%y.%H%I%S)"
    fi

    git_get_credential_helper
    git_branch_list
    until [[ "$git_new_branch" ]]; do
            IFS= read -p "Название ветки: " -r git_new_branch

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

    cd "$git_new_dir" || exit

    ##  Устанавливаем настройки
    git config --global user.name "server"
    git config --global user.email "server@localhost"
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
        git reset --hard
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

# Меню не root пользователя
menu_bitrix() {
    until [[ "$TARGET_SELECTION" == "0" ]]; do
        header

        echo -e "\t\t1. Принять изменения определённой ветки"
        echo -e "\t\t*. Запустите от root, для доступа к другим пунктам меню"
        echo -e "\t\t0. Выход"

        IFS= read -p "Пункт меню: " -r TARGET_SELECTION
        case "$TARGET_SELECTION" in 
            "1"|pull)  git_pull_one;;
            0|z)  exit;;
            *)    no_menu;;
        esac
    done
}

## Вывод основного меню
menu() {
    until [[ "$TARGET_SELECTION" == "0" ]]; do
        header

        echo -e "\t\t1. Принять изменения определённой ветки"
        echo -e "\t\t3. (Пере)Создать репозиторий с определённой веткой"
        echo -e "\t\t6. Создать пользователя=гитветку=поддомен"
        echo -e "\t\t7. Проверить наличие DNS A записи у поддомена"
        echo -e "\t\t8. Изменить пароль у существующего пользователя"
        echo -e "\t\t10. Переустановить конфигурацию репозитория"
        echo -e "\t\t11. Обновить скрипт из гита"
        echo -e "\t\t12. Установить текущий скрипт"
        echo -e "\t\t20. Запустить bitrixenv"
        echo -e "\t\t0. Выход"

        IFS= read -p "Пункт меню: " -r TARGET_SELECTION
        case "$TARGET_SELECTION" in 
            "1"|pull)  git_pull_one; wait;;
            "3"|init)  git_init_one; wait;;
            "6"|site)  create_site; wait;;
            "7"|dns)  check_dns_a_record_one; wait;;
            "8"|pwd)  change_password_exist_user; wait;;
            "10"|clear) clear_config; first_run; wait;;
            "11"|install) update_self; wait;;
            "12"|update) install_self; wait;;
            "20"|env) start_bitrixenv; exit;;
            0|z)  exit;;
            *)    no_menu;;
        esac
    done  
}

## Заголовок
header() {
    clear
    echo -e "Bitrix.DevOps" "$version" "(c)DCRM"
    ## Проверяем настройки sfto
    check_openssh_chroot
    ## Проверим свободное место
    check_size 10
    ## Сразу проверим ip
    check_ip
    ## Информация о домене
    echo -e "Домен: $domain_name"
    ## Информация о репозитории
    echo -e "Репозиторий: $git_url"
    git_list "dns"
    line
}

## Для консольного запуска
usage() {
    echo -e "-b {git branch name} - для запуска процедуры git pull определённой ветки"
    echo -e "-s {минимальный процент для вывода сообщения} - проверить свободное место"
    echo -e "-h - вывести это сообщение"
}

## Проверка на первый запуск скрипта 
if load_config; then
    
    ## Проверяем, всего ли хватает
    check_config

    ## Если запустили с флагами
    while getopts "hb:s:" flag
    do
        case "$flag" in
            b) branch=${OPTARG}; git_pull "$branch"; exit;;
            s) free_limit=${OPTARG}; clear; check_size "$free_limit"; exit;;
            \?|h) usage; exit;;
        esac
    done

    ## Обычное или ограниченное меню
    if is_root; then
        menu
    else
        menu_bitrix
    fi
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
