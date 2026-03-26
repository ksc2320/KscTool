#!/bin/bash
# ============================================================================
#  ap_log.sh — AP 로그 실시간 모니터 (컬러 필터링)
# ============================================================================
#  사용법:
#    ./ap_log.sh                    # 기본 AP IP, [ksc] 하이라이트
#    ./ap_log.sh 172.30.1.1         # AP IP 지정
#    ./ap_log.sh 172.30.1.1 dhcp    # 추가 필터
#    ./ap_log.sh -a                 # 전체 로그 (필터 없음, 컬러만)
#    ./ap_log.sh -s                 # 저장 모드 (로그 파일로 저장)
#
#  종료: Ctrl+C
# ============================================================================

# ── 컬러 ──
readonly C_RED='\033[1;31m'
readonly C_GREEN='\033[1;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_CYAN='\033[1;36m'
readonly C_MAGENTA='\033[1;35m'
readonly C_WHITE='\033[1;37m'
readonly C_DIM='\033[0;90m'
readonly C_BG_RED='\033[41;1;37m'
readonly C_BG_YELLOW='\033[43;1;30m'
readonly C_BG_CYAN='\033[46;1;37m'
readonly C_BG_GREEN='\033[42;1;37m'
readonly C_RESET='\033[0m'

# ── 설정 ──
DEFAULT_AP_IP="172.30.1.1"
AP_IP="${DEFAULT_AP_IP}"
EXTRA_FILTER=""
ALL_MODE=0
SAVE_MODE=0
LOG_DIR="$(dirname "$0")/logs"

# ── 인자 파싱 ──
for arg in "$@"; do
    case "$arg" in
        -a|--all) ALL_MODE=1 ;;
        -s|--save) SAVE_MODE=1 ;;
        -h|--help)
            echo -e "${C_CYAN}ap_log.sh${C_RESET} — AP 실시간 로그 모니터"
            echo ""
            echo "  사용법:"
            echo "    ./ap_log.sh                    # 기본 (에러/경고/[ksc] 하이라이트)"
            echo "    ./ap_log.sh 172.30.1.1         # AP IP 지정"
            echo "    ./ap_log.sh 172.30.1.1 dhcp    # dhcp 관련만 필터"
            echo "    ./ap_log.sh -a                 # 전체 로그"
            echo "    ./ap_log.sh -s                 # 파일 저장 병행"
            echo ""
            echo "  하이라이트 규칙:"
            echo -e "    ${C_BG_RED} ERR ${C_RESET}  error, fail, panic, oops, segfault"
            echo -e "    ${C_BG_YELLOW} WRN ${C_RESET}  warn, timeout, refused, denied"
            echo -e "    ${C_BG_CYAN} KSC ${C_RESET}  [ksc] 태그 (디버그 로그)"
            echo -e "    ${C_BG_GREEN} NET ${C_RESET}  dhcp, ipv6, wan, netifd"
            exit 0
            ;;
        [0-9]*) AP_IP="$arg" ;;
        *) EXTRA_FILTER="$arg" ;;
    esac
done

# ── 헤더 ──
echo ""
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  ${C_WHITE}AP Log Monitor${C_RESET}  |  ${C_YELLOW}${AP_IP}${C_RESET}"
[ -n "$EXTRA_FILTER" ] && echo -e "  Filter: ${C_CYAN}${EXTRA_FILTER}${C_RESET}"
[ $ALL_MODE -eq 1 ] && echo -e "  Mode: ${C_GREEN}ALL (필터 없음)${C_RESET}"
echo -e "  ${C_DIM}Ctrl+C 로 종료${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo ""

# ── SSH 확인 ──
if ! ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${AP_IP}" "echo ok" &>/dev/null; then
    echo -e "${C_RED}✘ SSH 접속 실패: root@${AP_IP}${C_RESET}"
    exit 1
fi

