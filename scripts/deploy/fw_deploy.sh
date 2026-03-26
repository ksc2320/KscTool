#!/bin/bash
# ============================================================================
#  fw_deploy.sh — 펌웨어 빌드 → AP 자동 업데이트 (시리얼/클립보드)
# ============================================================================
#  기존 플로우: dv cp fw → SecureCRT → wget 버튼 → sysupgrade
#  개선 플로우: dv cp fw → fwd → 시리얼 자동 전송 or 클립보드 복사
#
#  사용법:
#    fwd                    # 자동 감지 (enx IP, FW, 포트)
#    fwd 172.30.2.254       # AP IP 지정 (wget URL에 반영)
#    fwd -n                 # sysupgrade -n (설정 초기화)
#    fwd -p 80              # HTTP 포트 지정
#    fwd -d /dev/ttyUSB1    # 시리얼 디바이스 지정
#    fwd -c                 # 클립보드 모드 강제 (시리얼 안 씀)
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
readonly ICON_CLIP="${C_YELLOW}📋${C_RESET}"

# ── enx 인터페이스 기반 자동 감지 ──
detect_from_enx() {
    local enx_info
    enx_info=$(ip -4 addr show 2>/dev/null | grep -A2 'enx' | grep 'inet ' | head -1)
    if [ -n "$enx_info" ]; then
        HOST_IP=$(echo "$enx_info" | awk '{print $2}' | cut -d/ -f1)
        DEFAULT_AP_IP=$(echo "$HOST_IP" | sed 's/\.[0-9]*$/.254/')
    else
        HOST_IP="172.30.1.3"
        DEFAULT_AP_IP="172.30.1.254"
    fi
}
detect_from_enx

# ── 설정 ──
HTTP_PORT=""
TFTP_DIR="${TFTP_PATH:-/tftpboot}"
SYSUPGRADE_OPTS=""
AUTO_FW_NAME="${FW_NAME:-}"
SERIAL_DEV=""                         # 자동 감지
CLIP_MODE=0                           # 1이면 클립보드 모드 강제

# ── 인자 파싱 ──
AP_IP="${DEFAULT_AP_IP}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n) SYSUPGRADE_OPTS="-n"; shift ;;
        -p) HTTP_PORT="$2"; shift 2 ;;
        -d) SERIAL_DEV="$2"; shift 2 ;;
        -c) CLIP_MODE=1; shift ;;
        -h|--help)
            echo -e "${C_CYAN}fw_deploy.sh${C_RESET} — AP 펌웨어 자동 배포"
            echo ""
            echo -e "  ${C_WHITE}사용법:${C_RESET}"
            echo "    fwd                    # 자동 감지"
            echo "    fwd 172.30.2.254       # AP IP 지정"
            echo "    fwd -n                 # 설정 초기화 업그레이드"
            echo "    fwd -p 80              # HTTP 포트 지정"
            echo "    fwd -d /dev/ttyUSB1    # 시리얼 디바이스"
            echo "    fwd -c                 # 클립보드 모드 강제"
            echo ""
            echo -e "  ${C_WHITE}자동 감지:${C_RESET}"
            echo "    AP IP    : enx 인터페이스 서브넷 .254"
            echo "    Host IP  : enx 인터페이스 IP"
            echo "    FW 파일  : \$FW_NAME → tftpboot 최신 .img"
            echo "    HTTP 포트: 8080 → 80 순서 시도"
            echo "    시리얼   : /dev/ttyUSB0~2 자동 탐색"
            echo ""
            echo -e "  ${C_WHITE}동작 모드:${C_RESET}"
            echo "    시리얼 사용 가능 → pyserial로 직접 명령 전송"
            echo "    시리얼 잠김(SecureCRT) → 클립보드 복사 (붙여넣기만)"
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
    [ -n "$HTTP_PORT" ] && return 0
    for port in 8080 80; do
        if curl -s --connect-timeout 1 "http://${HOST_IP}:${port}/" -o /dev/null 2>/dev/null; then
            HTTP_PORT="$port"
            return 0
        fi
    done
    HTTP_PORT="8080"
    return 1
}
detect_http_port
HTTP_DETECTED=$?

