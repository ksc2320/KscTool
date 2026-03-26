#!/bin/bash
# ============================================================================
#  fw_deploy.sh — 펌웨어 빌드 → AP 자동 업데이트
# ============================================================================
#  기존 플로우: dv cp fw → SecureCRT wget 버튼 → 수동 sysupgrade
#  개선 플로우: dv cp fw → fwd → 자동 wget + sysupgrade
#
#  사용법:
#    fwd                    # 환경변수 기반 자동 감지
#    fwd 172.30.2.1         # AP IP 지정
#    fwd -n                 # sysupgrade -n (설정 초기화)
#    fwd -p 80              # HTTP 포트 지정
#    fwd 172.30.2.1 -n -p 80
# ============================================================================

# ── 컬러 정의 ──
readonly C_RED='\033[1;31m'
readonly C_GREEN='\033[1;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_CYAN='\033[1;36m'
readonly C_MAGENTA='\033[1;35m'
readonly C_WHITE='\033[1;37m'
readonly C_DIM='\033[0;90m'
readonly C_RESET='\033[0m'

readonly ICON_OK="${C_GREEN}✔${C_RESET}"
readonly ICON_FAIL="${C_RED}✘${C_RESET}"
readonly ICON_RUN="${C_CYAN}▶${C_RESET}"
readonly ICON_WARN="${C_YELLOW}⚠${C_RESET}"
readonly ICON_FW="${C_MAGENTA}⬢${C_RESET}"

# ── 설정: 환경변수 우선, 없으면 기본값 ──
DEFAULT_AP_IP="172.30.1.1"
HOST_IP="172.30.1.3"
HTTP_PORT=""                          # 자동 감지 (8080 → 80 순서)
TFTP_DIR="${TFTP_PATH:-/tftpboot}"    # 환경변수 $TFTP_PATH 사용
SYSUPGRADE_OPTS=""

# FW 파일: 환경변수 $FW_NAME → tftpboot 내 최신 .img 자동 감지
AUTO_FW_NAME="${FW_NAME:-}"

# ── 인자 파싱 ──
AP_IP="${DEFAULT_AP_IP}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) SYSUPGRADE_OPTS="-n"; shift ;;
        -p) HTTP_PORT="$2"; shift 2 ;;
        -h|--help)
            echo -e "${C_CYAN}fw_deploy.sh${C_RESET} — AP 펌웨어 자동 배포"
            echo ""
            echo -e "  ${C_WHITE}사용법:${C_RESET}"
            echo "    fwd                    # 환경변수 자동 감지"
            echo "    fwd 172.30.2.1         # AP IP 지정"
            echo "    fwd -n                 # 설정 초기화 업그레이드"
            echo "    fwd -p 80              # HTTP 포트 지정"
            echo ""
            echo -e "  ${C_WHITE}자동 감지:${C_RESET}"
            echo "    FW 파일  : \$FW_NAME → tftpboot 최신 .img"
            echo "    TFTP 경로: \$TFTP_PATH → /tftpboot"
            echo "    HTTP 포트: -p 지정 → 8080 → 80 (순서대로 시도)"
            exit 0
            ;;
        [0-9]*)  AP_IP="$1"; shift ;;
        *) shift ;;
    esac
done

# ── FW 파일 자동 감지 ──
if [ -n "$AUTO_FW_NAME" ] && [ -f "${TFTP_DIR}/${AUTO_FW_NAME}" ]; then
    FW_FILE="$AUTO_FW_NAME"
