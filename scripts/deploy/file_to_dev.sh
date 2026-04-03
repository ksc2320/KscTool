#!/bin/bash
# ============================================================================
#  file_to_dev.sh — HTTP 서버 → AP 파일 전송 백엔드
# ============================================================================
#  dv up / dv file (dv_ext.sh) 에서 호출됨.
#  ~/.dv_up.conf 에서 설정 읽음. CLI 인자로 override 가능.
#
#  사용법:
#    file_to_dev.sh [AP_IP] [OPTIONS]
#      --file  FILE    전송할 파일명 (DVUP_TFTP_PATH 기준, 필수)
#      --upgrade       전송 후 sysupgrade 실행
#      -n              sysupgrade -n (설정 초기화)
#      --serial DEV    시리얼 디바이스 강제 지정
#      --login         로그인 시퀀스 실행 (기본 off)
#      --dry           dry-run (명령만 출력, 실제 전송 없음)
#      -h | --help
# ============================================================================

# ── 컬러 정의 ─────────────────────────────────────────────────────────────
readonly _C_RED='\033[1;31m'
readonly _C_GREEN='\033[1;32m'
readonly _C_YELLOW='\033[1;33m'
readonly _C_CYAN='\033[1;36m'
readonly _C_MAGENTA='\033[1;35m'
readonly _C_WHITE='\033[1;37m'
readonly _C_DIM='\033[0;90m'
readonly _C_RESET='\033[0m'
readonly _C_BOLD='\033[1m'
readonly _C_SKY='\033[0;36m'

readonly _OK="${_C_GREEN}✔${_C_RESET}"
readonly _FAIL="${_C_RED}✘${_C_RESET}"
readonly _RUN="${_C_CYAN}▶${_C_RESET}"
readonly _WARN="${_C_YELLOW}⚠${_C_RESET}"
readonly _CLIP="${_C_YELLOW}📋${_C_RESET}"

# ── 기본 설정값 (conf가 없을 때 fallback) ─────────────────────────────────
DVUP_TFTP_PATH="/tftpboot"
DVUP_SERVER_IP="auto"
DVUP_HTTP_PORT="80"
DVUP_AP_IP="auto"
DVUP_SERIAL_DEV="auto"
DVUP_AUTO_LOGIN="off"
DVUP_LOGIN_USER="root"
DVUP_LOGIN_PASS=""
DVUP_MANAGE_HTTP="off"
DVUP_SYSUPGRADE_OPTS=""

CONF_FILE="$HOME/.dv_up.conf"
LOG_FILE="$HOME/.dv_up.log"

# ── conf 로드 ──────────────────────────────────────────────────────────────
if [ -f "$CONF_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
else
    echo -e "${_WARN} ${_C_YELLOW}~/.dv_up.conf 없음 — 기본값으로 실행${_C_RESET}"
    echo -e "${_C_DIM}   → dv_up_install.sh 실행 권장${_C_RESET}"
fi

# ── CLI 파싱 ──────────────────────────────────────────────────────────────
FILE_NAME=""
DO_UPGRADE=0
UPGRADE_N=0
SERIAL_OVERRIDE=""
DO_LOGIN=0
DRY_RUN=0
AP_IP_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --file)    FILE_NAME="$2";       shift 2 ;;
        --upgrade) DO_UPGRADE=1;         shift   ;;
        -n)        UPGRADE_N=1;          shift   ;;
        --serial)  SERIAL_OVERRIDE="$2"; shift 2 ;;
        --login)   DO_LOGIN=1;           shift   ;;
        --dry)     DRY_RUN=1;            shift   ;;
        -h|--help) _show_help; exit 0             ;;
        [0-9]*.*.*.*) AP_IP_ARG="$1";   shift   ;;
        *) shift ;;
    esac
done

_show_help() {
    echo -e "${_C_CYAN}file_to_dev.sh${_C_RESET} — HTTP 서버 → AP 파일 전송"
    echo ""
    echo "  --file FILE    전송할 파일명 (DVUP_TFTP_PATH 기준)"
    echo "  --upgrade      전송 후 sysupgrade 실행"
    echo "  -n             sysupgrade -n (설정 초기화)"
    echo "  --serial DEV   시리얼 디바이스 강제 (ex: /dev/ttyUSB1)"
    echo "  --login        로그인 시퀀스 실행"
    echo "  --dry          dry-run (명령만 표시)"
    echo "  [AP_IP]        AP IP 직접 지정"
    echo ""
    echo "  설정: ~/.dv_up.conf  /  dv up set 으로 변경 가능"
}