# ── 시리얼 디바이스 감지 ──
detect_serial() {
    [ $CLIP_MODE -eq 1 ] && return 1

    if [ -n "$SERIAL_DEV" ]; then
        [ -c "$SERIAL_DEV" ] && return 0
        return 1
    fi

    # ttyUSB0~2 순서로 열 수 있는지 확인
    for dev in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2; do
        if [ -c "$dev" ]; then
            # 포트 열 수 있는지 (SecureCRT가 잡고 있으면 실패)
            if python3 -c "
import serial, sys
try:
    s = serial.Serial('$dev', 115200, timeout=0.5)
    s.close()
    sys.exit(0)
except:
    sys.exit(1)
" 2>/dev/null; then
                SERIAL_DEV="$dev"
                return 0
            fi
        fi
    done
    return 1
}

SERIAL_AVAILABLE=0
detect_serial && SERIAL_AVAILABLE=1

# ── 헤더 ──
ENX_IF=$(ip link show 2>/dev/null | grep -oE 'enx[a-f0-9]+' | head -1)
ENX_TAG=""
[ -n "$ENX_IF" ] && ENX_TAG="${C_DIM} (${ENX_IF})${C_RESET}"

if [ $SERIAL_AVAILABLE -eq 1 ]; then
    MODE_TAG="${C_GREEN}시리얼${C_RESET} ${C_DIM}${SERIAL_DEV}${C_RESET}"
else
    MODE_TAG="${C_YELLOW}클립보드${C_RESET} ${C_DIM}(SecureCRT에서 붙여넣기)${C_RESET}"
fi

echo ""
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${ICON_FW}  ${C_WHITE}FW Deploy${C_RESET} — AP 펌웨어 자동 배포"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  AP   : ${C_YELLOW}${AP_IP}${C_RESET}${ENX_TAG}"
echo -e "  Host : ${C_YELLOW}${HOST_IP}:${HTTP_PORT}${C_RESET}"
echo -e "  FW   : ${C_YELLOW}${FW_FILE}${C_RESET} (${C_WHITE}${FW_SIZE}${C_RESET}, ${C_DIM}${FW_DATE}${C_RESET})"
echo -e "  Mode : ${MODE_TAG}"
[ -n "$SYSUPGRADE_OPTS" ] && echo -e "  Opts : ${C_RED}${SYSUPGRADE_OPTS} (설정 초기화)${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo ""

# ── Step 1: HTTP 서버 확인 + 자동 시작 ──
echo -e "${ICON_RUN} [1/3] HTTP 서버 확인..."
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
        exit 1
    fi
fi

# ── wget + sysupgrade 명령 생성 ──
WGET_URL="http://${HOST_IP}:${HTTP_PORT}/${FW_FILE}"
CMD_WGET="cd /tmp && wget ${WGET_URL} -O ${FW_FILE}"
CMD_UPGRADE="sysupgrade ${SYSUPGRADE_OPTS} /tmp/${FW_FILE}"

# ═══════════════════════════════════════════════════════
# 모드 분기: 시리얼 vs 클립보드
# ═══════════════════════════════════════════════════════

