#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
MAGENTA="\033[0;35m"
DIM="\033[2m"
BOLD="\033[1m"
NC="\033[0m"

XCODE="${XCODE:-$HOME/Library/Developer/Xcode}"
CLAUDE="${CLAUDE:-$HOME/Library/Application Support/Claude/vm_bundles}"
DEFAULT_SCAN_ROOT="${DEFAULT_SCAN_ROOT:-}"

function line() {
    printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '─'
}

function subtle_line() {
    printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '·'
}

function header() {
    clear 2>/dev/null || true
    echo -e "${BOLD}${BLUE}"
    echo "🧰 Developer Cleanup Utility"
    echo -e "${NC}"
    line
    echo -e "${DIM}Scan root: $(suggested_scan_root)${NC}"
    echo
}

function pause() {
    echo
    read -r -p "Нажмите Enter..."
}

function confirm() {
    local ans
    read -r -p "$1 (y/N): " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

function status_ok() {
    echo -e "${GREEN}✔ $1${NC}"
}

function status_warn() {
    echo -e "${YELLOW}• $1${NC}"
}

function status_info() {
    echo -e "${CYAN}• $1${NC}"
}

function section() {
    echo
    echo -e "${BOLD}${MAGENTA}$1${NC}"
    subtle_line
}

function compact_path() {
    local path="$1"
    if [[ "$path" == "$HOME"* ]]; then
        path="~${path#$HOME}"
    fi
    echo "$path"
}

function menu_item() {
    local number="$1"
    local title="$2"
    local hint="$3"

    printf "  ${BOLD}%2s${NC}  %-34s ${DIM}%s${NC}\n" "$number" "$title" "$hint"
}

function wait_with_spinner() {
    local pid="$1"
    local message="$2"
    local frames=("|" "/" "-" "\\")
    local i=0

    if [ ! -t 1 ]; then
        echo "$message..."
        set +e
        wait "$pid"
        local status=$?
        set -e
        return "$status"
    fi

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}%s${NC} %s" "${frames[$((i % 4))]}" "$message"
        i=$((i + 1))
        sleep 0.12
    done

    set +e
    wait "$pid"
    local status=$?
    set -e

    if [ "$status" -eq 0 ]; then
        printf "\r${GREEN}✔${NC} %s\n" "$message"
    else
        printf "\r${RED}✖${NC} %s\n" "$message"
    fi

    return "$status"
}

function progress_bar() {
    local current="$1"
    local total="$2"
    local label="$3"
    local width=28
    local percent=100
    local filled=0
    local empty=0
    local bar=""

    if [ "$total" -gt 0 ]; then
        percent=$((current * 100 / total))
        filled=$((current * width / total))
    fi

    empty=$((width - filled))

    for ((i = 0; i < filled; i++)); do
        bar="${bar}█"
    done

    for ((i = 0; i < empty; i++)); do
        bar="${bar}░"
    done

    printf "\r${CYAN}[%s]${NC} %3d%%  %s" "$bar" "$percent" "$label"

    if [ "$current" -ge "$total" ]; then
        printf "\n"
    fi
}

function human_kb() {
    awk -v kb="$1" 'BEGIN {
        if (kb >= 1048576) {
            printf "%.1fG", kb / 1048576
        } else if (kb >= 1024) {
            printf "%.1fM", kb / 1024
        } else {
            printf "%dK", kb
        }
    }'
}

function total_size_from_list() {
    local list="$1"
    local total_kb=0
    local path
    local kb

    while IFS= read -r path; do
        kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}' || echo 0)"
        total_kb=$((total_kb + kb))
    done < "$list"

    human_kb "$total_kb"
}

function size() {
    if [ -e "$1" ]; then
        du -sh "$1"
    else
        echo "0B    $1"
    fi
}

function ensure_dir() {
    if [ ! -d "$1" ]; then
        echo -e "${YELLOW}Папка не найдена:${NC} $1"
        return 1
    fi
}

function clean_dir_contents() {
    local dir="$1"
    local tmp
    local total
    local current=0
    local item

    if [ ! -d "$dir" ]; then
        echo -e "${YELLOW}Папка не найдена, пропускаю:${NC} $dir"
        return
    fi

    tmp="$(mktemp)"
    find "$dir" -mindepth 1 -maxdepth 1 -print > "$tmp"
    total="$(wc -l < "$tmp" | tr -d ' ')"

    if [ "$total" -eq 0 ]; then
        rm -f "$tmp"
        status_warn "Папка уже пустая."
        return
    fi

    while IFS= read -r item; do
        rm -rf "$item"
        current=$((current + 1))
        progress_bar "$current" "$total" "Удаление: $current/$total"
    done < "$tmp"

    rm -f "$tmp"
}

function suggested_scan_root() {
    if [ -n "$DEFAULT_SCAN_ROOT" ]; then
        echo "$DEFAULT_SCAN_ROOT"
    elif [ -d "$HOME/Code" ]; then
        echo "$HOME/Code"
    else
        echo "$HOME"
    fi
}