# ── 파일 필수 확인 ─────────────────────────────────────────────────────────
if [ -z "$FILE_NAME" ]; then
    echo -e "${_FAIL} ${_C_RED}--file 인자 필요${_C_RESET}"
    exit 1
fi

FW_PATH="${DVUP_TFTP_PATH}/${FILE_NAME}"
if [ ! -f "$FW_PATH" ]; then
    echo -e "${_FAIL} ${_C_RED}파일 없음: ${FW_PATH}${_C_RESET}"
    exit 1
fi

# ── IP 결정 ───────────────────────────────────────────────────────────────
_detect_network() {
    local enx_info
    enx_info=$(ip -4 addr show 2>/dev/null | grep -A2 'enx' | grep 'inet ' | head -1)
    if [ -n "$enx_info" ]; then
        HOST_IP=$(echo "$enx_info" | awk '{print $2}' | cut -d/ -f1)
        DETECTED_AP_IP=$(echo "$HOST_IP" | sed 's/\.[0-9]*$/.254/')
    else
        HOST_IP="$DVUP_SERVER_IP"
        DETECTED_AP_IP="192.168.1.254"
    fi
}
_detect_network

# SERVER_IP: auto면 enx에서 감지, 아니면 conf값 사용
if [ "$DVUP_SERVER_IP" = "auto" ]; then
    SERVER_IP="$HOST_IP"
else
    SERVER_IP="$DVUP_SERVER_IP"
fi

# AP_IP: CLI > conf > auto감지
if [ -n "$AP_IP_ARG" ]; then
    AP_IP="$AP_IP_ARG"
elif [ "$DVUP_AP_IP" != "auto" ]; then
    AP_IP="$DVUP_AP_IP"
else
    AP_IP="$DETECTED_AP_IP"
fi

HTTP_PORT="$DVUP_HTTP_PORT"

# sysupgrade 옵션
SYSUPGRADE_OPTS="$DVUP_SYSUPGRADE_OPTS"
[ $UPGRADE_N -eq 1 ] && SYSUPGRADE_OPTS="${SYSUPGRADE_OPTS} -n"
SYSUPGRADE_OPTS=$(echo "$SYSUPGRADE_OPTS" | xargs)  # trim

# ── HTTP 서버 확인 ─────────────────────────────────────────────────────────
_check_http_server() {
    if curl -s --connect-timeout 2 \
        "http://${SERVER_IP}:${HTTP_PORT}/${FILE_NAME}" \
        -o /dev/null -w "%{http_code}" 2>/dev/null | grep -q "200"; then
        return 0
    fi
    return 1
}

_start_http_server() {
    python3 -m http.server --directory "${DVUP_TFTP_PATH}" "${HTTP_PORT}" \
        &>/dev/null &
    HTTP_MGR_PID=$!
    sleep 1
    kill -0 "$HTTP_MGR_PID" 2>/dev/null && return 0
    return 1
}

# ── 시리얼 감지 ───────────────────────────────────────────────────────────
_detect_serial() {
    local target_dev="$1"   # 지정 디바이스 or "auto"
    local candidates=()

    if [ "$target_dev" = "auto" ]; then
        candidates=(/dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2)
    else
        candidates=("$target_dev")
    fi

    for dev in "${candidates[@]}"; do
        [ -c "$dev" ] || continue
        if python3 -c "
import serial, sys
try:
    s = serial.Serial('$dev', 115200, timeout=0.5)
    s.close()
    sys.exit(0)
except:
    sys.exit(1)
" 2>/dev/null; then
            SERIAL_DEV_FOUND="$dev"
            return 0
        fi
    done
    SERIAL_DEV_FOUND=""
    return 1
}