if [ $SERIAL_AVAILABLE -eq 1 ]; then
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    #  시리얼 모드: pyserial 직접 전송
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    echo -e "${ICON_RUN} [2/3] 시리얼로 wget 전송 (${SERIAL_DEV})..."
    echo -e "${C_DIM}   ${CMD_WGET}${C_RESET}"

    # pyserial로 명령 전송 + 응답 대기
    WGET_RESULT=$(python3 -c "
import serial, time, sys

ser = serial.Serial('${SERIAL_DEV}', 115200, timeout=1)
time.sleep(0.3)

# 프롬프트 확인용 엔터
ser.write(b'\r')
time.sleep(0.5)
ser.read(ser.in_waiting)  # 버퍼 비우기

# wget 전송
cmd = '${CMD_WGET}\r'
ser.write(cmd.encode())

# 다운로드 완료 대기 (최대 120초)
output = ''
start = time.time()
while time.time() - start < 120:
    data = ser.read(ser.in_waiting or 1)
    if data:
        text = data.decode('utf-8', errors='ignore')
        output += text
        sys.stderr.write(text)
        # wget 완료 시그널: 프롬프트(#/$) 또는 100%
        if ('100%' in output and ('#' in output.split('100%')[-1] or '\$' in output.split('100%')[-1])):
            break
        if 'bad address' in output.lower() or 'connection refused' in output.lower():
            print('WGET_FAIL')
            ser.close()
            sys.exit(1)
    time.sleep(0.1)

ser.close()
if '100%' in output or 'saved' in output.lower():
    print('WGET_OK')
else:
    print('WGET_TIMEOUT')
" 2>&1)

    if echo "$WGET_RESULT" | grep -q "WGET_OK"; then
        echo ""
        echo -e "${ICON_OK} ${C_GREEN}다운로드 완료${C_RESET}"
    elif echo "$WGET_RESULT" | grep -q "WGET_FAIL"; then
        echo ""
        echo -e "${ICON_FAIL} ${C_RED}wget 실패${C_RESET}"
        exit 1
    else
        echo ""
        echo -e "${ICON_WARN} ${C_YELLOW}응답 불확실 — 시리얼 출력 확인 필요${C_RESET}"
    fi

    # sysupgrade
    echo ""
    echo -e "${ICON_WARN} ${C_YELLOW}sysupgrade 실행 시 AP 재부팅${C_RESET}"
    echo -ne "   진행? [y/N]: "
    read -r confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        echo -e "${ICON_OK} 다운로드까지만 완료"
        exit 0
    fi

    echo -e "${ICON_RUN} [3/3] ${C_RED}sysupgrade 전송${C_RESET}"
    python3 -c "
import serial, time
ser = serial.Serial('${SERIAL_DEV}', 115200, timeout=1)
ser.write(b'\r')
time.sleep(0.3)
ser.write('${CMD_UPGRADE}\r'.encode())
time.sleep(2)
ser.close()
" 2>/dev/null

    echo ""
    echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${ICON_OK}  ${C_GREEN}sysupgrade 전송 완료 — AP 재부팅 중${C_RESET}"
    echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

    # 재부팅 대기
    echo -ne "${C_DIM}   AP 부팅 대기"
    for i in $(seq 1 45); do
        sleep 2
        if ping -c1 -W1 "$AP_IP" &>/dev/null; then
            echo -e "${C_RESET}"
            echo -e "${ICON_OK} ${C_GREEN}AP 부팅 완료!${C_RESET} ($(( i * 2 ))초)"
            echo ""
            exit 0
        fi
        echo -ne "."
    done
    echo -e "${C_RESET}"
    echo -e "${ICON_WARN} ${C_YELLOW}90초 초과 — 수동 확인 필요${C_RESET}"

else
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    #  클립보드 모드: 명령 복사
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    echo -e "${ICON_RUN} [2/3] 시리얼 포트 사용 불가 → ${C_YELLOW}클립보드 모드${C_RESET}"

    # 1단계: wget 명령 클립보드 복사
    echo ""
    echo -e "${C_WHITE}  ┌─ Step 1: wget (펌웨어 다운로드)${C_RESET}"
    echo -e "${C_CYAN}  │ ${CMD_WGET}${C_RESET}"
    echo -e "${C_WHITE}  └─────────────────────────────────${C_RESET}"
    echo ""

    echo "$CMD_WGET" | xclip -selection clipboard 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${ICON_CLIP} ${C_GREEN}클립보드 복사 완료${C_RESET} — SecureCRT에서 ${C_WHITE}Ctrl+V${C_RESET} (또는 우클릭 붙여넣기)"
    else
        echo -e "${ICON_WARN} ${C_YELLOW}xclip 없음 — 위 명령을 수동 복사${C_RESET}"
    fi

    echo ""
    echo -ne "   wget 완료 후 Enter 누르세요... "
    read -r

    # 2단계: sysupgrade 명령 클립보드 복사
    echo ""
    echo -e "${C_WHITE}  ┌─ Step 2: sysupgrade (펌웨어 적용)${C_RESET}"
    echo -e "${C_RED}  │ ${CMD_UPGRADE}${C_RESET}"
    echo -e "${C_WHITE}  └─────────────────────────────────${C_RESET}"
    echo ""

    echo "$CMD_UPGRADE" | xclip -selection clipboard 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${ICON_CLIP} ${C_GREEN}클립보드 복사 완료${C_RESET} — SecureCRT에서 붙여넣기"
    else
        echo -e "${ICON_WARN} ${C_YELLOW}위 명령을 수동 복사${C_RESET}"
    fi

    echo ""
    echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${ICON_OK}  ${C_GREEN}완료${C_RESET} — SecureCRT에서 붙여넣기하세요"
    echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
fi
echo ""
