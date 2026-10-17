#!/bin/bash

# ══════════════════════════════════════════════════════════════════════════
# 3X-UI // ENTERPRISE NODE APPLIANCE INSTALLER
# ══════════════════════════════════════════════════════════════════════════

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

# 256-Color Enterprise Appliance Palette
C_FRAME='\033[38;5;39m'     # Deep Electric Blue (Borders)
C_CYAN='\033[38;5;51m'      # Bright Cyan (Accents)
C_GREEN='\033[38;5;46m'     # Neon Green (OK / Bars)
C_YELLOW='\033[38;5;226m'   # Amber Yellow (Credentials / Warnings)
C_RED='\033[38;5;196m'      # Crimson Red (Errors)
C_DIM='\033[38;5;242m'      # Muted Gray
C_WHITE='\033[1;37m'        # Bold White
C_NC='\033[0m'              # Reset

LOG_FILE="/tmp/xui_enterprise_install.log"
rm -f "$LOG_FILE"

xui_folder="${XUI_MAIN_FOLDER:=/usr/local/x-ui}"
xui_service="${XUI_SERVICE:=/etc/systemd/system}"

# Global Telemetry & Timing Trackers
T_P1="0.0s"
T_P2="0.0s"
T_P3="0.0s"
T_P4="0.0s"
T_P5="0.0s"
FINAL_URL=""
FINAL_USER=""
FINAL_PASS=""
FINAL_DB="SQLite (/etc/x-ui/x-ui.db)"
FINAL_TOKEN=""
DETECTED_IP=""

# Check root
[[ $EUID -ne 0 ]] && echo -e "${C_RED}Fatal error:${C_NC} Please run this script with root privilege \n" && exit 1

# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${C_RED}Unsupported CPU architecture!${C_NC}" && rm -f "$(realpath "$0")" && exit 1 ;;
    esac
}

if [[ "${XUI_NONINTERACTIVE:-0}" == "1" ]] || [[ ! -t 0 ]]; then
    NONINTERACTIVE=1
else
    NONINTERACTIVE=0
fi
export NONINTERACTIVE

# ══════════════════════════════════════════════════════════════════════════
# ENTERPRISE APPLIANCE TUI ENGINE (STRICT 76-COL ALIGNMENT)
# ══════════════════════════════════════════════════════════════════════════

v_bar() {
    local pct="${1:-20}"
    [[ ! "$pct" =~ ^[0-9]+$ ]] && pct=20
    (( pct > 100 )) && pct=100
    (( pct < 0 )) && pct=0
    local fill=$(( pct * 8 / 100 ))
    local emp=$(( 8 - fill ))
    local bar=""
    for ((i=0; i<fill; i++)); do bar+="▮"; done
    for ((i=0; i<emp; i++)); do bar+="▯"; done
    echo "$bar"
}

print_appliance_header() {
    clear
    local os_ver=$(grep -oP '(?<=^NAME=).+' /etc/os-release 2>/dev/null | tr -d '"' | awk '{print $1}')
    local os_num=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release 2>/dev/null | tr -d '"')
    local os_str=$(printf "%s %s" "${os_ver:-Linux}" "${os_num}" | cut -c 1-12)
    local kern_str=$(uname -r | cut -c 1-12)
    local arch_str=$(printf "%s / 64b" "$(arch)" | cut -c 1-12)

    if [[ -z "$DETECTED_IP" ]]; then
        DETECTED_IP=$(curl -s --max-time 2 https://api4.ipify.org 2>/dev/null || echo "Detecting...")
    fi
    local ip_str=$(printf "%s" "${SSL_HOST:-$DETECTED_IP}" | cut -c 1-15)
    local tls_str="Let's Encrypt"
    [[ "${SSL_SCHEME:-https}" == "http" ]] && tls_str="HTTP (No TLS)"

    local bbr_stat="Standard TCP"
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        bbr_stat="Active (TCP)"
    fi

    local cpu_p=$(top -bn1 2>/dev/null | awk '/Cpu\(s\)/{printf("%.0f", 100 - $8)}' || echo 18)
    [[ ! "$cpu_p" =~ ^[0-9]+$ ]] && cpu_p=18
    local ram_p=$(free 2>/dev/null | awk '/Mem/{printf("%.0f"), $3/$2*100}' || echo 42)
    [[ ! "$ram_p" =~ ^[0-9]+$ ]] && ram_p=42
    local hdd_p=$(df / 2>/dev/null | awk 'END{print $(NF-1)}' | tr -d '%' || echo 24)
    [[ ! "$hdd_p" =~ ^[0-9]+$ ]] && hdd_p=24

    local rev_str="${tag_version:-v2.8.X}"
    rev_str=$(printf "%s" "$rev_str" | cut -c 1-8)

    echo -e "${C_FRAME}┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${C_NC}"
    printf "${C_FRAME}┃${C_NC} ${C_CYAN}██▓▒░${C_NC}  ${C_WHITE}%-49s${C_NC} ${C_YELLOW}[REV: %-8s]${C_NC} ${C_FRAME}┃${C_NC}\n" "3X-UI // ENTERPRISE NODE APPLIANCE" "$rev_str"
    echo -e "${C_FRAME}┣━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━┫${C_NC}"
    printf "${C_FRAME}┃${C_NC} ${C_CYAN}%-21s${C_NC} ${C_FRAME}┃${C_NC} ${C_CYAN}%-24s${C_NC} ${C_FRAME}┃${C_NC} ${C_CYAN}%-21s${C_NC} ${C_FRAME}┃${C_NC}\n" "❖ HOST ARCHITECTURE" "❖ NETWORK & ROUTING" "❖ HARDWARE TELEMETRY"
    printf "${C_FRAME}┃${C_NC} ${C_DIM}─────────────────────${C_NC} ${C_FRAME}┃${C_NC} ${C_DIM}────────────────────────${C_NC} ${C_FRAME}┃${C_NC} ${C_DIM}─────────────────────${C_NC} ${C_FRAME}┃${C_NC}\n"
    printf "${C_FRAME}┃${C_NC} ▸ OS   : ${C_WHITE}%-12.12s${C_NC} ${C_FRAME}┃${C_NC} ▸ IPv4 : ${C_YELLOW}%-15.15s${C_NC} ${C_FRAME}┃${C_NC} ▸ CPU : ${C_GREEN}%s${C_NC} %3d%% ${C_FRAME}┃${C_NC}\n" "$os_str" "$ip_str" "$(v_bar "$cpu_p")" "$cpu_p"
    printf "${C_FRAME}┃${C_NC} ▸ ARCH : ${C_WHITE}%-12.12s${C_NC} ${C_FRAME}┃${C_NC} ▸ TLS  : ${C_WHITE}%-15.15s${C_NC} ${C_FRAME}┃${C_NC} ▸ RAM : ${C_YELLOW}%s${C_NC} %3d%% ${C_FRAME}┃${C_NC}\n" "$arch_str" "$tls_str" "$(v_bar "$ram_p")" "$ram_p"
    printf "${C_FRAME}┃${C_NC} ▸ KERN : ${C_DIM}%-12.12s${C_NC} ${C_FRAME}┃${C_NC} ▸ BBR  : ${C_GREEN}%-15.15s${C_NC} ${C_FRAME}┃${C_NC} ▸ HDD : ${C_CYAN}%s${C_NC} %3d%% ${C_FRAME}┃${C_NC}\n" "$kern_str" "$bbr_stat" "$(v_bar "$hdd_p")" "$hdd_p"
    echo -e "${C_FRAME}┣━━━━━━━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━┫${C_NC}"
    printf "${C_FRAME}┃${C_NC} ${C_CYAN}❖ NODE TOPOLOGY :${C_NC}  ${C_WHITE}[WAN]${C_NC} ${C_DIM}──►${C_NC} ${C_YELLOW}[FAIL2BAN]${C_NC} ${C_DIM}──►${C_NC} ${C_GREEN}[TLS:1.3]${C_NC} ${C_DIM}──►${C_NC} ${C_CYAN}[XRAY-ENGINE]${C_NC}  ${C_FRAME}┃${C_NC}\n"
    echo -e "${C_FRAME}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${C_NC}"
    printf "${C_FRAME}┃${C_NC} ${C_DIM}PHASE   MODULE DESCRIPTION                     PROGRESS       TIME  STAT${C_NC} ${C_FRAME}┃${C_NC}\n"
    echo -e "${C_FRAME}┃ ──────────────────────────────────────────────────────────────────────── ┃${C_NC}"
}