# ── 헤더 출력 ─────────────────────────────────────────────────────────────
_print_header() {
    local fw_size fw_date mode_tag enx_if enx_tag

    fw_size=$(du -h "$FW_PATH" | awk '{print $1}')
    fw_date=$(stat -c '%y' "$FW_PATH" | cut -d. -f1)
    enx_if=$(ip link show 2>/dev/null | grep -oE 'enx[a-f0-9]+' | head -1)
    [ -n "$enx_if" ] && enx_tag="${_C_DIM} (${enx_if})${_C_RESET}" || enx_tag=""

    if [ -n "$SERIAL_DEV_FOUND" ]; then
        mode_tag="${_C_GREEN}시리얼${_C_RESET} ${_C_DIM}${SERIAL_DEV_FOUND}${_C_RESET}"
    else
        mode_tag="${_C_YELLOW}클립보드${_C_RESET} ${_C_DIM}(SecureCRT에서 붙여넣기)${_C_RESET}"
    fi

    local dry_tag=""
    [ $DRY_RUN -eq 1 ] && dry_tag=" ${_C_MAGENTA}[DRY-RUN]${_C_RESET}"

    echo ""
    echo -e "${_C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
    echo -e "  ${_C_BOLD}${_C_WHITE}file_to_dev${_C_RESET}${dry_tag}"
    echo -e "${_C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
    echo -e "  File  : ${_C_YELLOW}${FILE_NAME}${_C_RESET} ${_C_DIM}(${fw_size}, ${fw_date})${_C_RESET}"
    echo -e "  AP    : ${_C_YELLOW}${AP_IP}${_C_RESET}${enx_tag}"
    echo -e "  Host  : ${_C_YELLOW}${SERVER_IP}:${HTTP_PORT}${_C_RESET}"
    echo -e "  Mode  : ${mode_tag}"
    [ $DO_UPGRADE -eq 1 ] && echo -e "  Upg   : ${_C_GREEN}sysupgrade${_C_RESET} ${_C_DIM}${SYSUPGRADE_OPTS:-(옵션 없음)}${_C_RESET}"
    [ $DO_LOGIN  -eq 1 ] && echo -e "  Login : ${_C_GREEN}on${_C_RESET} ${_C_DIM}(user: ${DVUP_LOGIN_USER})${_C_RESET}"
    echo -e "${_C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
    echo ""
}

# ── dry-run 시 명령만 출력 ────────────────────────────────────────────────
_print_dry_run() {
    local wget_url="http://${SERVER_IP}:${HTTP_PORT}/${FILE_NAME}"
    echo -e "${_C_MAGENTA}[DRY-RUN] 실제 전송 없이 명령 미리보기${_C_RESET}"
    echo ""
    [ $DO_LOGIN -eq 1 ] && \
        echo -e "  ${_C_DIM}① 로그인: ${DVUP_LOGIN_USER} / (패스워드 conf)${_C_RESET}"
    echo -e "  ${_C_SKY}② wget${_C_RESET}  : cd /tmp && wget ${wget_url} -O ${FILE_NAME}"
    [ $DO_UPGRADE -eq 1 ] && \
        echo -e "  ${_C_SKY}③ upgrade${_C_RESET}: sysupgrade ${SYSUPGRADE_OPTS} /tmp/${FILE_NAME}"
    echo ""
}

