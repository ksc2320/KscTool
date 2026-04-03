#!/bin/bash
# ============================================================================
#  dv_up_install.sh — dv up / dv file 초기 설치 스크립트
# ============================================================================
#  1. ~/.dv_up.conf 생성 (없으면)
#  2. ~/.dv_up.log 생성 (없으면)
#  3. ~/.bash_functions 끝에 dv_ext.sh source 추가 (없으면)
#  4. ~/.bash_aliases 의 fwd alias → file_to_dev.sh 로 업데이트
#  5. fw_deploy.sh → git mv로 rename (있으면)
#  6. KscTool/dotfiles 백업 디렉토리 생성
#  7. chmod +x 스크립트들
# ============================================================================

set -e

readonly _C_GREEN='\033[1;32m'
readonly _C_RED='\033[1;31m'
readonly _C_YELLOW='\033[1;33m'
readonly _C_CYAN='\033[1;36m'
readonly _C_DIM='\033[0;90m'
readonly _C_RESET='\033[0m'
readonly _C_BOLD='\033[1m'

OK="${_C_GREEN}✔${_C_RESET}"
FAIL="${_C_RED}✘${_C_RESET}"
SKIP="${_C_YELLOW}↷${_C_RESET}"
RUN="${_C_CYAN}▶${_C_RESET}"

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KSCTOOL_DIR="$(cd "${DEPLOY_DIR}/../.." && pwd)"
CONF_FILE="$HOME/.dv_up.conf"
LOG_FILE="$HOME/.dv_up.log"
BASH_FUNCTIONS="$HOME/.bash_functions"
BASH_ALIASES="$HOME/.bash_aliases"
DOTFILES_DIR="${KSCTOOL_DIR}/dotfiles"

echo ""
echo -e "${_C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
echo -e "  ${_C_BOLD}dv up install${_C_RESET} — 초기 설치"
echo -e "${_C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
echo ""

# ── 1. ~/.dv_up.conf ──────────────────────────────────────────────────────
echo -e "${RUN} [1/7] ~/.dv_up.conf 확인..."
if [ -f "$CONF_FILE" ]; then
    echo -e "${SKIP} 이미 존재 — 건드리지 않음 (${_C_DIM}${CONF_FILE}${_C_RESET})"
else
    cat > "$CONF_FILE" << 'CONFEOF'
# ============================================================
#  ~/.dv_up.conf — dv up / dv file 설정
#  dv up set 으로 편집 가능
# ============================================================

# HTTP/TFTP 서버 루트 경로
DVUP_TFTP_PATH='/tftpboot'

# 호스트 IP (AP의 wget URL에 사용)
# auto = enx 인터페이스 IP 자동 감지
DVUP_SERVER_IP='auto'

# HTTP 서버 포트
DVUP_HTTP_PORT='80'

# AP IP
# auto = enx 인터페이스 기반 .254 자동 감지
DVUP_AP_IP='auto'

# 시리얼 디바이스
# auto = /dev/ttyUSB0 → 1 → 2 순 자동 탐색 (잠겨있으면 다음으로)
# /dev/ttyUSBx = 특정 포트 고정
# off = 클립보드 모드 강제
DVUP_SERIAL_DEV='auto'

# 자동 로그인 (on/off)
# off = 로그인 건드리지 않음 (AP에서 이미 로그인 유지 가정)
# on  = wget 전 로그인 시퀀스 자동 실행
DVUP_AUTO_LOGIN='off'
DVUP_LOGIN_USER='root'
DVUP_LOGIN_PASS=''

# HTTP 서버 직접 관리
# off = 이미 실행 중인 서버 사용 (접근 불가 시 에러)
# on  = 서버 없으면 자동 시작
DVUP_MANAGE_HTTP='off'

# sysupgrade 기본 옵션 (ex: -n 으로 항상 설정 초기화)
DVUP_SYSUPGRADE_OPTS=''
CONFEOF
    echo -e "${OK} ~/.dv_up.conf 생성"
fi

# ── 사용자 환경에 맞게 SERVER_IP 업데이트 ─────────────────────────────────
echo -ne "   서버 IP 입력 (auto=enx감지 / 직접입력 / Enter=auto): "
read -r user_ip
if [ -n "$user_ip" ] && [ "$user_ip" != "auto" ]; then
    sed -i "s|^DVUP_SERVER_IP=.*|DVUP_SERVER_IP='${user_ip}'|" "$CONF_FILE"
    echo -e "${OK} DVUP_SERVER_IP = ${_C_GREEN}${user_ip}${_C_RESET}"
else
    echo -e "${SKIP} auto 유지"
fi

echo -ne "   HTTP 포트 (Enter=80): "
read -r user_port
user_port="${user_port:-80}"
sed -i "s|^DVUP_HTTP_PORT=.*|DVUP_HTTP_PORT='${user_port}'|" "$CONF_FILE"
echo -e "${OK} DVUP_HTTP_PORT = ${_C_GREEN}${user_port}${_C_RESET}"

echo -ne "   TFTP 경로 (Enter=/tftpboot): "
read -r user_tftp
user_tftp="${user_tftp:-/tftpboot}"
sed -i "s|^DVUP_TFTP_PATH=.*|DVUP_TFTP_PATH='${user_tftp}'|" "$CONF_FILE"
echo -e "${OK} DVUP_TFTP_PATH = ${_C_GREEN}${user_tftp}${_C_RESET}"
echo ""

# ── 2. ~/.dv_up.log ───────────────────────────────────────────────────────
echo -e "${RUN} [2/7] ~/.dv_up.log 확인..."
if [ -f "$LOG_FILE" ]; then
    echo -e "${SKIP} 이미 존재"