# ── 로그 저장 설정 ──
LOG_FILE=""
if [ $SAVE_MODE -eq 1 ]; then
    mkdir -p "$LOG_DIR"
    LOG_FILE="${LOG_DIR}/ap_$(date +%Y%m%d_%H%M%S).log"
    echo -e "${C_DIM}로그 저장: ${LOG_FILE}${C_RESET}"
    echo ""
fi

# ── 컬러 처리 함수 ──
colorize_line() {
    local line="$1"
    local lower_line=$(echo "$line" | tr '[:upper:]' '[:lower:]')

    # [ksc] 태그 — 시안 배경, 가장 높은 우선순위
    if echo "$lower_line" | grep -q '\[ksc\]'; then
        echo -e "${C_BG_CYAN} KSC ${C_RESET} ${C_CYAN}${line}${C_RESET}"
        return
    fi

    # 에러 계열 — 빨강
    if echo "$lower_line" | grep -qE 'error|fail|panic|oops|segfault|crash|bug:|kernel bug'; then
        echo -e "${C_BG_RED} ERR ${C_RESET} ${C_RED}${line}${C_RESET}"
        return
    fi

    # 경고 계열 — 노랑
    if echo "$lower_line" | grep -qE 'warn|timeout|refused|denied|reject|retry|dropped'; then
        echo -e "${C_BG_YELLOW} WRN ${C_RESET} ${C_YELLOW}${line}${C_RESET}"
        return
    fi

    # 네트워크 관련 — 초록
    if echo "$lower_line" | grep -qE 'dhcp|ipv6|wan[^t]|netifd|odhcpd|ra:|prefix|slaac|dhcpv6'; then
        echo -e "${C_BG_GREEN} NET ${C_RESET} ${C_GREEN}${line}${C_RESET}"
        return
    fi

    # WiFi 관련 — 마젠타
    if echo "$lower_line" | grep -qE 'hostapd|wpa_supplicant|ieee80211|ath[0-9]|wifi|wlan'; then
        echo -e "  ${C_MAGENTA}${line}${C_RESET}"
        return
    fi

    # 기본 — 회색
    echo -e "  ${C_DIM}${line}${C_RESET}"
}

# ── 메인 루프 ──
# logread -f 로 실시간 스트리밍
if [ $ALL_MODE -eq 1 ]; then
    # 전체 모드: 모든 로그 출력 (컬러만 적용)
    ssh "root@${AP_IP}" "logread -f" 2>/dev/null | while IFS= read -r line; do
        if [ -n "$EXTRA_FILTER" ]; then
            echo "$line" | grep -qi "$EXTRA_FILTER" || continue
        fi
        colorize_line "$line"
        [ -n "$LOG_FILE" ] && echo "$line" >> "$LOG_FILE"
    done
else
    # 기본 모드: 중요한 것만 + [ksc]
    ssh "root@${AP_IP}" "logread -f" 2>/dev/null | while IFS= read -r line; do
        lower_line=$(echo "$line" | tr '[:upper:]' '[:lower:]')

        # 추가 필터 있으면 해당 필터만
        if [ -n "$EXTRA_FILTER" ]; then
            echo "$lower_line" | grep -qi "$EXTRA_FILTER" || continue
            colorize_line "$line"
            [ -n "$LOG_FILE" ] && echo "$line" >> "$LOG_FILE"
            continue
        fi

        # 기본: 에러/경고/ksc/네트워크 관련만
        if echo "$lower_line" | grep -qE '\[ksc\]|error|fail|panic|warn|timeout|dhcp|ipv6|wan[^t]|netifd|odhcpd|hostapd|denied|refused'; then
            colorize_line "$line"
            [ -n "$LOG_FILE" ] && echo "$line" >> "$LOG_FILE"
        fi
    done
fi

echo ""
echo -e "${C_DIM}모니터 종료${C_RESET}"
[ -n "$LOG_FILE" ] && echo -e "${C_DIM}로그 저장됨: ${LOG_FILE}${C_RESET}"
