#!/bin/bash
# ============================================================================
#  fw_deploy.sh — 펌웨어 빌드 → AP 자동 업데이트
# ============================================================================
#  기존 플로우: dv cp fw → SecureCRT wget 버튼 → 수동 sysupgrade
#  개선 플로우: dv cp fw → ./fw_deploy.sh → 자동 wget + sysupgrade
#
#  사용법:
#    ./fw_deploy.sh              # 기본 AP_IP 사용
#    ./fw_deploy.sh 172.30.1.1   # AP IP 지정
#    ./fw_deploy.sh -n           # sysupgrade -n (설정 초기화)
#    ./fw_deploy.sh 172.30.1.1 -n
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

# ── 설정 (본인 환경에 맞게 수정) ──
DEFAULT_AP_IP="172.30.1.1"
HOST_IP="172.30.1.3"
HTTP_PORT="8080"
FW_NAME="fw_609h.img"
TFTP_DIR="/tftpboot"
SYSUPGRADE_OPTS=""          # -n 추가 시 설정 초기화

# ── 인자 파싱 ──
AP_IP="${DEFAULT_AP_IP}"
for arg in "$@"; do
    case "$arg" in
        -n) SYSUPGRADE_OPTS="-n" ;;
        -h|--help)
            echo -e "${C_CYAN}fw_deploy.sh${C_RESET} — AP 펌웨어 자동 배포"
            echo ""
            echo -e "  ${C_WHITE}사용법:${C_RESET}"
            echo "    ./fw_deploy.sh              # 기본 IP ($DEFAULT_AP_IP)"
            echo "    ./fw_deploy.sh 172.30.1.1   # AP IP 지정"
            echo "    ./fw_deploy.sh -n           # 설정 초기화 업그레이드"
            echo ""
            echo -e "  ${C_WHITE}사전 조건:${C_RESET}"
            echo "    1. dv cp fw 로 tftpboot에 이미지 복사 완료"
            echo "    2. startserver 실행 중 (python3 http.server :8080)"
            echo "    3. AP SSH 접속 가능 (root@AP_IP)"
            exit 0
            ;;
        [0-9]*)  AP_IP="$arg" ;;
    esac
done

# ── 헤더 ──
echo ""
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${ICON_FW}  ${C_WHITE}FW Deploy${C_RESET} — AP 펌웨어 자동 배포"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  AP   : ${C_YELLOW}${AP_IP}${C_RESET}"
echo -e "  Host : ${C_YELLOW}${HOST_IP}:${HTTP_PORT}${C_RESET}"
echo -e "  FW   : ${C_YELLOW}${FW_NAME}${C_RESET}"
[ -n "$SYSUPGRADE_OPTS" ] && echo -e "  Opts : ${C_RED}${SYSUPGRADE_OPTS} (설정 초기화)${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo ""

# ── Step 1: 로컬 펌웨어 파일 확인 ──
echo -e "${ICON_RUN} [1/5] 로컬 펌웨어 파일 확인..."
FW_PATH="${TFTP_DIR}/${FW_NAME}"
if [ ! -f "$FW_PATH" ]; then
    echo -e "${ICON_FAIL} ${C_RED}파일 없음: ${FW_PATH}${C_RESET}"
    echo -e "${C_DIM}   → 먼저 'dv cp fw' 실행 필요${C_RESET}"
    exit 1
fi
FW_SIZE=$(du -h "$FW_PATH" | awk '{print $1}')
FW_DATE=$(stat -c '%y' "$FW_PATH" | cut -d. -f1)
echo -e "${ICON_OK} ${C_GREEN}${FW_NAME}${C_RESET} (${C_WHITE}${FW_SIZE}${C_RESET}, ${C_DIM}${FW_DATE}${C_RESET})"

# ── Step 2: HTTP 서버 확인 ──
echo -e "${ICON_RUN} [2/5] HTTP 서버 확인 (${HOST_IP}:${HTTP_PORT})..."
if curl -s --connect-timeout 2 "http://${HOST_IP}:${HTTP_PORT}/${FW_NAME}" -o /dev/null -w "%{http_code}" | grep -q "200"; then
    echo -e "${ICON_OK} HTTP 서버 정상 — 파일 접근 가능"
else
    echo -e "${ICON_WARN} ${C_YELLOW}HTTP 서버 응답 없음${C_RESET}"
    echo -e "${C_DIM}   → 'startserver' 실행 중인지 확인${C_RESET}"
    echo -ne "   자동으로 시작할까요? [y/N]: "
    read -r ans
    if [[ "$ans" =~ ^[yY]$ ]]; then
        echo -e "${ICON_RUN} HTTP 서버 시작..."
        python3 -m http.server --directory "${TFTP_DIR}" "${HTTP_PORT}" &>/dev/null &
        HTTP_PID=$!
        sleep 1
        if kill -0 "$HTTP_PID" 2>/dev/null; then
            echo -e "${ICON_OK} HTTP 서버 시작 완료 (PID: ${HTTP_PID})"
        else
            echo -e "${ICON_FAIL} ${C_RED}HTTP 서버 시작 실패${C_RESET}"
            exit 1
        fi
    else
        echo -e "${ICON_FAIL} 중단"
        exit 1
    fi