else
    touch "$LOG_FILE"
    printf "%-20s %-8s %-36s %-16s %s\n" \
        "# datetime" "result" "file" "ap_ip" "opts" >> "$LOG_FILE"
    echo -e "${OK} ~/.dv_up.log 생성"
fi

# ── 3. ~/.bash_functions 에 source 추가 ───────────────────────────────────
echo -e "${RUN} [3/7] ~/.bash_functions 에 dv_ext.sh source 추가..."
SOURCE_LINE="[ -f ${DEPLOY_DIR}/dv_ext.sh ] && source ${DEPLOY_DIR}/dv_ext.sh"

if grep -q "dv_ext.sh" "$BASH_FUNCTIONS" 2>/dev/null; then
    echo -e "${SKIP} 이미 등록됨"
else
    echo "" >> "$BASH_FUNCTIONS"
    echo "# dv up / dv file 확장" >> "$BASH_FUNCTIONS"
    echo "${SOURCE_LINE}" >> "$BASH_FUNCTIONS"
    echo -e "${OK} source 줄 추가 완료"
fi

# ── 4. ~/.bash_aliases fwd alias 업데이트 ────────────────────────────────
echo -e "${RUN} [4/7] fwd alias 업데이트..."
NEW_FWD_ALIAS="alias fwd=\"\$HOME/KscTool/scripts/deploy/file_to_dev.sh\""
if grep -q "^alias fwd=" "$BASH_ALIASES" 2>/dev/null; then
    OLD_ALIAS=$(grep "^alias fwd=" "$BASH_ALIASES")
    if echo "$OLD_ALIAS" | grep -q "file_to_dev.sh"; then
        echo -e "${SKIP} 이미 file_to_dev.sh 가리킴"
    else
        sed -i "s|^alias fwd=.*|${NEW_FWD_ALIAS}|" "$BASH_ALIASES"
        echo -e "${OK} fwd alias → file_to_dev.sh 로 변경"
        echo -e "  ${_C_DIM}이전: ${OLD_ALIAS}${_C_RESET}"
    fi
else
    echo "${NEW_FWD_ALIAS}" >> "$BASH_ALIASES"
    echo -e "${OK} fwd alias 추가"
fi

# ── 5. fw_deploy.sh rename ───────────────────────────────────────────────
echo -e "${RUN} [5/7] fw_deploy.sh → file_to_dev.sh rename 확인..."
OLD_SCRIPT="${DEPLOY_DIR}/fw_deploy.sh"
if [ -f "$OLD_SCRIPT" ]; then
    if git -C "$KSCTOOL_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        git -C "$KSCTOOL_DIR" mv \
            "scripts/deploy/fw_deploy.sh" \
            "scripts/deploy/fw_deploy.sh.bak" 2>/dev/null || true
        echo -e "${OK} git mv → fw_deploy.sh.bak (보관)"
    else
        mv "$OLD_SCRIPT" "${OLD_SCRIPT}.bak"
        echo -e "${OK} mv → fw_deploy.sh.bak (보관)"
    fi
else
    echo -e "${SKIP} fw_deploy.sh 없음"
fi

# ── 6. KscTool/dotfiles 백업 구조 ────────────────────────────────────────
echo -e "${RUN} [6/7] KscTool/dotfiles 백업 디렉토리..."
mkdir -p "${DOTFILES_DIR}"

# .dv_up.conf 심볼릭 링크 또는 복사 (백업용)
if [ ! -e "${DOTFILES_DIR}/dv_up.conf.sample" ]; then
    cp "$CONF_FILE" "${DOTFILES_DIR}/dv_up.conf.sample"
    echo -e "${OK} dv_up.conf.sample 생성 (설정 샘플 보관)"
else
    echo -e "${SKIP} dv_up.conf.sample 이미 존재"
fi

# dotfiles README
cat > "${DOTFILES_DIR}/README.md" << 'RDEOF'
# KscTool dotfiles

개인 설정 파일 백업/샘플 보관 디렉토리.

| 파일 | 설명 |
|------|------|
| dv_up.conf.sample | dv up / dv file 설정 샘플 |

## 복원 방법
```bash
cp dv_up.conf.sample ~/.dv_up.conf
# 이후 dv up set 으로 환경에 맞게 수정
```
RDEOF
echo -e "${OK} dotfiles/README.md 생성"

# ── 7. chmod +x ──────────────────────────────────────────────────────────
echo -e "${RUN} [7/7] 실행 권한 설정..."
chmod +x "${DEPLOY_DIR}/file_to_dev.sh" && echo -e "${OK} file_to_dev.sh +x"
chmod +x "${DEPLOY_DIR}/dv_ext.sh"      && echo -e "${OK} dv_ext.sh +x"
chmod +x "${DEPLOY_DIR}/dv_up_install.sh" && echo -e "${OK} dv_up_install.sh +x"

# ── 완료 ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${_C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
echo -e "${OK}  ${_C_GREEN}설치 완료${_C_RESET}"
echo -e "${_C_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_C_RESET}"
echo ""
echo -e "  다음 명령으로 즉시 적용:"
echo -e "  ${_C_CYAN}source ~/.bashrc${_C_RESET}"
echo ""
echo -e "  사용 시작:"
echo -e "  ${_C_CYAN}dv up set${_C_RESET}    → 설정 확인/편집"
echo -e "  ${_C_CYAN}dv up dry${_C_RESET}    → 실제 전송 없이 미리보기"
echo -e "  ${_C_CYAN}dv up${_C_RESET}        → 배포!"
echo -e "  ${_C_CYAN}dv up -h${_C_RESET}     → 전체 도움말"
echo ""