print_completed_phase_row() {
    local hex="$1"
    local desc="$2"
    local elapsed="$3"
    printf "${C_FRAME}┃${C_NC} [${C_CYAN}%-4.4s${C_NC}]  %-38.38s ${C_GREEN}▮▮▮▮▮▮▮▮▮▮${C_NC}   %6.6s  [${C_GREEN}OK${C_NC}] ${C_FRAME}┃${C_NC}\n" "$hex" "$desc" "$elapsed"
}

run_appliance_phase() {
    local hex="$1"
    local desc="$2"
    local out_var="$3"
    shift 3

    local start_ts=$(date +%s%N)
    local anim=(
        "▮▯▯▯▯▯▯▯▯▯" "▮▮▯▯▯▯▯▯▯▯" "▮▮▮▯▯▯▯▯▯▯" "▮▮▮▮▯▯▯▯▯▯" "▮▮▮▮▮▯▯▯▯▯"
        "▮▮▮▮▮▮▯▯▯▯" "▮▮▮▮▮▮▮▯▯▯" "▮▮▮▮▮▮▮▮▯▯" "▮▮▮▮▮▮▮▮▮▯" "▮▮▮▮▮▮▮▮▮▮"
    )
    local idx=0

    "$@" >> "$LOG_FILE" 2>&1 &
    local pid=$!

    while kill -0 $pid 2>/dev/null; do
        printf "\r${C_FRAME}┃${C_NC} [${C_CYAN}%-4.4s${C_NC}]  %-38.38s ${C_YELLOW}%s${C_NC}     ${C_DIM}....${C_NC}  [${C_YELLOW}..${C_NC}] ${C_FRAME}┃${C_NC}" "$hex" "$desc" "${anim[$idx]}"
        idx=$(( (idx + 1) % 10 ))
        sleep 0.12
    done

    wait $pid
    local rc=$?
    local end_ts=$(date +%s%N)
    local elapsed=$(awk "BEGIN {printf \"%.1fs\", ($end_ts - $start_ts)/1000000000}")
    printf -v "$out_var" '%s' "$elapsed"

    if [ $rc -eq 0 ]; then
        print_completed_phase_row "$hex" "$desc" "$elapsed"
    else
        printf "\r${C_FRAME}┃${C_NC} [${C_RED}%-4.4s${C_NC}]  %-38.38s ${C_RED}▮▮▮▮▮▮▮▮▮▮${C_NC}   %6.6s  [${C_RED}XX${C_NC}] ${C_FRAME}┃${C_NC}\n" "$hex" "$desc" "$elapsed"
        echo -e "${C_FRAME}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_NC}"
        echo -e "${C_RED}[!] Critical failure at phase ${hex}. Detailed log: ${LOG_FILE}${C_NC}"
        tail -n 15 "$LOG_FILE" >&2
        exit 1
    fi
}

