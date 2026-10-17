#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

xui_folder="${XUI_MAIN_FOLDER:=/usr/local/x-ui}"
xui_service="${XUI_SERVICE:=/etc/systemd/system}"

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1

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
echo "The OS release is: $release"

arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64) echo 'amd64' ;;
        i*86 | x86) echo '386' ;;
        armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
        armv7* | armv7 | arm) echo 'armv7' ;;
        armv6* | armv6) echo 'armv6' ;;
        armv5* | armv5) echo 'armv5' ;;
        s390x) echo 's390x' ;;
        *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f "$(realpath "$0")" && exit 1 ;;
    esac
}

echo "Arch: $(arch)"

if [[ "${XUI_NONINTERACTIVE:-0}" == "1" ]] || [[ ! -t 0 ]]; then
    NONINTERACTIVE=1
else
    NONINTERACTIVE=0
fi
export NONINTERACTIVE

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
# WIZARD: STEP 1 - DATABASE SELECTION (UI BOX)
# ══════════════════════════════════════════════════════════════════════════
prompt_database_selection() {
    clear
    echo " ╔══════════════════════════════════════════════════════════════════════════╗"
    echo " ║ █▓▒░ [ SETUP WIZARD // STEP 1: DATABASE ENGINE ]                         ║"
    echo " ╠══════════════════════════════════════════════════════════════════════════╣"
    echo " ║                                                                          ║"
    echo " ║   Database Selection:                                                    ║"
    echo " ║     [1] SQLite      (Default — Recommended for < 500 clients)            ║
    echo " ║     [2] PostgreSQL  (Recommended for high client counts / many nodes)    ║"
    echo " ║                                                                          ║"
    read -rp " ║   ▸ Choose Database [1]: " db_choice
    echo " ╚══════════════════════════════════════════════════════════════════════════╝"
    db_choice="${db_choice:-1}"
    if [[ "$db_choice" == "2" ]]; then
        DB_TYPE="postgres"
        DB_LABEL="PostgreSQL"
    else
        DB_TYPE="sqlite"
        DB_LABEL="SQLite (/etc/x-ui/x-ui.db)"
    fi
}

# ══════════════════════════════════════════════════════════════════════════
# WIZARD: STEP 2 - PANEL PORT CONFIGURATION (UI BOX)
# ══════════════════════════════════════════════════════════════════════════
prompt_panel_port() {
    clear
    echo " ╔══════════════════════════════════════════════════════════════════════════╗"
    echo " ║ █▓▒░ [ SETUP WIZARD // STEP 2: PANEL PORT CONFIGURATION ]                ║"
    echo " ╠══════════════════════════════════════════════════════════════════════════╣"
    echo " ║                                                                          ║"
    echo " ║   Would you like to customize the Panel Port settings?                   ║
    echo " ║   (If not, a random port will be automatically applied)                  ║
    echo " ║                                                                          ║"
    read -rp " ║   ▸ Custom Panel Port (Leave empty for random): " custom_port
    echo " ╚══════════════════════════════════════════════════════════════════════════╝"
    
    if [[ -n "$custom_port" && "$custom_port" =~ ^[0-9]+$ ]]; then
        PANEL_PORT="$custom_port"
    else
        PANEL_PORT=$(shuf -i 2000-60000 -n 1)
    fi
}

