#!/bin/bash
# ============================================================================
#  dvcon.sh — AP SSH 자동 연결 v1.0.0
# ============================================================================
#  사용법:  dvcon [IP]
#
#  ftd config (~/.config/ftd/config) 에서 AP IP / 계정 정보를 읽어
#  ssh root@AP_IP 를 자동으로 실행한다.
#
#  인자:
#    [IP]   AP IP 직접 지정 (생략 시 ftd config / enx 자동 감지)
# ============================================================================

DVC_VERSION='1.0.0'
FTD_CONF="$HOME/.config/ftd/config"

# ── 컬러 ─────────────────────────────────────────────────────────────────────
_F_RED='\033[1;31m';  _F_GREEN='\033[1;32m';  _F_YELLOW='\033[1;33m'
_F_CYAN='\033[1;36m'; _F_WHITE='\033[1;37m';  _F_DIM='\033[0;90m'
_F_RST='\033[0m';     _F_BOLD='\033[1m'
_OK="${_F_GREEN}✔${_F_RST}"; _FAIL="${_F_RED}✘${_F_RST}"; _RUN="${_F_CYAN}▶${_F_RST}"

# ── 기본값 ───────────────────────────────────────────────────────────────────
FTD_AP_IP='auto'
FTD_LOGIN_USER='root'
FTD_LOGIN_PASS=''

# ── ftd config 로드 ───────────────────────────────────────────────────────────
# shellcheck disable=SC1090
[ -f "$FTD_CONF" ] && source "$FTD_CONF" 2>/dev/null

# ── AP IP 결정 ────────────────────────────────────────────────────────────────
_dvc_ap_ip() {
    local override="$1"
    [ -n "$override" ] && { echo "$override"; return; }

    if [ "$FTD_AP_IP" != 'auto' ]; then
        echo "$FTD_AP_IP"
        return
    fi

    # enx 인터페이스 기반 자동 감지 (.254)
    local enx_info host_ip
    enx_info=$(ip -4 addr show 2>/dev/null | grep -A2 'enx' | grep 'inet ' | head -1)
    if [ -n "$enx_info" ]; then
        host_ip=$(echo "$enx_info" | awk '{print $2}' | cut -d/ -f1)
        echo "${host_ip%.*}.254"
    else
        echo "192.168.1.254"
    fi
}

# ── 메인 ─────────────────────────────────────────────────────────────────────
_dvc_main() {
    local ip_override="${1:-}"
    local ap_ip user pass

    ap_ip=$(_dvc_ap_ip "$ip_override")
    user="${FTD_LOGIN_USER:-root}"
    pass="${FTD_LOGIN_PASS:-}"

    echo ""
    echo -e "  ${_RUN} AP 접속: ${_F_CYAN}${user}${_F_RST}@${_F_WHITE}${ap_ip}${_F_RST}"
    echo ""

    if [ -n "$pass" ] && command -v sshpass &>/dev/null; then
        sshpass -p "$pass" ssh \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=5 \
            -o ServerAliveInterval=15 \
            "${user}@${ap_ip}"
    else
        ssh \
            -o StrictHostKeyChecking=no \
            -o ConnectTimeout=5 \
            -o ServerAliveInterval=15 \
            "${user}@${ap_ip}"
    fi

    local exit_code=$?
    echo ""
    if [ $exit_code -eq 0 ]; then
        echo -e "  ${_OK} 연결 종료 (${_F_DIM}${ap_ip}${_F_RST})"
    else
        echo -e "  ${_FAIL} 연결 실패 ${_F_DIM}(exit ${exit_code})${_F_RST}"
        echo -e "  ${_F_DIM}IP 확인: fwd doctor  |  IP 변경: fwd set → FTD_AP_IP${_F_RST}"
    fi
    echo ""
}

_dvc_main "$@"