fi

# ── Step 3: AP SSH 접속 확인 ──
echo -e "${ICON_RUN} [3/5] AP SSH 접속 확인 (${AP_IP})..."
if ssh -o ConnectTimeout=3 -o BatchMode=yes "root@${AP_IP}" "echo ok" &>/dev/null; then
    echo -e "${ICON_OK} SSH 연결 정상"
else
    echo -e "${ICON_FAIL} ${C_RED}SSH 접속 실패: root@${AP_IP}${C_RESET}"
    echo -e "${C_DIM}   → AP 전원/네트워크 확인, SSH 키 등록 여부 확인${C_RESET}"
    exit 1
fi

# ── Step 4: AP에서 wget 다운로드 ──
WGET_URL="http://${HOST_IP}:${HTTP_PORT}/${FW_NAME}"
echo -e "${ICON_RUN} [4/5] AP에서 펌웨어 다운로드..."
echo -e "${C_DIM}   wget ${WGET_URL}${C_RESET}"

ssh "root@${AP_IP}" "cd /tmp && rm -f ${FW_NAME} && wget -q '${WGET_URL}'" 2>&1
if [ $? -ne 0 ]; then
    echo -e "${ICON_FAIL} ${C_RED}wget 실패${C_RESET}"
    exit 1
fi

# 파일 크기 비교 검증
REMOTE_SIZE=$(ssh "root@${AP_IP}" "wc -c < /tmp/${FW_NAME}" 2>/dev/null | tr -d ' ')
LOCAL_SIZE=$(wc -c < "$FW_PATH" | tr -d ' ')
if [ "$REMOTE_SIZE" == "$LOCAL_SIZE" ]; then
    echo -e "${ICON_OK} 다운로드 완료 — ${C_GREEN}크기 일치${C_RESET} (${FW_SIZE})"
else
    echo -e "${ICON_FAIL} ${C_RED}크기 불일치!${C_RESET} local=${LOCAL_SIZE} remote=${REMOTE_SIZE}"
    exit 1
fi

# ── Step 5: sysupgrade 실행 ──
echo ""
echo -e "${ICON_WARN} ${C_YELLOW}sysupgrade 실행 시 AP가 재부팅됩니다${C_RESET}"
echo -ne "   진행할까요? [y/N]: "
read -r confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    echo -e "${C_DIM}   → /tmp/${FW_NAME} 은 AP에 남아있음. 수동 sysupgrade 가능${C_RESET}"
    echo -e "${ICON_OK} 다운로드까지만 완료"
    exit 0
fi

echo -e "${ICON_RUN} [5/5] ${C_RED}sysupgrade ${SYSUPGRADE_OPTS} 실행 중...${C_RESET}"
ssh "root@${AP_IP}" "sysupgrade ${SYSUPGRADE_OPTS} /tmp/${FW_NAME}" &
UPGRADE_PID=$!

# 업그레이드 진행 표시
echo -ne "${C_DIM}   업그레이드 진행 중"
for i in $(seq 1 10); do
    sleep 2
    echo -ne "."
    # SSH 끊기면 (AP 재부팅) 완료로 판단
    if ! kill -0 "$UPGRADE_PID" 2>/dev/null; then
        break
    fi
done
echo -e "${C_RESET}"

echo ""
echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${ICON_OK}  ${C_GREEN}펌웨어 전송 완료 — AP 재부팅 대기${C_RESET}"
echo -e "${C_DIM}   약 60~90초 후 AP 접속 가능${C_RESET}"
echo -e "${C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo ""

# 선택: 재부팅 완료 대기
echo -ne "재부팅 완료 대기할까요? [y/N]: "
read -r wait_ans
if [[ "$wait_ans" =~ ^[yY]$ ]]; then
    echo -ne "${C_DIM}   AP 재부팅 대기"
    for i in $(seq 1 45); do
        sleep 2
        if ping -c1 -W1 "$AP_IP" &>/dev/null; then
            echo -e "${C_RESET}"
            echo -e "${ICON_OK} ${C_GREEN}AP 부팅 완료!${C_RESET} ($(( i * 2 ))초)"
            # 버전 확인
            sleep 3
            AP_VER=$(ssh -o ConnectTimeout=3 "root@${AP_IP}" "cat /etc/openwrt_version 2>/dev/null || cat /etc/davo_version 2>/dev/null" 2>/dev/null)
            [ -n "$AP_VER" ] && echo -e "   버전: ${C_CYAN}${AP_VER}${C_RESET}"
            exit 0
        fi
        echo -ne "."
    done
    echo -e "${C_RESET}"
    echo -e "${ICON_WARN} ${C_YELLOW}90초 초과 — 수동 확인 필요${C_RESET}"
fi