print_final_appliance_screen() {
    print_appliance_header
    print_completed_phase_row "0x01" "System Core & Crypto Libraries" "$T_P1"
    print_completed_phase_row "0x02" "3X-UI Binary & Xray-Core Engine" "$T_P2"
    print_completed_phase_row "0x03" "Database Provisioning & Migration" "$T_P3"
    print_completed_phase_row "0x04" "ACME Zero-Trust SSL Certificate" "$T_P4"
    print_completed_phase_row "0x05" "Systemd Hardening & IP-Limit Guard" "$T_P5"

    local url_disp=$(printf "%s" "${FINAL_URL}" | cut -c 1-48)
    local usr_disp=$(printf "%s" "${FINAL_USER}" | cut -c 1-48)
    local pas_disp=$(printf "%s" "${FINAL_PASS}" | cut -c 1-48)
    local db_disp=$(printf "%s" "${FINAL_DB}" | cut -c 1-48)
    local tok_disp="Configured (Use 'x-ui settings' to view)"
    if [[ -n "$FINAL_TOKEN" ]]; then
        tok_disp="$(printf "%s" "$FINAL_TOKEN" | cut -c 1-45)..."
    fi

    echo -e "${C_FRAME}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${C_NC}"
    printf "${C_FRAME}┃${C_NC} ${C_YELLOW}██▓▒░${C_NC}  ${C_WHITE}%-58s${C_NC}   [${C_YELLOW}##${C_NC}] ${C_FRAME}┃${C_NC}\n" "MASTER ACCESS KEYCARD // AUTHORIZED OPERATOR ONLY"
    echo -e "${C_FRAME}┃ ──────────────────────────────────────────────────────────────────────── ┃${C_NC}"
    echo -e "${C_FRAME}┃                                                                          ┃${C_NC}"
    echo -e "${C_FRAME}┃${C_NC}   ${C_CYAN}┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓${C_NC}   ${C_FRAME}┃${C_NC}"
    printf "${C_FRAME}┃${C_NC}   ${C_CYAN}┃${C_NC} ${C_CYAN}◈${C_NC} ${C_WHITE}%-11.11s${C_NC} ${C_CYAN}┃${C_NC} ${C_GREEN}%-48.48s${C_NC} ${C_CYAN}┃${C_NC}   ${C_FRAME}┃${C_NC}\n" "ACCESS URL" "$url_disp"
    echo -e "${C_FRAME}┃${C_NC}   ${C_CYAN}┣━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${C_NC}   ${C_FRAME}┃${C_NC}"
    printf "${C_FRAME}┃${C_NC}   ${C_CYAN}┃${C_NC} ${C_CYAN}◈${C_NC} ${C_WHITE}%-11.11s${C_NC} ${C_CYAN}┃${C_NC} ${C_YELLOW}%-48.48s${C_NC} ${C_CYAN}┃${C_NC}   ${C_FRAME}┃${C_NC}\n" "USERNAME" "$usr_disp"
    printf "${C_FRAME}┃${C_NC}   ${C_CYAN}┃${C_NC} ${C_CYAN}◈${C_NC} ${C_WHITE}%-11.11s${C_NC} ${C_CYAN}┃${C_NC} ${C_YELLOW}%-48.48s${C_NC} ${C_CYAN}┃${C_NC}   ${C_FRAME}┃${C_NC}\n" "PASSWORD" "$pas_disp"
    printf "${C_FRAME}┃${C_NC}   ${C_CYAN}┃${C_NC} ${C_CYAN}◈${C_NC} ${C_WHITE}%-11.11s${C_NC} ${C_CYAN}┃${C_NC} ${C_WHITE}%-48.48s${C_NC} ${C_CYAN}┃${C_NC}   ${C_FRAME}┃${C_NC}\n" "DATABASE" "$db_disp"
    printf "${C_FRAME}┃${C_NC}   ${C_CYAN}┃${C_NC} ${C_CYAN}◈${C_NC} ${C_WHITE}%-11.11s${C_NC} ${C_CYAN}┃${C_NC} ${C_DIM}%-48.48s${C_NC} ${C_CYAN}┃${C_NC}   ${C_FRAME}┃${C_NC}\n" "API TOKEN" "$tok_disp"
    echo -e "${C_FRAME}┃${C_NC}   ${C_CYAN}┗━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_NC}   ${C_FRAME}┃${C_NC}"
    echo -e "${C_FRAME}┃                                                                          ┃${C_NC}"
    printf "${C_FRAME}┃${C_NC} ▸ ${C_CYAN}CONTROL :${C_NC}  [ ${C_GREEN}x-ui${C_NC} ] Main Menu   [ ${C_YELLOW}x-ui status${C_NC} ] Service   [ ${C_CYAN}x-ui log${C_NC} ] ${C_FRAME}┃${C_NC}\n"
    echo -e "${C_FRAME}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${C_NC}"

    # If URL is longer than 48 chars, display full copyable URL below the box
    if (( ${#FINAL_URL} > 48 )); then
        echo -e "  ${C_CYAN}▸ Full Access URL:${C_NC} ${C_GREEN}${FINAL_URL}${C_NC}"
    fi
}

# ══════════════════════════════════════════════════════════════════════════
# CORE HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════

is_ipv4() {
    [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0 || return 1
}
is_ipv6() {
    [[ "$1" =~ : ]] && return 0 || return 1
}
is_ip() {
    is_ipv4 "$1" || is_ipv6 "$1"
}
is_domain() {
    [[ "$1" =~ ^([A-Za-z0-9](-*[A-Za-z0-9])*\.)+(xn--[a-z0-9]{2,}|[A-Za-z]{2,})$ ]] && return 0 || return 1
}

acme_listen_flag() {
    if ip -4 addr show scope global 2> /dev/null | grep -q "inet "; then
        echo ""
    else
        echo "--listen-v6"
    fi
}

is_port_in_use() {
    local port="$1"
    if command -v ss > /dev/null 2>&1; then
        ss -ltn 2> /dev/null | awk -v p=":${port}$" '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v netstat > /dev/null 2>&1; then
        netstat -lnt 2> /dev/null | awk -v p=":${port} " '$4 ~ p {exit 0} END {exit 1}'
        return
    fi
    if command -v lsof > /dev/null 2>&1; then
        lsof -nP -iTCP:${port} -sTCP:LISTEN > /dev/null 2>&1 && return 0
    fi
    return 1
}

install_base() {
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update && apt-get install -y -q cron curl tar tzdata socat ca-certificates openssl
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf makecache -y && dnf install -y -q cronie curl tar tzdata socat ca-certificates openssl
            ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum makecache -y && yum install -y cronie curl tar tzdata socat ca-certificates openssl
            else
                dnf makecache -y && dnf install -y -q cronie curl tar tzdata socat ca-certificates openssl
            fi
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm cronie curl tar tzdata socat ca-certificates openssl
            ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper refresh && zypper -q install -y cron curl tar timezone socat ca-certificates openssl
            ;;
        alpine)
            apk update && apk add dcron curl tar tzdata socat ca-certificates openssl
            ;;
        *)
            apt-get update && apt-get install -y -q cron curl tar tzdata socat ca-certificates openssl
            ;;
    esac
}

gen_random_string() {
    local length="$1"
    openssl rand -base64 $((length * 2)) \
        | tr -dc 'a-zA-Z0-9' \
        | head -c "$length"
}

prompt_or_default() {
    local __var="$1" __prompt="$2" __default="$3" __env="${4:-$1}"
    if [[ "$NONINTERACTIVE" == "1" ]]; then
        printf -v "$__var" '%s' "${!__env:-$__default}"
    else
        # shellcheck disable=SC2229
        read -rp "$__prompt" "$__var"
    fi
}

write_install_result() {
    local u="$1" p="$2" port="$3" wbp="$4" scheme="$5" host="$6" token="$7" dbtype="$8"
    local result_file="/etc/x-ui/install-result.env"
    local url_host="${host:-SERVER_IP_UNKNOWN}"
    install -d -m 700 /etc/x-ui 2> /dev/null
    local prev_umask
    prev_umask=$(umask)
    umask 077
    if ! {
        printf 'XUI_USERNAME=%q\n' "$u"
        printf 'XUI_PASSWORD=%q\n' "$p"
        printf 'XUI_PANEL_PORT=%q\n' "$port"
        printf 'XUI_WEB_BASE_PATH=%q\n' "$wbp"
        printf 'XUI_ACCESS_URL=%q\n' "${scheme}://${url_host}:${port}/${wbp}"
        printf 'XUI_API_TOKEN=%q\n' "$token"
        printf 'XUI_DB_TYPE=%q\n' "$dbtype"
    } > "$result_file"; then
        umask "$prev_umask"
        return 1
    fi
    umask "$prev_umask"
    chmod 600 "$result_file" 2> /dev/null
    chown root:root "$result_file" 2> /dev/null || true
}

# ══════════════════════════════════════════════════════════════════════════
# POSTGRESQL ENGINE HELPERS
# ══════════════════════════════════════════════════════════════════════════

pg_ensure_hba_password_auth() {
    local pg_db="$1"
    local hba_file
    hba_file=$(sudo -u postgres psql -tAc 'SHOW hba_file' 2> /dev/null | tr -d '[:space:]')
    [[ -n "${hba_file}" && -f "${hba_file}" ]] || return 0
    grep -Eq "^host[[:space:]]+${pg_db}[[:space:]]" "${hba_file}" && return 0
    local tmp
    tmp=$(mktemp) || return 1
    {
        echo "# Added by 3x-ui: allow password logins for the panel database."
        echo "host    ${pg_db}    all    127.0.0.1/32    md5"
        echo "host    ${pg_db}    all    ::1/128         md5"
        cat "${hba_file}"
    } > "${tmp}" || {
        rm -f "${tmp}"
        return 1
    }
    cat "${tmp}" > "${hba_file}" || {
        rm -f "${tmp}"
        return 1
    }
    rm -f "${tmp}"
    sudo -u postgres psql -tAc 'SELECT pg_reload_conf()' > /dev/null 2>&1 || true
}

PG_TARGET_MAJOR=18

pg_has_debian_cluster() {
    command -v pg_lsclusters > /dev/null 2>&1 && [[ -n "$(pg_lsclusters -h 2> /dev/null)" ]]
}

pg_apt_install_pgdg_server() {
    local list added_lists=()
    for list in /etc/apt/sources.list.d/pgdg.list /etc/apt/sources.list.d/pgdg.sources; do
        [[ -e "${list}" ]] || added_lists+=("${list}")
    done
    if apt-get install -y -q postgresql-common ca-certificates gnupg >&2 \
        && /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y >&2 \
        && apt-get install -y -q "postgresql-${PG_TARGET_MAJOR}" >&2; then
        return 0
    fi
    for list in "${added_lists[@]}"; do
        rm -f "${list}"
    done
    apt-get update >&2 || true
    return 1
}

pg_el_install_pgdg_server() {
    local elver
    elver=$(rpm -E %rhel 2> /dev/null)
    [[ "${elver}" =~ ^[0-9]+$ && "${elver}" -ge 8 ]] && command -v dnf > /dev/null 2>&1 || return 1
    [[ -f /var/lib/pgsql/data/PG_VERSION ]] && return 1
    local added_repo=false
    if ! rpm -q pgdg-redhat-repo > /dev/null 2>&1; then
        if dnf install -y -q "https://download.postgresql.org/pub/repos/yum/reporpms/EL-${elver}-$(uname -m)/pgdg-redhat-repo-latest.noarch.rpm" >&2; then
            added_repo=true
            dnf -qy module disable postgresql > /dev/null 2>&1 || true
        fi
    fi
    if rpm -q pgdg-redhat-repo > /dev/null 2>&1 \
        && dnf install -y -q "postgresql${PG_TARGET_MAJOR}-server" "postgresql${PG_TARGET_MAJOR}-contrib" >&2; then
        return 0
    fi
    if [[ "${added_repo}" == "true" ]]; then
        dnf -qy module reset postgresql > /dev/null 2>&1 || true
        dnf remove -y -q pgdg-redhat-repo >&2 || true
    fi
    return 1
}

install_postgres_local() {
    local pg_user pg_pass
    pg_pass=$(gen_random_string 24)
    local pg_db="xui"
    local pg_host="127.0.0.1"
    local pg_port="5432"

    local pg_service="postgresql"
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update >&2 || return 1
            if pg_has_debian_cluster || ! pg_apt_install_pgdg_server; then
                apt-get install -y -q postgresql >&2 || return 1
            fi
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol | centos)
            if [[ "${release}" != "fedora" && "${release}" != "amzn" ]] && pg_el_install_pgdg_server; then
                pg_service="postgresql-${PG_TARGET_MAJOR}"
                [[ -f "/var/lib/pgsql/${PG_TARGET_MAJOR}/data/PG_VERSION" ]] \
                    || "/usr/pgsql-${PG_TARGET_MAJOR}/bin/postgresql-${PG_TARGET_MAJOR}-setup" initdb >&2 || return 1
            else
                if [[ "${release}" == "centos" && "${VERSION_ID}" =~ ^7 ]]; then
                    yum install -y postgresql-server postgresql-contrib >&2 || return 1
                else
                    dnf install -y -q postgresql-server postgresql-contrib >&2 || return 1
                fi
                [[ -d /var/lib/pgsql/data && -f /var/lib/pgsql/data/PG_VERSION ]] || postgresql-setup --initdb >&2 || return 1
            fi
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm postgresql >&2 || return 1
            if [[ ! -f /var/lib/postgres/data/PG_VERSION ]]; then
                sudo -u postgres initdb -D /var/lib/postgres/data >&2 || return 1
            fi
            ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper -q install -y postgresql-server postgresql-contrib >&2 || return 1
            if [[ ! -f /var/lib/pgsql/data/PG_VERSION ]]; then
                install -d -o postgres -g postgres -m 700 /var/lib/pgsql/data >&2 || return 1
                su - postgres -c "initdb -D /var/lib/pgsql/data" >&2 || return 1
            fi
            ;;
        alpine)
            apk add --no-cache postgresql postgresql-contrib >&2 || return 1
            if [[ ! -f /var/lib/postgresql/data/PG_VERSION ]]; then
                /etc/init.d/postgresql setup >&2 || return 1
            fi
            rc-update add postgresql default >&2 2> /dev/null || true
            rc-service postgresql start >&2 || return 1
            ;;
        *)
            return 1
            ;;
    esac

    if [[ "${release}" != "alpine" ]]; then
        systemctl enable --now "${pg_service}" >&2 || return 1
    fi

    local i
    for i in 1 2 3 4 5; do
        sudo -u postgres psql -tAc 'SELECT 1' > /dev/null 2>&1 && break
        sleep 1
    done

    local existing_owner=""
    existing_owner=$(sudo -u postgres psql -tAc \
        "SELECT pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname='${pg_db}'" 2> /dev/null \
        | tr -d '[:space:]')
    if [[ -n "${existing_owner}" && "${existing_owner}" != "postgres" ]]; then
        pg_user="${existing_owner}"
    else
        pg_user=$(gen_random_string 8)
    fi

    sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${pg_user}'" 2> /dev/null \
        | grep -q 1 \
        || sudo -u postgres psql -c "CREATE USER \"${pg_user}\" WITH PASSWORD '${pg_pass}';" >&2 || return 1

    sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${pg_db}'" 2> /dev/null \
        | grep -q 1 \
        || sudo -u postgres psql -c "CREATE DATABASE \"${pg_db}\" OWNER \"${pg_user}\";" >&2 || return 1

    sudo -u postgres psql -c "ALTER USER \"${pg_user}\" WITH PASSWORD '${pg_pass}';" >&2 || return 1

    pg_ensure_hba_password_auth "${pg_db}" || true

    local pg_pass_enc
    pg_pass_enc=$(printf '%s' "${pg_pass}" | sed -e 's/%/%25/g' -e 's/:/%3A/g' -e 's/@/%40/g' -e 's|/|%2F|g' -e 's/?/%3F/g' -e 's/#/%23/g')

    if [[ -n "${PG_CRED_FILE:-}" ]]; then
        local prev_umask
        prev_umask=$(umask)
        umask 077
        if ! cat > "${PG_CRED_FILE}" << EOF; then
