#!/bin/bash
# ============================================================================
#  ipv6_verify.sh — AP IPv6 규격 검증 (KT V2.1.1 기준)
# ============================================================================
#  사용법:
#    ./ipv6_verify.sh              # 기본 AP IP
#    ./ipv6_verify.sh 172.30.1.1   # AP IP 지정
#    ./ipv6_verify.sh -v           # 상세 출력
# ============================================================================

# ── 컬러 ──
readonly C_RED='\033[1;31m'
readonly C_GREEN='\033[1;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_CYAN='\033[1;36m'
readonly C_MAGENTA='\033[1;35m'
readonly C_WHITE='\033[1;37m'
readonly C_DIM='\033[0;90m'
readonly C_BG_GREEN='\033[42;1;37m'
readonly C_BG_RED='\033[41;1;37m'
readonly C_BG_YELLOW='\033[43;1;30m'
readonly C_RESET='\033[0m'

readonly PASS="${C_BG_GREEN} PASS ${C_RESET}"
readonly FAIL="${C_BG_RED} FAIL ${C_RESET}"
readonly SKIP="${C_BG_YELLOW} SKIP ${C_RESET}"
readonly INFO="${C_CYAN}INFO${C_RESET}"

# ── 설정 ──
DEFAULT_AP_IP="172.30.1.1"
AP_IP="${1:-$DEFAULT_AP_IP}"
VERBOSE=0
[[ "$1" == "-v" || "$2" == "-v" ]] && VERBOSE=1
[[ "$1" == "-v" ]] && AP_IP="${2:-$DEFAULT_AP_IP}"

# ── 카운터 ──
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

# ── 테스트 함수 ──
run_test() {
    local name="$1"
    local cmd="$2"
    local grep_pattern="$3"
    local description="$4"

    TOTAL=$((TOTAL + 1))

    local result
    result=$(ssh -o ConnectTimeout=3 "root@${AP_IP}" "$cmd" 2>/dev/null)

    if [ $? -ne 0 ]; then
        printf "  %-4s %-40s %b\n" "[$TOTAL]" "$name" "$FAIL"
        echo -e "       ${C_DIM}SSH 실행 실패: $cmd${C_RESET}"
        FAILED=$((FAILED + 1))
        return 1
    fi

    if echo "$result" | grep -qE "$grep_pattern"; then
        printf "  %-4s %-40s %b\n" "[$TOTAL]" "$name" "$PASS"
        [ $VERBOSE -eq 1 ] && echo -e "       ${C_DIM}${result}${C_RESET}"
        PASSED=$((PASSED + 1))
        return 0
    else
        printf "  %-4s %-40s %b\n" "[$TOTAL]" "$name" "$FAIL"
        echo -e "       ${C_DIM}expected: $grep_pattern${C_RESET}"
        [ -n "$result" ] && echo -e "       ${C_DIM}got: ${result:0:120}${C_RESET}"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

run_test_empty() {
    # grep_pattern에 매치되면 FAIL (존재하면 안되는 것 검증)
    local name="$1"
    local cmd="$2"
    local fail_pattern="$3"

    TOTAL=$((TOTAL + 1))

    local result
    result=$(ssh -o ConnectTimeout=3 "root@${AP_IP}" "$cmd" 2>/dev/null)

    if echo "$result" | grep -qE "$fail_pattern"; then
        printf "  %-4s %-40s %b\n" "[$TOTAL]" "$name" "$FAIL"
        echo -e "       ${C_DIM}불필요한 항목 존재: ${result:0:120}${C_RESET}"
        FAILED=$((FAILED + 1))
        return 1
    else
        printf "  %-4s %-40s %b\n" "[$TOTAL]" "$name" "$PASS"
        PASSED=$((PASSED + 1))
        return 0
    fi
}

# ── 헤더 ──
echo ""
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  ${C_WHITE}IPv6 규격 검증${C_RESET} — KT WiFi 홈 AP V2.1.1"
echo -e "  AP: ${C_YELLOW}${AP_IP}${C_RESET}  |  $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

# ── SSH 접속 확인 ──
echo ""
echo -e "${C_DIM}  SSH 접속 확인...${C_RESET}"
if ! ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${AP_IP}" "echo ok" &>/dev/null; then
    echo -e "  ${FAIL} ${C_RED}SSH 접속 불가: root@${AP_IP}${C_RESET}"
    exit 1
fi
echo -e "  ${C_GREEN}✔ SSH 연결 정상${C_RESET}"

# ═══════════════════════════════════════════════════
echo ""
echo -e "${C_MAGENTA}  ── WAN IPv6 (DHCPv6) ──${C_RESET}"
# ═══════════════════════════════════════════════════

run_test \
    "wan6 인터페이스 존재" \
    "uci show network.wan6" \
    "proto.*dhcpv6" \
    "DHCPv6 클라이언트 설정"

run_test \
    "wan6 Global IPv6 주소 할당" \
    "ip -6 addr show dev wan6 2>/dev/null || ip -6 addr show dev eth0.2 2>/dev/null" \
    "scope global" \
    "DHCPv6 IA_NA 주소 수신"

run_test \
    "IPv6 default route 존재" \
    "ip -6 route show default" \
    "default.*via" \
    "게이트웨이 라우트"

run_test \
    "wan6 reqprefix (PD 요청)" \
    "uci get network.wan6.reqprefix 2>/dev/null || echo auto" \
    "auto|48|56|60|64" \
    "Prefix Delegation 요청 활성화"

# ═══════════════════════════════════════════════════
echo ""
echo -e "${C_MAGENTA}  ── LAN IPv6 (RA/SLAAC) ──${C_RESET}"
# ═══════════════════════════════════════════════════

run_test \
    "br-lan Global IPv6 주소" \
    "ip -6 addr show dev br-lan" \
    "scope global" \
    "PD prefix → LAN 배포"

run_test \
    "odhcpd RA 활성화" \
    "uci show dhcp.lan.ra" \
    "server|relay" \
    "Router Advertisement"

run_test \
    "ra_flags managed" \
    "uci get dhcp.lan.ra_flags 2>/dev/null" \
    "managed-config|other-config" \
    "M/O 플래그"

run_test \
    "odhcpd 데몬 실행" \
    "pgrep -x odhcpd" \
    "[0-9]+" \
    "odhcpd 프로세스"

# ═══════════════════════════════════════════════════
echo ""
echo -e "${C_MAGENTA}  ── Firewall IPv6 ──${C_RESET}"
# ═══════════════════════════════════════════════════

run_test \
    "wan6 → wan zone 소속" \
    "uci show firewall | grep 'zone.*wan.*network'" \
    "wan6" \
    "wan zone에 wan6 포함"

run_test \
    "ICMPv6 input ACCEPT" \
    "uci show firewall | grep icmpv6" \
    "icmpv6" \
    "ICMPv6 규칙 존재"

run_test \
    "ip6tables FORWARD 정책" \
    "ip6tables -L FORWARD -n 2>/dev/null | head -5 || nft list chain inet fw4 forward 2>/dev/null | head -5" \
    "ACCEPT\|accept\|policy" \
    "IPv6 포워딩"

# ═══════════════════════════════════════════════════
echo ""
echo -e "${C_MAGENTA}  ── ip6_passthru ACL (switch0) ──${C_RESET}"
# ═══════════════════════════════════════════════════

run_test_empty \
    "ip6_passthru ACL 미존재" \
    "uci show network | grep ip6_passthru" \
    "ip6_passthru"

# ═══════════════════════════════════════════════════
echo ""
echo -e "${C_MAGENTA}  ── DNS IPv6 ──${C_RESET}"
# ═══════════════════════════════════════════════════

run_test \
    "IPv6 DNS 서버 수신" \
    "cat /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null || cat /tmp/resolv.conf 2>/dev/null" \
    "nameserver.*:" \
    "IPv6 nameserver"

run_test \
    "외부 IPv6 연결 (ping6)" \
    "ping6 -c1 -W3 2001:4860:4860::8888 2>/dev/null && echo REACHABLE || echo UNREACHABLE" \
    "REACHABLE" \
    "Google DNS IPv6 도달성"

# ═══════════════════════════════════════════════════
# 결과 요약
# ═══════════════════════════════════════════════════
echo ""
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

if [ $FAILED -eq 0 ]; then
    echo -e "  ${C_BG_GREEN}  RESULT  ${C_RESET}  ${C_GREEN}ALL PASS${C_RESET} — ${PASSED}/${TOTAL} 항목 통과"
else
    echo -e "  ${C_BG_RED}  RESULT  ${C_RESET}  ${C_RED}${FAILED} FAILED${C_RESET} / ${PASSED} passed / ${TOTAL} total"
fi

echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo ""

exit $FAILED