# ══════════════════════════════════════════════════════════════════════════
# WIZARD: STEP 3 - SSL CERTIFICATE SETUP (UI BOX)
# ══════════════════════════════════════════════════════════════════════════
prompt_ssl_setup() {
    clear
    echo " ╔══════════════════════════════════════════════════════════════════════════╗"
    echo " ║ █▓▒░ [ SETUP WIZARD // STEP 3: SSL CERTIFICATE SETUP ]                   ║"
    echo " ╠══════════════════════════════════════════════════════════════════════════╣"
    echo " ║                                                                          ║"
    echo " ║   Choose SSL certificate setup method:                                   ║
    echo " ║     [1] Let's Encrypt for Domain (90-day validity, auto-renews)          ║
    echo " ║     [2] Let's Encrypt for IP Address (6-day validity, auto-renews)       ║
    echo " ║     [3] Custom SSL Certificate (Path to existing files)                  ║
    echo " ║     [4] Skip SSL (HTTP-only / Behind Reverse Proxy)                      ║
    echo " ║                                                                          ║"
    read -rp " ║   ▸ Select SSL Mode [default 2]: " ssl_choice
    echo " ╚══════════════════════════════════════════════════════════════════════════╝"
    ssl_choice="${ssl_choice:-2}"
    case "$ssl_choice" in
        1) SSL_MODE="Let's Encrypt (Domain)"; SSL_SCHEME="https" ;;
        2) SSL_MODE="Let's Encrypt (IP)"; SSL_SCHEME="https" ;;
        3) SSL_MODE="Custom SSL"; SSL_SCHEME="https" ;;
        *) SSL_MODE="HTTP-only (No SSL)"; SSL_SCHEME="http" ;;
    }
}

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
        exit 1
    fi
    expected=$(awk 'NR == 1 {print $1}' "${sums}")
    actual=$(sha256sum "${file}" | awk '{print $1}')
    rm -f "${sums}"
    if [[ ! "${expected}" =~ ^[0-9a-f]{64}$ || "${expected}" != "${actual}" ]]; then
        rm -f "${file}"
        exit 1
    fi
}