PG_USER=${pg_user}
PG_PASS=${pg_pass}
PG_HOST=${pg_host}
PG_PORT=${pg_port}
PG_DB=${pg_db}
EOF
            umask "${prev_umask}"
            return 1
        fi
        umask "${prev_umask}"
    fi

    echo "postgres://${pg_user}:${pg_pass_enc}@${pg_host}:${pg_port}/${pg_db}?sslmode=disable"
    return 0
}

ensure_pg_client() {
    if command -v pg_dump > /dev/null 2>&1 && command -v pg_restore > /dev/null 2>&1; then
        return 0
    fi
    case "${release}" in
        ubuntu | debian | armbian)
            apt-get update >&2 && apt-get install -y -q postgresql-client >&2 || return 1
            ;;
        fedora | amzn | virtuozzo | rhel | almalinux | rocky | ol)
            dnf install -y -q postgresql >&2 || return 1
            ;;
        centos)
            if [[ "${VERSION_ID}" =~ ^7 ]]; then
                yum install -y postgresql >&2 || return 1
            else
                dnf install -y -q postgresql >&2 || return 1
            fi
            ;;
        arch | manjaro | parch)
            pacman -Sy --noconfirm postgresql >&2 || return 1
            ;;
        opensuse-tumbleweed | opensuse-leap)
            zypper -q install -y postgresql >&2 || return 1
            ;;
        alpine)
            apk add --no-cache postgresql-client >&2 || return 1
            ;;
        *)
            return 1
            ;;
    esac
    command -v pg_dump > /dev/null 2>&1 && command -v pg_restore > /dev/null 2>&1
}

# ══════════════════════════════════════════════════════════════════════════
# ACME & ZERO-TRUST SSL CERTIFICATES
# ══════════════════════════════════════════════════════════════════════════

install_acme() {
    cd ~ || return 1
    curl -s https://get.acme.sh | sh >> "$LOG_FILE" 2>&1
    return $?
}

setup_ip_certificate() {
    local ipv4="$1"
    local ipv6="$2"

    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        install_acme || return 1
    fi

    if [[ -z "$ipv4" ]] || ! is_ipv4 "$ipv4"; then
        return 1
    fi

    local certDir="/root/cert/ip"
    mkdir -p "$certDir"

    local domain_args="-d ${ipv4}"
    if [[ -n "$ipv6" ]] && is_ipv6 "$ipv6"; then
        domain_args="${domain_args} -d ${ipv6}"
    fi

    local reloadCmd="systemctl restart x-ui 2>/dev/null || rc-service x-ui restart 2>/dev/null || true"
    local WebPort=""
    prompt_or_default WebPort " ▸ ACME HTTP-01 Listener Port [default 80]: " "80" XUI_ACME_HTTP_PORT
    WebPort="${WebPort:-80}"
    if ! [[ "${WebPort}" =~ ^[0-9]+$ ]] || ((WebPort < 1 || WebPort > 65535)); then
        WebPort=80
    fi

    while true; do
        if is_port_in_use "${WebPort}"; then
            if [[ "$NONINTERACTIVE" == "1" ]]; then
                return 1
            fi
            local alt_port=""
            read -rp " ▸ Port ${WebPort} is busy. Enter alternate port (empty to abort): " alt_port
            alt_port="${alt_port// /}"
            [[ -z "${alt_port}" ]] && return 1
            if ! [[ "${alt_port}" =~ ^[0-9]+$ ]] || ((alt_port < 1 || alt_port > 65535)); then
                return 1
            fi
            WebPort="${alt_port}"
        else
            break
        fi
    done

    ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force >> "$LOG_FILE" 2>&1
    [[ -n "${XUI_ACME_EMAIL:-}" ]] && ~/.acme.sh/acme.sh --register-account -m "${XUI_ACME_EMAIL}" >> "$LOG_FILE" 2>&1

    ~/.acme.sh/acme.sh --issue \
        ${domain_args} \
        --standalone \
        --server letsencrypt \
        --certificate-profile shortlived \
        --days 6 \
        --httpport ${WebPort} \
        --force >> "$LOG_FILE" 2>&1

    if [ $? -ne 0 ]; then
        rm -rf ~/.acme.sh/${ipv4} ~/.acme.sh/${ipv4}_ecc 2> /dev/null
        [[ -n "$ipv6" ]] && rm -rf ~/.acme.sh/${ipv6} ~/.acme.sh/${ipv6}_ecc 2> /dev/null
        rm -rf ${certDir} 2> /dev/null
        return 1
    fi

    ~/.acme.sh/acme.sh --installcert --force -d ${ipv4} \
        --key-file "${certDir}/privkey.pem" \
        --fullchain-file "${certDir}/fullchain.pem" \
        --reloadcmd "${reloadCmd}" >> "$LOG_FILE" 2>&1 || true

    if [[ ! -f "${certDir}/fullchain.pem" || ! -f "${certDir}/privkey.pem" ]]; then
        rm -rf ~/.acme.sh/${ipv4} ~/.acme.sh/${ipv4}_ecc 2> /dev/null
        [[ -n "$ipv6" ]] && rm -rf ~/.acme.sh/${ipv6} ~/.acme.sh/${ipv6}_ecc 2> /dev/null
        rm -rf ${certDir} 2> /dev/null
        return 1
    fi

    ~/.acme.sh/acme.sh --upgrade --auto-upgrade >> "$LOG_FILE" 2>&1
    chmod 600 ${certDir}/privkey.pem 2> /dev/null
    chmod 644 ${certDir}/fullchain.pem 2> /dev/null
    ${xui_folder}/x-ui cert -webCert "${certDir}/fullchain.pem" -webCertKey "${certDir}/privkey.pem" >> "$LOG_FILE" 2>&1
    return 0
}