function expand_path() {
    local path="$1"
    path="${path/#\~/$HOME}"
    echo "$path"
}

function ask_scan_root() {
    local prompt="$1"
    local default_root
    local target

    default_root="$(suggested_scan_root)"
    read -r -e -p "$prompt [$default_root]: " target
    target="${target:-$default_root}"
    expand_path "$target"
}

function find_xcode_project_bundles() {
    local root="$1"

    find "$root" \
        \( -path "$HOME/Library" -o -path "$HOME/.Trash" -o -name ".git" -o -name "Pods" -o -name "node_modules" -o -name ".gradle" -o -name "DerivedData" -o -name ".derivedData" -o -name "build" \) -prune \
        -o -type d \( -name "*.xcodeproj" -o -name "*.xcworkspace" \) -print 2>/dev/null
}

function find_xcode_projects() {
    local root
    local tmp
    local count

    echo
    root="$(ask_scan_root "Где искать Xcode-проекты")"

    if ! ensure_dir "$root"; then
        return
    fi

    echo
    echo -e "${BOLD}Xcode-проекты и workspace:${NC}"
    echo -e "${YELLOW}Library, .git, Pods, build, DerivedData и node_modules пропускаются.${NC}"
    echo

    tmp="$(mktemp)"
    { find_xcode_project_bundles "$root" | sort > "$tmp"; } &
    wait_with_spinner "$!" "Сканирую проекты"

    count="$(wc -l < "$tmp" | tr -d ' ')"
    if [ "$count" -eq 0 ]; then
        echo "Ничего не найдено."
    else
        status_ok "Найдено: $count"
        cat "$tmp"
    fi

    rm -f "$tmp"
}

function clean_project_derived() {
    local root
    local tmp
    local count
    local total_size
    local current=0
    local path

    echo
    root="$(ask_scan_root "Где искать локальные .derivedData")"

    if ! ensure_dir "$root"; then
        return
    fi

    tmp="$(mktemp)"
    { find "$root" -type d -name ".derivedData" -prune -print 2>/dev/null | sort > "$tmp"; } &
    wait_with_spinner "$!" "Ищу локальные .derivedData"

    count="$(wc -l < "$tmp" | tr -d ' ')"
    if [ "$count" -eq 0 ]; then
        rm -f "$tmp"
        status_warn "Локальные .derivedData не найдены."
        return
    fi

    total_size="$(total_size_from_list "$tmp")"

    status_ok "Найдено: $count"
    if [ -n "$total_size" ]; then
        status_info "Примерный объем: $total_size"
    fi
    echo

    while IFS= read -r path; do
        du -sh "$path" 2>/dev/null || true
    done < "$tmp"
    echo

    if confirm "Удалить все найденные .derivedData?"; then
        while IFS= read -r path; do
            rm -rf "$path"
            current=$((current + 1))
            progress_bar "$current" "$count" "Удаление .derivedData: $current/$count"
        done < "$tmp"
        status_ok "Готово"
    else
        status_warn "Удаление отменено."
    fi

    rm -f "$tmp"
}

function clean_global_derived() {
    echo
    size "$XCODE/DerivedData"

    if confirm "Очистить глобальный DerivedData?"; then
        clean_dir_contents "$XCODE/DerivedData"
        echo -e "${GREEN}✔ Готово${NC}"
    fi
}

function clean_device_support() {
    echo
    size "$XCODE/iOS DeviceSupport"

    if confirm "Удалить DeviceSupport?"; then
        clean_dir_contents "$XCODE/iOS DeviceSupport"
        echo -e "${GREEN}✔ Готово${NC}"
    fi
}

function clean_archives() {
    echo
    size "$XCODE/Archives"

    if confirm "Удалить Xcode Archives?"; then
        clean_dir_contents "$XCODE/Archives"
        echo -e "${GREEN}✔ Готово${NC}"
    fi
}

function clean_simulators() {
    echo

    if confirm "Удалить unavailable Simulator Runtime?"; then
        { xcrun simctl delete unavailable >/dev/null; } &
        wait_with_spinner "$!" "Удаляю unavailable simulators"
        status_ok "Готово"
    fi
}

function docker_cleanup() {
    if ! command -v docker >/dev/null; then
        echo "Docker не установлен."
        return
    fi

    docker system df
    echo

    if confirm "Docker prune -a --volumes?"; then
        { docker system prune -a --volumes -f; } &
        wait_with_spinner "$!" "Docker prune выполняется"
    fi
}

function claude_cleanup() {
    echo
    size "$CLAUDE"

    if confirm "Удалить Claude VM Bundles?"; then
        clean_dir_contents "$CLAUDE"
        echo -e "${GREEN}✔ Готово${NC}"
    fi
}