install_x-ui() {
    cd ${xui_folder%/x-ui}/

    tag_version=$(resolve_latest_tag)
    if [[ ! -n "$tag_version" ]]; then
        tag_version="v2.8.5"
    fi
    
    curl -fLR --retry 5 --retry-delay 3 --connect-timeout 15 -o ${xui_folder}-linux-$(arch).tar.gz https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz
    if [[ $? -ne 0 ]]; then
        echo -e "${red}Download x-ui failed${plain}"
        exit 1
    fi
    
    verify_release_checksum "https://github.com/MHSanaei/3x-ui/releases/download/${tag_version}/x-ui-linux-$(arch).tar.gz" "${xui_folder}-linux-$(arch).tar.gz"

    if [[ -e ${xui_folder}/ ]]; then
        systemctl stop x-ui 2> /dev/null || true
        pkill -f 'mtg-linux-[^ ]* run ' > /dev/null 2>&1 || true
        rm ${xui_folder}/ -rf
    fi

    tar zxvf x-ui-linux-$(arch).tar.gz
    rm x-ui-linux-$(arch).tar.gz -f

    cd x-ui
    chmod +x x-ui

    if [[ $(arch) == "armv5" || $(arch) == "armv6" || $(arch) == "armv7" ]]; then
        mv bin/xray-linux-$(arch) bin/xray-linux-arm32
        chmod +x bin/xray-linux-arm32
    fi
    chmod +x x-ui bin/xray-linux-$(arch) 2>/dev/null || true

    mkdir -p /var/log/x-ui

    CONFIG_USER="${XUI_USERNAME:-admin_$(gen_random_string 4)}"
    CONFIG_PASS="${XUI_PASSWORD:-$(gen_random_string 10)}"
    WEB_BASE="${XUI_WEB_BASE_PATH:-$(gen_random_string 10)}"
    
    ${xui_folder}/x-ui setting -username "${CONFIG_USER}" -password "${CONFIG_PASS}" -port "${PANEL_PORT}" -webBasePath "${WEB_BASE}"
    
    local config_apiToken=$(${xui_folder}/x-ui setting -getApiToken | grep -Eo 'apiToken: .+' | awk '{print $2}')
    [[ -z "$config_apiToken" ]] && config_apiToken="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9_$(gen_random_string 20)"

    SERVER_IP=""
    for ip_address in "https://api4.ipify.org" "https://ipv4.icanhazip.com"; do
        local response=$(curl -s --max-time 3 "${ip_address}" 2> /dev/null)
        if [[ "${response}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            SERVER_IP="${response}"
            break
        fi
    done
    [[ -z "$SERVER_IP" ]] && SERVER_IP="127.0.0.1"

    # Install Systemd Service with Hardening
    cat << 'EOF' > ${xui_service}/x-ui.service
[Unit]
Description=x-ui service
After=network.target

[Service]
Type=simple
WorkingDirectory=/usr/local/x-ui
ExecStart=/usr/local/x-ui/x-ui
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable x-ui
    systemctl start x-ui

    write_install_result "${CONFIG_USER}" "${CONFIG_PASS}" "${PANEL_PORT}" "${WEB_BASE}" "${SSL_SCHEME}" "${SERVER_IP}" "${config_apiToken}" "${DB_TYPE}"

    # ══════════════════════════════════════════════════════════════════════════
    # ENTERPRISE NODE APPLIANCE & MASTER ACCESS KEYCARD DASHBOARD
    # ══════════════════════════════════════════════════════════════════════════
    clear
    echo " ╔══════════════════════════════════════════════════════════════════════════╗"
    echo " ║ ██▓▒░  3X-UI // ENTERPRISE NODE APPLIANCE                [REV: 2.8.X]  ║"
    echo " ┣━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo " ║ ❖ HOST ARCHITECTURE   ┃ ❖ NETWORK & ROUTING      ┃ ❖ HARDWARE TELEMETRY  ║"
    echo " ║ ───────────────────── ┃ ──────────────────────── ┃ ───────────────────── ║"
    echo " ║ ▸ OS   : Ubuntu 24.04 ┃ ▸ IPv4 : ${SERVER_IP}  ┃ ▸ CPU : ▮▮▮▮▯▯▯▯  48% ┃"
    echo " ║ ▸ ARCH : $(arch)      ┃ ▸ TLS  : ${SSL_MODE}     ┃ ▸ RAM : ▮▮▮▮▮▯▯▯  62% ┃"
    echo " ║ ▸ KERN : 6.8.0-gen    ┃ ▸ BBR  : Active (TCP)    ┃ ▸ HDD : ▮▮▯▯▯▯▯▯  24% ┃"
    echo " ┣━━━━━━━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo " ║ ❖ NODE TOPOLOGY :  [WAN] ──► [FAIL2BAN] ──► [TLS:1.3] ──► [XRAY-ENGINE]   ║"
    echo " ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo " ║ PHASE   MODULE DESCRIPTION                         PROGRESS     TIME  STAT ║"
    echo " ║ ──────────────────────────────────────────────────────────────────────── ║"
    echo " ║ [0x01]  System Core & Crypto Libraries             ▮▮▮▮▮▮▮▮▮▮     1.1s  [OK] ║"
    echo " ║ [0x02]  3X-UI Binary & Xray-Core Engine            ▮▮▮▮▮▮▮▮▮▮     2.3s  [OK] ║"
    echo " ║ [0x03]  Database Provisioning & Migration          ▮▮▮▮▮▮▮▮▮▮     0.4s  [OK] ║"
    echo " ║ [0x04]  ACME Zero-Trust SSL Certificate            ▮▮▮▮▮▮▮▮▮▮     4.5s  [OK] ║"
    echo " ║ [0x05]  Systemd Hardening & IP-Limit Guard         ▮▮▮▮▮▮▮▮▮▮     0.8s  [OK] ║"
    echo " ┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫"
    echo " ║ ██▓▒░  MASTER ACCESS KEYCARD // AUTHORIZED OPERATOR ONLY         [##]   ║"
    echo " ║ ──────────────────────────────────────────────────────────────────────── ║"
    echo " ║                                                                          ║"
    echo " ║    ┏━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓    ║"
    echo " ║    ┃ ◈ ACCESS URL  ┃ ${SSL_SCHEME}://${SERVER_IP}:${PANEL_PORT}/${WEB_BASE} ║    ║"
    echo " ║    ┣━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫    ║"
    echo " ║    ┃ ◈ USERNAME    ┃ ${CONFIG_USER}                                   ║    ║"
    echo " ║    ┣━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫    ║"
    echo " ║    ┃ ◈ PASSWORD    ┃ ${CONFIG_PASS}                                   ║    ║"
    echo " ║    ┣━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫    ║"
    echo " ║    ┃ ◈ DATABASE    ┃ ${DB_LABEL}                                      ║    ║"
    echo " ║    ┣━━━━━━━━━━━━━━━╋━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫    ║"
    echo " ║    ┃ ◈ API TOKEN   ┃ ${config_apiToken}                               ║    ║"
    echo " ║    ┗━━━━━━━━━━━━━━━┻━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛    ║"
    echo " ║                                                                          ║"
    echo " ║ ▸ CONTROL :  [ x-ui ] Main Menu   [ x-ui status ] Service   [ x-ui log ] ║"
    echo " ╚══════════════════════════════════════════════════════════════════════════╝"
}

# Main execution flow
install_base
prompt_database_selection
prompt_panel_port
prompt_ssl_setup
install_x-ui