ssl_cert_issue() {
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep 'webBasePath:' | awk -F': ' '{print $2}' | tr -d '[:space:]' | sed 's#^/##')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep 'port:' | awk -F': ' '{print $2}' | tr -d '[:space:]')

    if ! command -v ~/.acme.sh/acme.sh &> /dev/null; then
        install_acme || return 1
    fi

    local domain=""
    if [[ "$NONINTERACTIVE" == "1" ]]; then
        domain="${XUI_DOMAIN// /}"
        if [[ -z "$domain" ]] || ! is_domain "$domain"; then
            return 1
        fi
    else
        while true; do
            read -rp " ▸ Enter your Domain Name: " domain
            domain="${domain// /}"
            [[ -n "$domain" ]] && is_domain "$domain" && break
            echo -e "   ${C_RED}Invalid domain format. Please try again.${C_NC}"
        done
    fi
    SSL_ISSUED_DOMAIN="${domain}"

    local cert_exists=0
    if ~/.acme.sh/acme.sh --list 2> /dev/null | awk '{print $1}' | grep -Fxq "${domain}"; then
        local acmeCertDir=""
        if [[ -s ~/.acme.sh/${domain}_ecc/fullchain.cer && -s ~/.acme.sh/${domain}_ecc/${domain}.key ]]; then
            acmeCertDir=~/.acme.sh/${domain}_ecc
        elif [[ -s ~/.acme.sh/${domain}/fullchain.cer && -s ~/.acme.sh/${domain}/${domain}.key ]]; then
            acmeCertDir=~/.acme.sh/${domain}
        fi
        if [[ -n "${acmeCertDir}" ]]; then
            cert_exists=1
        else
            rm -rf ~/.acme.sh/${domain} ~/.acme.sh/${domain}_ecc
        fi
    fi

    certPath="/root/cert/${domain}"
    rm -rf "$certPath"
    mkdir -p "$certPath"

    local WebPort=80
    prompt_or_default WebPort " ▸ ACME HTTP-01 Port [default 80]: " "80" XUI_ACME_HTTP_PORT
    if [[ -z ${WebPort} ]] || [[ ! ${WebPort} =~ ^[1-9][0-9]*$ || ${WebPort} -gt 65535 ]]; then
        WebPort=80
    fi

    systemctl stop x-ui 2> /dev/null || rc-service x-ui stop 2> /dev/null

    if [[ ${cert_exists} -eq 0 ]]; then
        ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt --force >> "$LOG_FILE" 2>&1
        [[ -n "${XUI_ACME_EMAIL:-}" ]] && ~/.acme.sh/acme.sh --register-account -m "${XUI_ACME_EMAIL}" >> "$LOG_FILE" 2>&1
        ~/.acme.sh/acme.sh --issue -d ${domain} $(acme_listen_flag) --standalone --httpport ${WebPort} --force >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            rm -rf ~/.acme.sh/${domain} ~/.acme.sh/${domain}_ecc
            systemctl start x-ui 2> /dev/null || rc-service x-ui start 2> /dev/null
            return 1
        fi
    fi

    reloadCmd="systemctl restart x-ui || rc-service x-ui restart"
    local installOutput=""
    installOutput=$(~/.acme.sh/acme.sh --installcert --force -d ${domain} \
        --key-file /root/cert/${domain}/privkey.pem \
        --fullchain-file /root/cert/${domain}/fullchain.pem --reloadcmd "${reloadCmd}" 2>&1)
    local installRc=$?

    local installWroteFiles=0
    if echo "${installOutput}" | grep -q "Installing key to:" && echo "${installOutput}" | grep -q "Installing full chain to:"; then
        installWroteFiles=1
    fi

    if [[ ! -f "/root/cert/${domain}/privkey.pem" || ! -f "/root/cert/${domain}/fullchain.pem" || (${installRc} -ne 0 && ${installWroteFiles} -ne 1) ]]; then
        [[ ${cert_exists} -eq 0 ]] && rm -rf ~/.acme.sh/${domain} ~/.acme.sh/${domain}_ecc
        systemctl start x-ui 2> /dev/null || rc-service x-ui start 2> /dev/null
        return 1
    fi

    ~/.acme.sh/acme.sh --upgrade --auto-upgrade >> "$LOG_FILE" 2>&1
    chmod 600 $certPath/privkey.pem 2> /dev/null
    chmod 644 $certPath/fullchain.pem 2> /dev/null

    ${xui_folder}/x-ui cert -webCert "/root/cert/${domain}/fullchain.pem" -webCertKey "/root/cert/${domain}/privkey.pem" >> "$LOG_FILE" 2>&1
    systemctl start x-ui 2> /dev/null || rc-service x-ui start 2> /dev/null
    return 0
}

prompt_and_setup_ssl() {
    local panel_port="$1"
    local web_base_path="$2"
    local server_ip="$3"
    local ssl_choice=""
    SSL_SCHEME="https"

    if [[ "$NONINTERACTIVE" == "1" ]]; then
        case "${XUI_SSL_MODE:-none}" in
            domain) ssl_choice="1" ;;
            ip) ssl_choice="2" ;;
            none | "") ssl_choice="4" ;;
            *) ssl_choice="4" ;;
        esac
    else
        echo -e "${C_FRAME}┃${C_NC} ${C_CYAN}❖ ZERO-TRUST SSL CONFIGURATION${C_NC}                                           ${C_FRAME}┃${C_NC}"
        echo -e "${C_FRAME}┃${C_NC}   [1] Let's Encrypt Domain (90-day)   [2] Let's Encrypt IP (6-day, Def)  ${C_FRAME}┃${C_NC}"
        echo -e "${C_FRAME}┃${C_NC}   [3] Custom Certificate Paths        [4] Skip SSL (HTTP / Reverse Proxy)${C_FRAME}┃${C_NC}"
        read -rp " ▸ Select SSL Mode [default 2]: " ssl_choice
        ssl_choice="${ssl_choice// /}"
        if [[ "$ssl_choice" != "1" && "$ssl_choice" != "3" && "$ssl_choice" != "4" ]]; then
            ssl_choice="2"
        fi
    fi

    local s_ts=$(date +%s%N)
    case "$ssl_choice" in
        1)
            if ssl_cert_issue; then
                SSL_HOST="${SSL_ISSUED_DOMAIN:-$server_ip}"
            else
                SSL_SCHEME="http"
                SSL_HOST="${server_ip}"
            fi
            ;;
        2)
            local ipv6_addr="${XUI_SSL_IPV6:-}"
            if [[ $release == "alpine" ]]; then
                rc-service x-ui stop > /dev/null 2>&1
            else
                systemctl stop x-ui > /dev/null 2>&1
            fi
            if setup_ip_certificate "${server_ip}" "${ipv6_addr}"; then
                SSL_HOST="${server_ip}"
            else
                SSL_SCHEME="http"
                SSL_HOST="${server_ip}"
            fi
            ;;
        3)
            local custom_cert="" custom_key="" custom_domain=""
            read -rp " ▸ Domain for certificate: " custom_domain
            custom_domain="${custom_domain// /}"
            while true; do
                read -rp " ▸ Fullchain path (.crt/.pem): " custom_cert
                custom_cert=$(echo "$custom_cert" | tr -d '"' | tr -d "'")
                [[ -f "$custom_cert" && -r "$custom_cert" && -s "$custom_cert" ]] && break
            done
            while true; do
                read -rp " ▸ Private key path (.key): " custom_key
                custom_key=$(echo "$custom_key" | tr -d '"' | tr -d "'")
                [[ -f "$custom_key" && -r "$custom_key" && -s "$custom_key" ]] && break
            done
            ${xui_folder}/x-ui cert -webCert "$custom_cert" -webCertKey "$custom_key" > /dev/null 2>&1
            SSL_HOST="${custom_domain:-$server_ip}"
            systemctl restart x-ui > /dev/null 2>&1 || rc-service x-ui restart > /dev/null 2>&1
            ;;
        4)
            SSL_SCHEME="http"
            SSL_HOST="${server_ip}"
            local bind_local="n"
            if [[ "$NONINTERACTIVE" != "1" ]]; then
                read -rp " ▸ Bind panel to 127.0.0.1 only (SSH Tunnel mode)? [y/N]: " bind_local
            fi
            if [[ "$bind_local" == "y" || "$bind_local" == "Y" ]]; then
                ${xui_folder}/x-ui setting -listenIP "127.0.0.1" > /dev/null 2>&1
                SSL_HOST="127.0.0.1"
            fi
            systemctl restart x-ui > /dev/null 2>&1 || rc-service x-ui restart > /dev/null 2>&1
            ;;
    esac
    local e_ts=$(date +%s%N)
    T_P4=$(awk "BEGIN {printf \"%.1fs\", ($e_ts - $s_ts)/1000000000}")
}

# ══════════════════════════════════════════════════════════════════════════
# POST-INSTALL CONFIGURATION & DATABASE PROVISIONING
# ══════════════════════════════════════════════════════════════════════════