# ── 시리얼: 명령 전송 + 결과 대기 ────────────────────────────────────────
_serial_send_wget() {
    local dev="$1" cmd="$2"
    local result
    result=$(python3 -c "
import serial, time, sys

ser = serial.Serial('${dev}', 115200, timeout=1)
time.sleep(0.3)

# 프롬프트 확인 엔터
ser.write(b'\r')
time.sleep(0.5)
ser.read(ser.in_waiting)

# 명령 전송
ser.write('${cmd}\r'.encode())

output = ''
start = time.time()
while time.time() - start < 120:
    data = ser.read(ser.in_waiting or 1)
    if data:
        text = data.decode('utf-8', errors='ignore')
        output += text
        sys.stderr.write(text)
        if '100%' in output and ('#' in output.split('100%')[-1] or '\$' in output.split('100%')[-1]):
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
    echo "$result"
}

_serial_send_cmd() {
    local dev="$1" cmd="$2" wait="${3:-2}"
    python3 -c "
import serial, time
ser = serial.Serial('${dev}', 115200, timeout=1)
ser.write(b'\r')
time.sleep(0.3)
ser.write('${cmd}\r'.encode())
time.sleep(${wait})
ser.close()
" 2>/dev/null
}

# ── 시리얼: 로그인 시퀀스 ─────────────────────────────────────────────────
_serial_do_login() {
    local dev="$1"
    echo -e "${_RUN} 로그인 시퀀스..."
    python3 -c "
import serial, time, sys

ser = serial.Serial('${dev}', 115200, timeout=1)
time.sleep(0.3)
ser.write(b'\r\n')
time.sleep(0.5)
buf = ser.read(ser.in_waiting).decode('utf-8', errors='ignore')
if 'login' in buf.lower():
    ser.write('${DVUP_LOGIN_USER}\r'.encode())
    time.sleep(0.5)
    pw = '${DVUP_LOGIN_PASS}'
    if pw:
        buf2 = ser.read(ser.in_waiting).decode('utf-8', errors='ignore')
        if 'password' in buf2.lower() or 'assword' in buf2.lower():
            ser.write((pw+'\r').encode())
            time.sleep(0.5)
ser.close()
print('LOGIN_DONE')
" 2>/dev/null
}

# ── 부팅 대기 ─────────────────────────────────────────────────────────────
_wait_boot() {
    echo -ne "${_C_DIM}   AP 부팅 대기"
    for i in $(seq 1 50); do
        sleep 2
        if ping -c1 -W1 "$AP_IP" &>/dev/null; then
            echo -e "${_C_RESET}"
            echo -e "${_OK} ${_C_GREEN}AP 부팅 완료!${_C_RESET} (${i}초×2 = $(( i * 2 ))초)"
            echo ""
            return 0
        fi
        echo -ne "."
    done
    echo -e "${_C_RESET}"
    echo -e "${_WARN} ${_C_YELLOW}100초 초과 — 수동 확인 필요${_C_RESET}"
}

# ── AP ping pre-check ─────────────────────────────────────────────────────
_ping_ap_check() {
    echo -e "${_RUN} AP ping 확인 (${AP_IP})..."
    if ping -c1 -W2 "$AP_IP" &>/dev/null; then
        echo -e "${_OK} AP 응답 확인"
    else
        echo -e "${_WARN} ${_C_YELLOW}AP 응답 없음 — 계속 진행할까요? [y/N]${_C_RESET} "
        read -r ans
        [[ ! "$ans" =~ ^[yY]$ ]] && exit 0
    fi
}

# ── 로그 기록 ─────────────────────────────────────────────────────────────
_log_result() {
    local status="$1"   # OK / FAIL / CLIP
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    [ -w "$LOG_FILE" ] || touch "$LOG_FILE" 2>/dev/null || return
    printf "%-20s %-8s %-36s %-16s %s\n" \
        "$ts" "$status" "$FILE_NAME" "$AP_IP" "${SYSUPGRADE_OPTS:--}" \
        >> "$LOG_FILE"
}

# ══════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════

# 시리얼 감지 (serial override 처리)
_target_serial="${SERIAL_OVERRIDE:-${DVUP_SERIAL_DEV}}"
SERIAL_DEV_FOUND=""
if [ "$_target_serial" != "off" ]; then
    _detect_serial "$_target_serial"
fi

# 헤더
_print_header

# dry-run 이면 여기서 종료
if [ $DRY_RUN -eq 1 ]; then
    _print_dry_run
    exit 0
fi

# ── Step 1: AP ping ─────────────────────────────────────────────────────
_ping_ap_check

echo ""

# ── Step 2: HTTP 서버 확인 ──────────────────────────────────────────────
echo -e "${_RUN} ${_C_BOLD}[1/3]${_C_RESET} HTTP 서버 확인..."

if _check_http_server; then
    echo -e "${_OK} http://${SERVER_IP}:${HTTP_PORT}/${FILE_NAME} 접근 가능"
else
    if [ "$DVUP_MANAGE_HTTP" = "on" ]; then
        echo -e "${_C_DIM}   HTTP 서버 없음 → 자동 시작 (:${HTTP_PORT})${_C_RESET}"
        if _start_http_server; then
            echo -e "${_OK} HTTP 서버 시작 완료 (:${HTTP_PORT})"
        else
            echo -e "${_FAIL} ${_C_RED}HTTP 서버 시작 실패${_C_RESET}"
            _log_result "FAIL"
            exit 1
        fi
    else
        echo -e "${_FAIL} ${_C_RED}HTTP 서버 접근 불가 (${SERVER_IP}:${HTTP_PORT})${_C_RESET}"
        echo -e "${_C_DIM}   → 서버 확인 또는 DVUP_MANAGE_HTTP=on 으로 설정 (dv up set)${_C_RESET}"
        _log_result "FAIL"
        exit 1
    fi
fi

echo ""

# ── 명령 구성 ───────────────────────────────────────────────────────────
WGET_URL="http://${SERVER_IP}:${HTTP_PORT}/${FILE_NAME}"
CMD_WGET="cd /tmp && wget ${WGET_URL} -O ${FILE_NAME}"
CMD_UPGRADE="sysupgrade ${SYSUPGRADE_OPTS} /tmp/${FILE_NAME}"

# ══════════════════════════════════════════════════════════════════════════
# 모드 분기: 시리얼 vs 클립보드
# ══════════════════════════════════════════════════════════════════════════
if [ -n "$SERIAL_DEV_FOUND" ]; then
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    #  시리얼 모드
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    # 로그인
    if [ $DO_LOGIN -eq 1 ]; then
        _serial_do_login "$SERIAL_DEV_FOUND"
        echo -e "${_OK} 로그인 완료"
        echo ""
    fi

    echo -e "${_RUN} ${_C_BOLD}[2/3]${_C_RESET} wget 전송 (${SERIAL_DEV_FOUND})..."
    echo -e "${_C_DIM}   ${CMD_WGET}${_C_RESET}"

    WGET_RESULT=$(_serial_send_wget "$SERIAL_DEV_FOUND" "$CMD_WGET")

    if echo "$WGET_RESULT" | grep -q "WGET_OK"; then
        echo -e "${_OK} ${_C_GREEN}다운로드 완료${_C_RESET}"
    elif echo "$WGET_RESULT" | grep -q "WGET_FAIL"; then
        echo -e "${_FAIL} ${_C_RED}wget 실패 (접속 거부 또는 주소 오류)${_C_RESET}"
        _log_result "FAIL"
        exit 1
    else
        echo -e "${_WARN} ${_C_YELLOW}응답 불확실 — 시리얼 출력 확인 필요${_C_RESET}"
    fi

    echo ""

    # sysupgrade
    if [ $DO_UPGRADE -eq 1 ]; then
        echo -e "${_WARN} ${_C_YELLOW}sysupgrade 실행 시 AP 재부팅됩니다${_C_RESET}"
        [ -n "$SYSUPGRADE_OPTS" ] && \
            echo -e "  ${_C_RED}옵션: ${SYSUPGRADE_OPTS}${_C_RESET}"
        echo -ne "   진행? [y/N]: "
        read -r confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            echo -e "${_OK} wget까지만 완료. sysupgrade 취소."
            _log_result "CLIP"
            exit 0
        fi

        echo -e "${_RUN} ${_C_BOLD}[3/3]${_C_RESET} ${_C_RED}sysupgrade 전송...${_C_RESET}"
        _serial_send_cmd "$SERIAL_DEV_FOUND" "$CMD_UPGRADE" 2

        echo ""
        echo -e "${_C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
        echo -e "${_OK}  ${_C_GREEN}sysupgrade 전송 완료 — AP 재부팅 중${_C_RESET}"
        echo -e "${_C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
        echo ""
        _log_result "OK"
        _wait_boot
    else
        echo -e "${_C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
        echo -e "${_OK}  ${_C_GREEN}파일 전송 완료${_C_RESET} — /tmp/${FILE_NAME}"
        echo -e "${_C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
        echo ""
        _log_result "OK"
    fi

else
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    #  클립보드 모드
    # ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    echo -e "${_RUN} ${_C_BOLD}[2/3]${_C_RESET} 시리얼 사용 불가 → ${_C_YELLOW}클립보드 모드${_C_RESET}"
    echo ""

    # wget 클립보드 복사
    echo -e "${_C_WHITE}  ┌─ Step 1: wget (파일 다운로드)${_C_RESET}"
    echo -e "${_C_SKY}  │ ${CMD_WGET}${_C_RESET}"
    echo -e "${_C_WHITE}  └──────────────────────────────────────${_C_RESET}"
    echo ""
    echo "$CMD_WGET" | xclip -selection clipboard 2>/dev/null \
        && echo -e "${_CLIP} ${_C_GREEN}클립보드 복사 완료${_C_RESET} — SecureCRT에서 ${_C_WHITE}Ctrl+V${_C_RESET}" \
        || echo -e "${_WARN} xclip 없음 — 위 명령 수동 복사"

    if [ $DO_UPGRADE -eq 1 ]; then
        echo ""
        echo -ne "   wget 완료 후 Enter 누르세요... "
        read -r

        echo ""
        echo -e "${_C_WHITE}  ┌─ Step 2: sysupgrade${_C_RESET}"
        echo -e "${_C_RED}  │ ${CMD_UPGRADE}${_C_RESET}"
        echo -e "${_C_WHITE}  └──────────────────────────────────────${_C_RESET}"
        echo ""
        echo "$CMD_UPGRADE" | xclip -selection clipboard 2>/dev/null \
            && echo -e "${_CLIP} ${_C_GREEN}클립보드 복사 완료${_C_RESET} — SecureCRT에서 붙여넣기" \
            || echo -e "${_WARN} 위 명령 수동 복사"
    fi

    echo ""
    echo -e "${_C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
    echo -e "${_OK}  ${_C_GREEN}완료${_C_RESET} — SecureCRT에서 붙여넣기하세요"
    echo -e "${_C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
    echo ""
    _log_result "CLIP"
fi
