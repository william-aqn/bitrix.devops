#!/bin/bash

## Проверено на bitrixenv 7.5.2
version=1.0

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

## Устанавливаем битрикс окружение
install_bitrixenv() {
    echo "Bitrixenv не обнаружен, устанавливаем..."
    yum clean all && yum -y update
    yum install -y wget
    wget -O bitrix-env.sh https://repo.bitrix.info/yum/bitrix-env.sh && chmod +x bitrix-env.sh && ./bitrix-env.sh
    exit
}

## Запустить bitrixenv
start_bitrixenv() {
    exec /root/menu.sh
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

check_size() {
    local used=$( df -h / --output=pcent | awk 'END{ print $(NF-1) }' | tr -d '%' )
    local free=$((100 - used))
    if [[ free -lt $1 ]]; then
        echo -e "Мало свободного места - $free%"
    fi
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

## Хелпер гита для авторизации
git_get_credential_helper() {
    printf -v HELPER "!f() { cat >/dev/null; echo 'username=%s'; echo 'password=%s'; }; f" "$git_user" "$git_pass"
}

## Вернёт errlvl 0 - если гит доступен 
git_remote_url_reachable() {
    git_get_credential_helper
    git -c credential.helper="$HELPER" ls-remote "$1" CHECK_GIT_REMOTE_URL_REACHABILITY >/dev/null 2>&1
}



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


## Сохраняем конфиг
save_config() {
    {
        printf 'git_url=%s\n' "${git_url}";
        printf 'git_user=%s\n' "${git_user}";
        printf 'git_pass=%s\n' "${git_pass}";
        printf 'git_branch_master_name=%s\n' "${git_branch_master_name}";
        printf 'git_pull_master_allow=%s\n' "${git_pull_master_allow}";
        printf 'bitrix_home_dir=%s\n' "${bitrix_home_dir}";
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

    ## Сохраняем настройки
    save_config

    ## Устанавливаем себя глобально
    install_self

    ## Запускаем основное меню
    menu
}

## Ручной ввод ветки
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
    for dir in $(find $bitrix_home_dir -maxdepth 3 -type d -name ".git")
        do cd "${dir%/*}" || exit
            current_branch_name=$(git symbolic-ref --short -q HEAD)
            echo -e "Директория: $PWD; Ветка: $current_branch_name;"
            cd - > /dev/null || exit
        done
    cd "$HOME" || exit
}


## Запуск процедуры git pull
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

                #git fetch 
                git reset --hard
                git -c credential.helper="$HELPER" pull
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

## Инициализация репозитория
git_init() {
    git_new_dir=""
    git_new_branch=""
    git_new_dir_override=""
    git_new_branch_create=""
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
    wait
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

# Меню не root пользователя
menu_bitrix() {
    until [[ "$TARGET_SELECTION" == "0" ]]; do
        header

        echo -e "\t\t1. git pull (существующей ветки)"
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

        echo -e "\t\t1. git pull (существующей ветки)"
        echo -e "\t\t3. git init (задать директорию)"
        echo -e "\t\t10. Переустановить конфигурацию репозитория"
        echo -e "\t\t11. Обновить скрипт из гита"
        echo -e "\t\t12. Установить текущий скрипт"
        echo -e "\t\t20. Запустить bitrixenv"
        echo -e "\t\t0. Выход"

        IFS= read -p "Пункт меню: " -r TARGET_SELECTION
        case "$TARGET_SELECTION" in 
            "1"|pull)  git_pull_one;;
            "3"|init)  git_init;;
            "10"|clear) clear_config; first_run;;
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
    ## Проверим свободное место
    check_size 10
    ## Сразу проверим ip
    check_ip
    ## Информация о репозитории
    echo -e "Репозиторий: $git_url"
    git_list
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