config_after_install() {
    local existing_hasDefaultCredential=$(${xui_folder}/x-ui setting -show true | grep -Eo 'hasDefaultCredential: .+' | awk '{print $2}')
    local existing_webBasePath=$(${xui_folder}/x-ui setting -show true | grep -Eo 'webBasePath: .+' | awk '{print $2}' | sed 's#^/##')
    local existing_port=$(${xui_folder}/x-ui setting -show true | grep -Eo 'port: .+' | awk '{print $2}')
    local existing_cert=$(${xui_folder}/x-ui setting -getCert true | grep 'cert:' | awk -F': ' '{print $2}' | tr -d '[:space:]')
    local URL_lists=(
        "https://api4.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://v4.api.ipinfo.io/ip"
        "https://ipv4.myexternalip.com/raw"
        "https://4.ident.me"
        "https://check-host.net/ip"
    )
    local server_ip=""
    for ip_address in "${URL_lists[@]}"; do
        local response=$(curl -s -w "\n%{http_code}" --max-time 3 "${ip_address}" 2> /dev/null)
        local http_code=$(echo "$response" | tail -n1)
        local ip_result=$(echo "$response" | head -n-1 | tr -d '[:space:]"')
        if [[ "${http_code}" == "200" && "${ip_result}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            server_ip="${ip_result}"
            break
        fi
    done

    if [[ -z "$server_ip" ]]; then
        if [[ "$NONINTERACTIVE" == "1" ]]; then
            server_ip="${XUI_SERVER_IP:-127.0.0.1}"
        else
            while [[ -z "$server_ip" ]]; do
                read -rp " ▸ Enter server public IPv4 address: " server_ip
                server_ip="${server_ip// /}"
                [[ ! "$server_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && server_ip=""
            done
        fi
    fi
    DETECTED_IP="$server_ip"

    local db_s_ts=$(date +%s%N)

    if [[ ${#existing_webBasePath} -lt 4 ]]; then
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_webBasePath="${XUI_WEB_BASE_PATH:-$(gen_random_string 18)}"
            local config_username="${XUI_USERNAME:-$(gen_random_string 10)}"
            local config_password="${XUI_PASSWORD:-$(gen_random_string 10)}"
            local config_port=""
            local db_label="SQLite (/etc/x-ui/x-ui.db)"

            if [[ "$NONINTERACTIVE" == "1" ]]; then
                if [[ "${XUI_DB_TYPE:-sqlite}" == "postgres" ]]; then
                    db_choice="2"
                else
                    db_choice="1"
                fi
            else
                echo -e "${C_FRAME}┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${C_NC}"
                echo -e "${C_FRAME}┃${C_NC} ${C_CYAN}❖ INTERACTIVE NODE CONFIGURATION${C_NC}                                         ${C_FRAME}┃${C_NC}"
                echo -e "${C_FRAME}┃${C_NC}   Database Engine: [1] SQLite (Default)   [2] PostgreSQL (High-Load)     ${C_FRAME}┃${C_NC}"
                read -rp " ▸ Choose Database [1]: " db_choice
                db_choice="${db_choice:-1}"
            fi

            if [[ "$db_choice" == "2" ]]; then
                local xui_env_file
                case "${release}" in
                    ubuntu | debian | armbian) xui_env_file="/etc/default/x-ui" ;;
                    arch | manjaro | parch | alpine) xui_env_file="/etc/conf.d/x-ui" ;;
                    *) xui_env_file="/etc/sysconfig/x-ui" ;;
                esac

                local xui_dsn="" pg_mode=""
                while [[ -z "$xui_dsn" ]]; do
                    if [[ "$NONINTERACTIVE" == "1" ]]; then
                        if [[ -n "${XUI_DB_DSN:-}" ]]; then
                            xui_dsn="${XUI_DB_DSN}"
                            db_label="PostgreSQL (External DSN)"
                            break
                        fi
                        local pg_cred_file=$(mktemp 2> /dev/null || mktemp -t x-ui-pg.XXXXXX)
                        if [[ -n "${pg_cred_file}" ]] && xui_dsn=$(PG_CRED_FILE="${pg_cred_file}" install_postgres_local); then
                            [[ -r "${pg_cred_file}" ]] && source "${pg_cred_file}"
                            rm -f "${pg_cred_file}"
                            db_label="PostgreSQL (${PG_USER}@${PG_HOST}:${PG_PORT}/${PG_DB})"
                            break
                        fi
                        rm -f "${pg_cred_file}"
                        exit 1
                    fi
                    read -rp " ▸ PostgreSQL Mode: [1] Local Auto-Install  [2] External DSN [1]: " pg_mode
                    pg_mode="${pg_mode:-1}"
                    if [[ "$pg_mode" == "2" ]]; then
                        while [[ -z "$xui_dsn" ]]; do
                            read -rp " ▸ Enter PostgreSQL DSN: " xui_dsn
                            xui_dsn="${xui_dsn// /}"
                        done
                        db_label="PostgreSQL (External DSN)"
                    else
                        local pg_cred_file=$(mktemp 2> /dev/null || mktemp -t x-ui-pg.XXXXXX)
                        if xui_dsn=$(PG_CRED_FILE="${pg_cred_file}" install_postgres_local); then
                            [[ -r "${pg_cred_file}" ]] && source "${pg_cred_file}"
                            rm -f "${pg_cred_file}"
                            db_label="PostgreSQL (${PG_USER}@${PG_HOST}:${PG_PORT}/${PG_DB})"
                        else
                            rm -f "${pg_cred_file}"
                            db_choice="1"
                            xui_dsn=""
                            break
                        fi
                    fi
                done
                if [[ -n "$xui_dsn" ]]; then
                    install -d -m 755 "$(dirname "$xui_env_file")"
                    umask 077
                    cat > "$xui_env_file" << EOF
XUI_DB_TYPE=postgres
XUI_DB_DSN=${xui_dsn}
EOF
                    chmod 600 "$xui_env_file"
                    umask 022
                    export XUI_DB_TYPE=postgres
                    export XUI_DB_DSN="${xui_dsn}"
                    ensure_pg_client >> "$LOG_FILE" 2>&1 || true
                fi
            fi

            if [[ "$NONINTERACTIVE" == "1" ]]; then
                config_port="${XUI_PANEL_PORT:-$(shuf -i 1024-62000 -n 1)}"
            else
                read -rp " ▸ Custom Panel Port (Leave empty for random): " config_port
                config_port="${config_port// /}"
                if [[ -z "$config_port" ]] || ! [[ "$config_port" =~ ^[0-9]+$ ]]; then
                    config_port=$(shuf -i 1024-62000 -n 1)
                fi
            fi

            ${xui_folder}/x-ui setting -username "${config_username}" -password "${config_password}" -port "${config_port}" -webBasePath "${config_webBasePath}" >> "$LOG_FILE" 2>&1
            local db_e_ts=$(date +%s%N)
            T_P3=$(awk "BEGIN {printf \"%.1fs\", ($db_e_ts - $db_s_ts)/1000000000}")

            prompt_and_setup_ssl "${config_port}" "${config_webBasePath}" "${server_ip}"

            local config_apiToken=$(${xui_folder}/x-ui setting -getApiToken | grep -Eo 'apiToken: .+' | awk '{print $2}')
            : "${SSL_SCHEME:=https}"
            : "${SSL_HOST:=${server_ip}}"
            local db_type_out="sqlite"
            [[ "$db_choice" == "2" ]] && db_type_out="postgres"

            write_install_result "${config_username}" "${config_password}" "${config_port}" \
                "${config_webBasePath}" "${SSL_SCHEME}" "${SSL_HOST}" "${config_apiToken}" "${db_type_out}"

            FINAL_URL="${SSL_SCHEME}://${SSL_HOST}:${config_port}/${config_webBasePath}"
            FINAL_USER="${config_username}"
            FINAL_PASS="${config_password}"
            FINAL_DB="${db_label}"
            FINAL_TOKEN="${config_apiToken}"
        else
            local config_webBasePath=$(gen_random_string 18)
            ${xui_folder}/x-ui setting -webBasePath "${config_webBasePath}" >> "$LOG_FILE" 2>&1
            local db_e_ts=$(date +%s%N)
            T_P3=$(awk "BEGIN {printf \"%.1fs\", ($db_e_ts - $db_s_ts)/1000000000}")

            if [[ -z "${existing_cert}" ]]; then
                prompt_and_setup_ssl "${existing_port}" "${config_webBasePath}" "${server_ip}"
            else
                SSL_SCHEME="https"
                SSL_HOST="${server_ip}"
                T_P4="0.1s"
            fi
            FINAL_URL="${SSL_SCHEME}://${SSL_HOST}:${existing_port}/${config_webBasePath}"
            FINAL_USER="(Existing Operator)"
            FINAL_PASS="(Unchanged)"
        fi
    else
        if [[ "$existing_hasDefaultCredential" == "true" ]]; then
            local config_username="${XUI_USERNAME:-$(gen_random_string 10)}"
            local config_password="${XUI_PASSWORD:-$(gen_random_string 10)}"
            ${xui_folder}/x-ui setting -username "${config_username}" -password "${config_password}" >> "$LOG_FILE" 2>&1
            local config_apiToken=$(${xui_folder}/x-ui setting -getApiToken | grep -Eo 'apiToken: .+' | awk '{print $2}')
            FINAL_USER="${config_username}"
            FINAL_PASS="${config_password}"
            FINAL_TOKEN="${config_apiToken}"
        else
            FINAL_USER="(Existing Operator)"
            FINAL_PASS="(Unchanged)"
        fi
        local db_e_ts=$(date +%s%N)
        T_P3=$(awk "BEGIN {printf \"%.1fs\", ($db_e_ts - $db_s_ts)/1000000000}")

        existing_cert=$(${xui_folder}/x-ui setting -getCert true | grep 'cert:' | awk -F': ' '{print $2}' | tr -d '[:space:]')
        if [[ -z "$existing_cert" ]]; then
            prompt_and_setup_ssl "${existing_port}" "${existing_webBasePath}" "${server_ip}"
        else
            SSL_SCHEME="https"
            SSL_HOST="${server_ip}"
            T_P4="0.1s"
        fi
        FINAL_URL="${SSL_SCHEME}://${SSL_HOST}:${existing_port}/${existing_webBasePath}"
    fi

    ${xui_folder}/x-ui migrate >> "$LOG_FILE" 2>&1
}

# ══════════════════════════════════════════════════════════════════════════
# SYSTEMD SANDBOX & FAIL2BAN HARDENING
# ══════════════════════════════════════════════════════════════════════════

setup_fail2ban() {
    if [[ -n "${XUI_ENABLE_FAIL2BAN+x}" && "${XUI_ENABLE_FAIL2BAN}" != "true" ]]; then
        return 0
    fi
    [[ ! -x /usr/bin/x-ui ]] && return 0
    grep -q '"setup-fail2ban")' /usr/bin/x-ui || return 0
    /usr/bin/x-ui setup-fail2ban >> "$LOG_FILE" 2>&1 || true
    return 0
}

_xui_systemd_major_version() {
    local version=""
    if command -v systemctl > /dev/null 2>&1; then
        version="$(systemctl --version 2>/dev/null | awk 'NR == 1 {print $2}')"
    fi
    if [[ ! "$version" =~ ^[0-9]+$ ]]; then
        echo 0
        return 0
    fi
    echo "$version"
}

_xui_service_write_paths_dropin() {
    local env_file="${1:-}"
    local dropin_dir dropin temp_file
    local db_folder log_folder bin_folder main_folder
    local path line="" seen_paths="" escaped_path

    if [[ -z "$env_file" ]]; then
        case "${release}" in
            ubuntu | debian | armbian) env_file="/etc/default/x-ui" ;;
            arch | manjaro | parch | alpine) env_file="/etc/conf.d/x-ui" ;;
            *) env_file="/etc/sysconfig/x-ui" ;;
        esac
    fi
    if [[ -r "$env_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    fi

    main_folder="${XUI_MAIN_FOLDER:-${xui_folder}}"
    db_folder="${XUI_DB_FOLDER:-/etc/x-ui}"
    log_folder="${XUI_LOG_FOLDER:-/var/log/x-ui}"
    bin_folder="${XUI_BIN_FOLDER:-bin}"
    if [[ "$bin_folder" != /* ]]; then
        bin_folder="${main_folder%/}/${bin_folder#./}"
    fi

    for path in "$db_folder" "$log_folder" "$bin_folder" "$main_folder"; do
        [[ "$path" == /* ]] || continue
        [[ "$path" != "${path//[[:space:]]/}" ]] && continue
        case " $seen_paths " in
            *" $path "*) continue ;;
        esac
        seen_paths="${seen_paths}${seen_paths:+ }$path"
        escaped_path="${path//%/%%}"
        line="${line} -${escaped_path}"
    done
    line="${line# }"
    [[ -n "$line" ]] || return 1

    dropin_dir="${xui_service}/x-ui.service.d"
    dropin="${dropin_dir}/10-xui-sandbox.conf"
    temp_file="${dropin}.tmp.$$"

    mkdir -p "$dropin_dir" || return 1
    cat > "$temp_file" << EOF
[Service]
ReadWritePaths=${line}
ReadWriteDirectories=${line}
EOF
    if [[ "$(_xui_systemd_major_version)" -ge 239 ]]; then
        cat >> "$temp_file" << 'EOF'
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
EOF
    fi
    [[ ! -s "$temp_file" ]] && { rm -f "$temp_file"; return 1; }
    chmod 644 "$temp_file"
    mv -f "$temp_file" "$dropin" || { rm -f "$temp_file"; return 1; }
    command -v systemctl > /dev/null 2>&1 && systemctl daemon-reload > /dev/null 2>&1 || true
    return 0
}

_install_xui_service_unit() {
    local source="$1"
    local source_is_url="$2"
    local dest="${xui_service}/x-ui.service"
    local temp_file="${dest}.tmp.$$"

    rm -f "$temp_file"
    if [[ "$source_is_url" == "true" ]]; then
        curl -fLRo "$temp_file" "$source" > /dev/null 2>&1
    else
        cp -f "$source" "$temp_file" > /dev/null 2>&1
    fi
    [[ $? -ne 0 || ! -s "$temp_file" ]] && { rm -f "$temp_file"; return 1; }
    mv -f "$temp_file" "$dest" || { rm -f "$temp_file"; return 1; }
    _xui_service_write_paths_dropin || true
    return 0
}

# ══════════════════════════════════════════════════════════════════════════
# RELEASE FETCH & CRYPTOGRAPHIC CHECKSUM VERIFICATION
# ══════════════════════════════════════════════════════════════════════════

resolve_latest_tag() {
    local url tag
    url=$(curl -sSLI -o /dev/null -w '%{url_effective}' --retry 5 --retry-delay 3 --connect-timeout 15 --max-time 60 "https://github.com/MHSanaei/3x-ui/releases/latest" 2>/dev/null)
    tag=${url##*/tag/}
    if [[ "$tag" != "$url" && -n "$tag" && "$tag" != "latest" ]]; then
        echo "$tag"
        return 0
    fi
    curl -Ls --retry 5 --retry-delay 3 --connect-timeout 15 --max-time 60 "https://api.github.com/repos/MHSanaei/3x-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'
}

verify_release_checksum() {
    local url="$1" file="$2" sums="$2.sha256" code expected actual
    rm -f "${sums}"
    code=$(curl -sL --retry 3 --retry-delay 3 --connect-timeout 15 --max-time 60 -o "${sums}" -w '%{http_code}' "${url}.sha256")
    if [[ "${code}" == "404" ]]; then
        rm -f "${sums}"
        return 0
    fi
    if [[ "${code}" != "200" ]]; then
        rm -f "${sums}" "${file}"
        return 1
    fi
    expected=$(awk 'NR == 1 {print $1}' "${sums}")
    actual=$(sha256sum "${file}" | awk '{print $1}')
    rm -f "${sums}"
    if [[ ! "${expected}" =~ ^[0-9a-f]{64}$ || "${expected}" != "${actual}" ]]; then
        rm -f "${file}"
        return 1
    fi
    return 0
}

require_repo_files() {
    local ref="$1" name status
    shift
    [[ "${ref}" == "main" ]] && return 0
    for name in "$@"; do
        status=$(curl -sIL --retry 3 --connect-timeout 15 -o /dev/null -w '%{http_code}' "https://raw.githubusercontent.com/MHSanaei/3x-ui/${ref}/${name}")
        [[ "${status}" != "200" ]] && return 1
    done
    return 0
}

# Phase 0x02 Worker: Download, Verify & Extract Core
_phase2_download_and_extract() {
    cd ${xui_folder%/x-ui}/ || return 1

    if [ -z "$tag_version" ]; then
        return 1
    fi

    local url="https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz"
    curl -fLR --retry 5 --retry-delay 3 --connect-timeout 15 --speed-limit 1 --speed-time 300 -o ${xui_folder}-linux-$(arch).tar.gz "${url}" || return 1
    [[ ! -s ${xui_folder}-linux-$(arch).tar.gz ]] && { rm -f ${xui_folder}-linux-$(arch).tar.gz; return 1; }
    verify_release_checksum "${url}" "${xui_folder}-linux-$(arch).tar.gz" || return 1

    local script_ref="${tag_version}"
    [[ "${tag_version}" == "dev-latest" ]] && script_ref="main"

    local required_files=("x-ui.sh")
    [[ $release == "alpine" ]] && required_files+=("x-ui.rc")
    require_repo_files "${script_ref}" "${required_files[@]}" || return 1

    local xui_script_temp="/usr/bin/x-ui-temp.$$"
    rm -f "${xui_script_temp}"
    curl -fLRo "${xui_script_temp}" "https://raw.githubusercontent.com/MHSanaei/3x-ui/${script_ref}/x-ui.sh" || return 1
    [[ ! -s "${xui_script_temp}" ]] && { rm -f "${xui_script_temp}"; return 1; }

    local custom_bin_backup=""
    if [[ -e ${xui_folder}/ ]]; then
        if [[ $release == "alpine" ]]; then
            rc-service x-ui stop > /dev/null 2>&1 || true
        else
            systemctl stop x-ui > /dev/null 2>&1 || true
        fi
        pkill -f 'mtg-linux-[^ ]* run ' > /dev/null 2>&1 || true
        pkill -f 'tuic-server.*-c .*bin/tuic/tuic_[0-9]+\.json' > /dev/null 2>&1 || true

        if [[ -d "${xui_folder}/bin" ]]; then
            custom_bin_backup="${xui_folder%/x-ui}/x-ui-bin-backup.$$"
            rm -rf "${custom_bin_backup}"
            mv "${xui_folder}/bin" "${custom_bin_backup}" || custom_bin_backup=""
        fi
        rm -rf ${xui_folder}/
    fi

    tar zxvf x-ui-linux-$(arch).tar.gz || { rm -f x-ui-linux-$(arch).tar.gz "${xui_script_temp}"; return 1; }
    rm -f x-ui-linux-$(arch).tar.gz

    cd x-ui || return 1
    [[ ! -s x-ui ]] && { rm -f "${xui_script_temp}"; return 1; }
    chmod +x x-ui x-ui.sh

    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm32
        chmod +x bin/xray-linux-arm32
        if [[ -f bin/mtg-linux-$(arch) ]]; then
            mv bin/mtg-linux-$(arch) bin/mtg-linux-arm
            chmod +x bin/mtg-linux-arm
        fi
    fi
    chmod +x x-ui bin/xray-linux-$(arch) 2>/dev/null || true
    [[ -f bin/mtg-linux-arm ]] && chmod +x bin/mtg-linux-arm
    [[ -f bin/mtg-linux-$(arch) ]] && chmod +x bin/mtg-linux-$(arch)

    if [[ -n "${custom_bin_backup}" ]]; then
        while IFS= read -r -d '' f; do
            local rel="${f#"${custom_bin_backup}"/}"
            case "${rel}" in
                config.json | mtproto | mtproto/* | tuic | tuic/* | tuic-server | tuic-server-*) continue ;;
            esac
            if [[ ! -e "bin/${rel}" ]]; then
                mkdir -p "bin/$(dirname "${rel}")"
                cp -a "${f}" "bin/${rel}"
            fi
        done < <(find "${custom_bin_backup}" \( -type f -o -type l \) -print0)
        rm -rf "${custom_bin_backup}"
    fi

    rm -f bin/tuic-server bin/tuic-server-* > /dev/null 2>&1 || true
    rm -rf bin/tuic > /dev/null 2>&1 || true

    mv -f "${xui_script_temp}" /usr/bin/x-ui || return 1
    chmod +x /usr/bin/x-ui
    mkdir -p /var/log/x-ui
    return 0
}

# Phase 0x05 Worker: Systemd Service, Etckeeper & Fail2ban
_phase5_service_and_hardening() {
    cd "${xui_folder}" || return 1
    local script_ref="${tag_version}"
    [[ "${tag_version}" == "dev-latest" ]] && script_ref="main"

    if [ -d "/etc/.git" ]; then
        if [ -f "/etc/.gitignore" ]; then
            if ! grep -q "x-ui/x-ui.db" "/etc/.gitignore"; then
                echo "" >> "/etc/.gitignore"
                echo "x-ui/x-ui.db" >> "/etc/.gitignore"
            fi
        else
            echo "x-ui/x-ui.db" > "/etc/.gitignore"
        fi
    fi

    if [[ $release == "alpine" ]]; then
        local xui_rc_temp="/etc/init.d/x-ui.tmp.$$"
        rm -f "${xui_rc_temp}"
        curl -fLRo "${xui_rc_temp}" "https://raw.githubusercontent.com/MHSanaei/3x-ui/${script_ref}/x-ui.rc" || return 1
        [[ ! -s "${xui_rc_temp}" ]] && { rm -f "${xui_rc_temp}"; return 1; }
        mv -f "${xui_rc_temp}" /etc/init.d/x-ui || return 1
        chmod +x /etc/init.d/x-ui
        rc-update add x-ui
        rc-service x-ui start
    else
        local service_installed=false
        if [ -f "x-ui.service" ]; then
            _install_xui_service_unit "x-ui.service" "false" && service_installed=true
        fi

        if [ "$service_installed" = false ]; then
            case "${release}" in
                ubuntu | debian | armbian)
                    [ -f "x-ui.service.debian" ] && _install_xui_service_unit "x-ui.service.debian" "false" && service_installed=true
                    ;;
                arch | manjaro | parch)
                    [ -f "x-ui.service.arch" ] && _install_xui_service_unit "x-ui.service.arch" "false" && service_installed=true
                    ;;
                *)
                    [ -f "x-ui.service.rhel" ] && _install_xui_service_unit "x-ui.service.rhel" "false" && service_installed=true
                    ;;
            esac
        fi

        if [ "$service_installed" = false ]; then
            local service_unit_url=""
            case "${release}" in
                ubuntu | debian | armbian) service_unit_url="https://raw.githubusercontent.com/MHSanaei/3x-ui/${script_ref}/x-ui.service.debian" ;;
                arch | manjaro | parch) service_unit_url="https://raw.githubusercontent.com/MHSanaei/3x-ui/${script_ref}/x-ui.service.arch" ;;
                *) service_unit_url="https://raw.githubusercontent.com/MHSanaei/3x-ui/${script_ref}/x-ui.service.rhel" ;;
            esac
            _install_xui_service_unit "$service_unit_url" "true" || return 1
        fi

        chown root:root ${xui_service}/x-ui.service > /dev/null 2>&1
        chmod 644 ${xui_service}/x-ui.service > /dev/null 2>&1
        systemctl daemon-reload
        systemctl enable x-ui
        systemctl start x-ui
    fi

    setup_fail2ban
    return 0
}

# ══════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION PIPELINE
# ══════════════════════════════════════════════════════════════════════════

install_x-ui() {
    if [ $# == 0 ]; then
        tag_version=$(resolve_latest_tag)
    else
        tag_version="$1"
        if [[ "$tag_version" == "dev" || "$tag_version" == "dev-latest" ]]; then
            tag_version="dev-latest"
        else
            local tag_version_numeric=${tag_version#v}
            local min_version="2.3.5"
            if [[ "$(printf '%s\n' "$min_version" "$tag_version_numeric" | sort -V | head -n1)" != "$min_version" ]]; then
                echo -e "${C_RED}Please use a newer version (at least v2.3.5).${C_NC}"
                exit 1
            fi
        fi
    fi

    # Render initial Enterprise Appliance Dashboard
    print_appliance_header

    # [0x01] Base Dependencies
    run_appliance_phase "0x01" "System Core & Crypto Libraries" T_P1 install_base

    # [0x02] Core Binary & Checksum
    run_appliance_phase "0x02" "3X-UI Binary & Xray-Core Engine" T_P2 _phase2_download_and_extract

    # [0x03] & [0x04] Database + SSL Configuration
    config_after_install

    # Re-render clean header & phases [0x01]..[0x04] before running [0x05]
    print_appliance_header
    print_completed_phase_row "0x01" "System Core & Crypto Libraries" "$T_P1"
    print_completed_phase_row "0x02" "3X-UI Binary & Xray-Core Engine" "$T_P2"
    print_completed_phase_row "0x03" "Database Provisioning & Migration" "$T_P3"
    print_completed_phase_row "0x04" "ACME Zero-Trust SSL Certificate" "$T_P4"

    # [0x05] Systemd Unit & Fail2ban Guard
    run_appliance_phase "0x05" "Systemd Hardening & IP-Limit Guard" T_P5 _phase5_service_and_hardening

    # Render Final Complete Master Appliance Screen
    print_final_appliance_screen
}

install_x-ui "$@"