else
    # tftpboot에서 최신 .img 파일 찾기
    FW_FILE=$(ls -t "${TFTP_DIR}"/*.img 2>/dev/null | head -1 | xargs -r basename)
    if [ -z "$FW_FILE" ]; then
        echo -e "${ICON_FAIL} ${C_RED}${TFTP_DIR}에 .img 파일 없음${C_RESET}"
        echo -e "${C_DIM}   → 먼저 'dv cp fw' 실행 필요${C_RESET}"
        exit 1
    fi
fi

FW_PATH="${TFTP_DIR}/${FW_FILE}"
FW_SIZE=$(du -h "$FW_PATH" | awk '{print $1}')
FW_DATE=$(stat -c '%y' "$FW_PATH" | cut -d. -f1)

# ── HTTP 포트 자동 감지 ──
detect_http_port() {
    # -p로 지정했으면 그대로 사용
    [ -n "$HTTP_PORT" ] && return 0

    # 8080 먼저 시도
    for port in 8080 80; do
        if curl -s --connect-timeout 1 "http://${HOST_IP}:${port}/" -o /dev/null 2>/dev/null; then
            HTTP_PORT="$port"
            return 0
        fi
    done

    # 둘 다 안되면 8080 기본 (자동 시작용)
    HTTP_PORT="8080"
    return 1
}

detect_http_port
HTTP_DETECTED=$?

# ── 헤더 ──
echo ""
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${ICON_FW}  ${C_WHITE}FW Deploy${C_RESET} — AP 펌웨어 자동 배포"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  AP   : ${C_YELLOW}${AP_IP}${C_RESET}"
echo -e "  Host : ${C_YELLOW}${HOST_IP}:${HTTP_PORT}${C_RESET}"
echo -e "  FW   : ${C_YELLOW}${FW_FILE}${C_RESET} (${C_WHITE}${FW_SIZE}${C_RESET}, ${C_DIM}${FW_DATE}${C_RESET})"
[ -n "$SYSUPGRADE_OPTS" ] && echo -e "  Opts : ${C_RED}${SYSUPGRADE_OPTS} (설정 초기화)${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo ""

# ── Step 1: HTTP 서버 확인 + 자동 시작 ──
echo -e "${ICON_RUN} [1/4] HTTP 서버 확인..."
if [ $HTTP_DETECTED -eq 0 ] && curl -s --connect-timeout 2 "http://${HOST_IP}:${HTTP_PORT}/${FW_FILE}" -o /dev/null -w "%{http_code}" 2>/dev/null | grep -q "200"; then
    echo -e "${ICON_OK} HTTP :${HTTP_PORT} 정상 — ${FW_FILE} 접근 가능"
else
    echo -e "${C_DIM}   HTTP 서버 없음 → 자동 시작 (:${HTTP_PORT})${C_RESET}"
    python3 -m http.server --directory "${TFTP_DIR}" "${HTTP_PORT}" &>/dev/null &
    HTTP_PID=$!
    sleep 1
    if kill -0 "$HTTP_PID" 2>/dev/null; then
        echo -e "${ICON_OK} HTTP 서버 자동 시작 (PID: ${HTTP_PID}, :${HTTP_PORT})"
    else
        echo -e "${ICON_FAIL} ${C_RED}HTTP 서버 시작 실패${C_RESET}"
        echo -e "${C_DIM}   → 포트 ${HTTP_PORT} 충돌? 'fwd -p 다른포트' 시도${C_RESET}"
        exit 1
    fi
fi

# ── Step 2: AP SSH 접속 확인 ──
echo -e "${ICON_RUN} [2/4] AP SSH 접속 확인 (${AP_IP})..."
if ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${AP_IP}" "echo ok" &>/dev/null; then
    echo -e "${ICON_OK} SSH 연결 정상"
else
    echo -e "${ICON_FAIL} ${C_RED}SSH 접속 실패: root@${AP_IP}${C_RESET}"
    echo -e "${C_DIM}   → AP 전원/네트워크 확인, SSH 키 등록 여부 확인${C_RESET}"
    exit 1
fi

# ── Step 3: AP에서 wget 다운로드 ──
WGET_URL="http://${HOST_IP}:${HTTP_PORT}/${FW_FILE}"
echo -e "${ICON_RUN} [3/4] AP에서 펌웨어 다운로드..."
echo -e "${C_DIM}   wget ${WGET_URL}${C_RESET}"

ssh "root@${AP_IP}" "cd /tmp && rm -f '${FW_FILE}' && wget -q '${WGET_URL}'" 2>&1
if [ $? -ne 0 ]; then
    echo -e "${ICON_FAIL} ${C_RED}wget 실패${C_RESET}"
    exit 1
fi

# 크기 검증
REMOTE_SIZE=$(ssh "root@${AP_IP}" "wc -c < '/tmp/${FW_FILE}'" 2>/dev/null | tr -d ' ')
LOCAL_SIZE=$(wc -c < "$FW_PATH" | tr -d ' ')
if [ "$REMOTE_SIZE" == "$LOCAL_SIZE" ]; then
    echo -e "${ICON_OK} 다운로드 완료 — ${C_GREEN}크기 일치${C_RESET} (${FW_SIZE})"
else
    echo -e "${ICON_FAIL} ${C_RED}크기 불일치!${C_RESET} local=${LOCAL_SIZE} remote=${REMOTE_SIZE}"
    exit 1
fi

# ── Step 4: sysupgrade 실행 ──
echo ""
echo -e "${ICON_WARN} ${C_YELLOW}sysupgrade ${SYSUPGRADE_OPTS} 실행 시 AP 재부팅${C_RESET}"
echo -ne "   진행? [y/N]: "
read -r confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo -e "${C_DIM}   → /tmp/${FW_FILE} AP에 대기 중. 수동: sysupgrade /tmp/${FW_FILE}${C_RESET}"
    echo -e "${ICON_OK} 다운로드까지만 완료"
    exit 0
fi

echo -e "${ICON_RUN} [4/4] ${C_RED}sysupgrade ${SYSUPGRADE_OPTS}${C_RESET}"
ssh "root@${AP_IP}" "sysupgrade ${SYSUPGRADE_OPTS} /tmp/${FW_FILE}" &
UPGRADE_PID=$!

echo -ne "${C_DIM}   업그레이드 진행 중"
for i in $(seq 1 10); do
    sleep 2
    echo -ne "."
    if ! kill -0 "$UPGRADE_PID" 2>/dev/null; then
        break
    fi
done
echo -e "${C_RESET}"

echo ""
echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${ICON_OK}  ${C_GREEN}펌웨어 전송 완료 — AP 재부팅 대기${C_RESET}"
echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

# 재부팅 완료 대기
echo -ne "${C_DIM}   AP 부팅 대기"
for i in $(seq 1 45); do
    sleep 2
    if ping -c1 -W1 "$AP_IP" &>/dev/null; then
        echo -e "${C_RESET}"
        echo -e "${ICON_OK} ${C_GREEN}AP 부팅 완료!${C_RESET} ($(( i * 2 ))초)"
        sleep 3
        AP_VER=$(ssh -o ConnectTimeout=3 "root@${AP_IP}" "cat /etc/openwrt_version 2>/dev/null || cat /etc/davo_version 2>/dev/null" 2>/dev/null)
        [ -n "$AP_VER" ] && echo -e "   버전: ${C_CYAN}${AP_VER}${C_RESET}"
        echo ""
        exit 0
    fi
    echo -ne "."
done
echo -e "${C_RESET}"
echo -e "${ICON_WARN} ${C_YELLOW}90초 초과 — 수동 확인 필요${C_RESET}"
echo ""