function top_large_dirs() {
    local target

    echo
    target="$(ask_scan_root "Путь к проекту или папке")"

    if ! ensure_dir "$target"; then
        return
    fi

    echo
    echo -e "${BOLD}Top 20 самых больших вложенных папок:${NC}"
    echo -e "${YELLOW}Сканирование может занять время на больших проектах.${NC}"
    echo

    local all_tmp
    local tech_tmp
    all_tmp="$(mktemp)"
    tech_tmp="$(mktemp)"

    {
        find "$target" \
        \( -name ".git" -o -name "Pods" -o -name ".derivedData" -o -name "build" -o -name "DerivedData" -o -name "node_modules" -o -name ".gradle" \) \
        -prune \
        -exec du -sh {} + \
        -o -type d \
        ! -path "$target" \
        -exec du -sh {} + 2>/dev/null \
        | sort -hr \
        | head -n 20 > "$all_tmp"
    } &
    wait_with_spinner "$!" "Считаю размеры вложенных папок"
    cat "$all_tmp"

    echo
    echo -e "${BOLD}Top 20 технических папок:${NC}"
    {
        find "$target" \
        -type d \
        \( -name ".git" -o -name "Pods" -o -name ".derivedData" -o -name "build" -o -name "DerivedData" -o -name "node_modules" -o -name ".gradle" \) \
        -prune \
        -exec du -sh {} + 2>/dev/null \
        | sort -hr \
        | head -n 20 > "$tech_tmp"
    } &
    wait_with_spinner "$!" "Считаю размеры технических папок"
    cat "$tech_tmp"

    echo
    echo -e "${BOLD}Top 20 папок первого уровня:${NC}"
    du -sh "$target"/* 2>/dev/null | sort -hr | head -n 20 || true

    rm -f "$all_tmp" "$tech_tmp"
}

function show_sizes() {
    local root
    local tmp

    line
    echo -e "${BOLD}Xcode DerivedData:${NC}"
    size "$XCODE/DerivedData"
    echo
    echo -e "${BOLD}iOS DeviceSupport:${NC}"
    size "$XCODE/iOS DeviceSupport"
    echo
    echo -e "${BOLD}Xcode Archives:${NC}"
    size "$XCODE/Archives"
    echo
    echo -e "${BOLD}Claude VM Bundles:${NC}"
    size "$CLAUDE"
    echo
    root="$(ask_scan_root "Где искать локальные .derivedData для отчета")"
    echo
    echo -e "${BOLD}Локальные .derivedData:${NC}"

    if ensure_dir "$root"; then
        tmp="$(mktemp)"
        { find "$root" -type d -name ".derivedData" -prune -print 2>/dev/null | sort > "$tmp"; } &
        wait_with_spinner "$!" "Ищу локальные .derivedData"
        if [ -s "$tmp" ]; then
            while IFS= read -r path; do
                du -sh "$path" 2>/dev/null || true
            done < "$tmp"
        else
            echo "Ничего не найдено."
        fi
        rm -f "$tmp"
    fi

    echo
    echo "Свободное место:"
    df -h /
}

while true
do
    header
    section "Overview"
    menu_item "1" "Показать размеры" "Xcode, Claude, локальные кэши"
    menu_item "2" "Top 20 больших папок" "поиск тяжелых директорий"

    section "Xcode / iOS"
    menu_item "3" "Найти проекты и workspace" ".xcodeproj / .xcworkspace"
    menu_item "4" "Очистить локальные .derivedData" "в выбранной папке"
    menu_item "5" "Очистить глобальный DerivedData" "$(compact_path "$XCODE/DerivedData")"
    menu_item "6" "Очистить iOS DeviceSupport" "старые device symbols"
    menu_item "7" "Очистить Archives" "локальные Xcode archives"
    menu_item "8" "Удалить unavailable Simulators" "xcrun simctl delete unavailable"

    section "Developer Tools"
    menu_item "9" "Docker system prune" "images, cache, volumes"
    menu_item "10" "Claude VM Bundles cleanup" "локальные VM bundles"

    section "Batch"
    menu_item "11" "🚀 Полная очистка Xcode/iOS" "пункты 4-8 с подтверждениями"
    menu_item "0" "Выход" "закрыть утилиту"
    echo

    read -r -p "$(echo -e "${BOLD}Выберите пункт:${NC} ")" choice

    case "$choice" in
        1)
            show_sizes
            pause
            ;;
        2)
            top_large_dirs
            pause
            ;;
        3)
            find_xcode_projects
            pause
            ;;
        4)
            clean_project_derived
            pause
            ;;
        5)
            clean_global_derived
            pause
            ;;
        6)
            clean_device_support
            pause
            ;;
        7)
            clean_archives
            pause
            ;;
        8)
            clean_simulators
            pause
            ;;
        9)
            docker_cleanup
            pause
            ;;
        10)
            claude_cleanup
            pause
            ;;
        11)
            clean_project_derived
            clean_global_derived
            clean_device_support
            clean_archives
            clean_simulators
            echo
            echo -e "${GREEN}Полная очистка завершена${NC}"
            df -h /
            pause
            ;;
        0)
            exit
            ;;
        *)
            ;;
    esac
done
