#!/bin/bash
# ============================================================================
#  file_to_dev.sh — AP 장치 펌웨어/파일 전송 도구 v2.0
# ============================================================================
#  단독 실행:  ./file_to_dev.sh <command> [args]
#  소싱(bash): source file_to_dev.sh  → 함수 등록 + dv 통합
#
#  Commands:
#    init      최초 설치 마법사 (패키지·경로·IP·시리얼·단축어 등록)
#    up        FW 배포 (copy→http check→wget→sysupgrade)
#    up s      fzf로 FW 파일 선택
#    up -n     sysupgrade -n (설정 초기화 포함)
#    up dry    dry-run (명령 미리보기만)
#    file      tftpboot 파일 선택 → AP wget 전송
#    set       설정 편집
#    log       배포 이력 조회
#    doctor    환경 진단 (패키지·설정·서버 상태)
#    help      도움말
#
#  배포: 이 파일 하나만 공유하면 됩니다.
#        git clone 또는 복사 후 → ./file_to_dev.sh init
# ============================================================================

# ── 컬러 ─────────────────────────────────────────────────────────────────
_F_RED='\033[1;31m';  _F_GREEN='\033[1;32m';  _F_YELLOW='\033[1;33m'
_F_CYAN='\033[1;36m'; _F_MAG='\033[1;35m';    _F_WHITE='\033[1;37m'
_F_SKY='\033[0;36m';  _F_DIM='\033[0;90m';    _F_RST='\033[0m'
_F_BOLD='\033[1m';    _F_UL='\033[4m'

_OK="${_F_GREEN}✔${_F_RST}"; _FAIL="${_F_RED}✘${_F_RST}"
_RUN="${_F_CYAN}▶${_F_RST}"; _WARN="${_F_YELLOW}⚠${_F_RST}"
_CLIP="${_F_YELLOW}📋${_F_RST}"

_ln() { echo -e "${_F_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_F_RST}"; }
_hd() { _ln; echo -e "  ${_F_BOLD}${_F_WHITE}$*${_F_RST}"; _ln; }

# ── 설정 경로 ─────────────────────────────────────────────────────────────
FTD_CONF_DIR="$HOME/.config/ftd"
FTD_CONF="${FTD_CONF_DIR}/config"
FTD_LOG="${FTD_CONF_DIR}/history.log"
FTD_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── 기본값 (conf 없을 때 fallback) ───────────────────────────────────────
FTD_FW_MODE='scan'       # dv / path / scan
FTD_FW_DIR=''
FTD_FW_NAME=''           # 빈 문자열=원본명 유지, 고정명 원하면 ex: fw_609h.img
FTD_SCAN_DIRS="$HOME/proj"   # scan 모드 탐색 루트 (공백 구분 다중 경로 가능)
FTD_TFTP_PATH='/tftpboot'
FTD_SERVER_IP='auto'
FTD_HTTP_PORT='80'
FTD_AP_IP='auto'
FTD_SERIAL_DEV='auto'
FTD_AUTO_LOGIN='off'
FTD_LOGIN_USER='root'
FTD_LOGIN_PASS=''
FTD_MANAGE_HTTP='off'
FTD_SYSUPGRADE_OPTS=''
FTD_DV_INTEGRATION='auto'
FTD_ALIAS='ftd'

# ── conf 로드 ─────────────────────────────────────────────────────────────
_ftd_load_conf() {
    [ -f "$FTD_CONF" ] && source "$FTD_CONF" 2>/dev/null
}
_ftd_load_conf

# ── 네트워크 자동 감지 ────────────────────────────────────────────────────
_ftd_detect_network() {
    local enx_info
    enx_info=$(ip -4 addr show 2>/dev/null | grep -A2 'enx' | grep 'inet ' | head -1)
    _DETECTED_ENX_IF=$(ip link show 2>/dev/null | grep -oE 'enx[a-f0-9]+' | head -1)
    if [ -n "$enx_info" ]; then
        _DETECTED_HOST_IP=$(echo "$enx_info" | awk '{print $2}' | cut -d/ -f1)
        _DETECTED_AP_IP=$(echo "$_DETECTED_HOST_IP" | sed 's/\.[0-9]*$/.254/')
    else
        _DETECTED_HOST_IP=""
        _DETECTED_AP_IP=""
    fi
}
_ftd_detect_network

_ftd_server_ip() {
    [ "$FTD_SERVER_IP" = "auto" ] && echo "${_DETECTED_HOST_IP:-127.0.0.1}" || echo "$FTD_SERVER_IP"
}
_ftd_ap_ip() {
    [ "$FTD_AP_IP" = "auto" ] && echo "${_DETECTED_AP_IP:-192.168.1.254}" || echo "$FTD_AP_IP"
}

# ══════════════════════════════════════════════════════════════════════════
#  INIT — 최초 설치 마법사
# ══════════════════════════════════════════════════════════════════════════
_ftd_init() {
    echo ""
    _hd "🚀  file_to_dev  초기 설치 마법사"
    echo -e "  ${_F_DIM}이 스크립트 하나로 팀원 누구나 AP 장치에 파일을 전송할 수 있습니다.${_F_RST}"
    echo ""

    mkdir -p "$FTD_CONF_DIR"

    # ── [1/8] 패키지 확인 ─────────────────────────────────────────────
    echo -e "${_RUN} ${_F_BOLD}[1/8]${_F_RST} 필수 패키지 확인..."
    echo ""
    _ftd_check_pkg python3  "Python 3"
    _ftd_check_pkg pip3     "pip3"         "python3-pip"
    _ftd_check_pkg fzf      "fzf (파일 선택기)"
    _ftd_check_pkg xclip    "xclip (클립보드)"
    _ftd_check_pkg curl     "curl"
    _ftd_check_pyserial
    echo ""

    # ── [2/8] FW 경로 모드 ────────────────────────────────────────────
    echo -e "${_RUN} ${_F_BOLD}[2/8]${_F_RST} FW(펌웨어) 파일 위치 설정"
    echo ""
    echo -e "  ${_F_WHITE}FW 파일을 어떻게 찾을까요?${_F_RST}"
    echo -e "  ${_F_CYAN}1)${_F_RST} dv 환경 사용  ${_F_DIM}(dv cp 처럼 동작 — davolink 개발환경)${_F_RST}"
    echo -e "  ${_F_CYAN}2)${_F_RST} 직접 경로 지정  ${_F_DIM}(FW_DIR / FW_NAME 수동 설정)${_F_RST}"
    echo -e "  ${_F_CYAN}3)${_F_RST} 자동 탐지  ${_F_DIM}(~/proj/**/bin/*.img 탐색)${_F_RST}"
    echo ""

    # dv 환경 자동 감지
    local dv_detected=0
    declare -f send_file_to_tftp &>/dev/null && dv_detected=1

    if [ $dv_detected -eq 1 ]; then
        echo -e "  ${_OK} ${_F_GREEN}dv 환경 감지됨${_F_RST} ${_F_DIM}(send_file_to_tftp 사용 가능)${_F_RST}"
        echo -ne "  선택 (Enter=1): "
    else
        echo -e "  ${_F_DIM}dv 환경 미감지 — 2번 또는 3번 추천${_F_RST}"
        echo -ne "  선택 (Enter=3): "
    fi
    read -r fw_mode_sel
    fw_mode_sel="${fw_mode_sel:-$([ $dv_detected -eq 1 ] && echo 1 || echo 3)}"

    local new_fw_mode new_fw_dir new_fw_name
    case "$fw_mode_sel" in
        1)
            new_fw_mode="dv"
            echo -e "  ${_OK} dv 모드 설정"
            ;;
        2)
            new_fw_mode="path"
            echo -ne "  FW 디렉토리 경로 (ex: ~/proj/13_1/bin/targets/ipq53xx/ipq53xx_32): "
            read -r new_fw_dir
            new_fw_dir="${new_fw_dir/#\~/$HOME}"
            echo -ne "  TFTP 저장 파일명 (ex: fw_609h.img, Enter=원본명 유지): "
            read -r new_fw_name
            echo -e "  ${_OK} path 모드 — ${_F_GREEN}${new_fw_dir}${_F_RST}"
            ;;
        3|*)
            new_fw_mode="scan"
            echo -e "  ${_OK} scan 모드"
            echo -ne "  탐색 루트 경로 (Enter=~/proj, 공백으로 다중 경로 가능): "
            read -r new_scan_dirs
            new_scan_dirs="${new_scan_dirs:-~/proj}"
            echo -ne "  TFTP 저장 파일명 (ex: fw_609h.img, Enter=원본명 유지): "
            read -r new_fw_name
            ;;
    esac
    echo ""

    # ── [3/8] TFTP 경로 ───────────────────────────────────────────────
    echo -e "${_RUN} ${_F_BOLD}[3/8]${_F_RST} TFTP/HTTP 서버 루트 경로"
    echo -e "  ${_F_DIM}AP가 wget으로 파일을 가져올 HTTP 서버의 파일 루트입니다.${_F_RST}"
    echo -ne "  경로 (Enter=/tftpboot): "
    read -r new_tftp
    new_tftp="${new_tftp:-/tftpboot}"
    echo -e "  ${_OK} ${_F_GREEN}${new_tftp}${_F_RST}"
    echo ""

    # ── [4/8] 서버 IP / 포트 ──────────────────────────────────────────
    echo -e "${_RUN} ${_F_BOLD}[4/8]${_F_RST} 호스트(서버) IP & HTTP 포트"
    echo -e "  ${_F_DIM}AP에서 wget할 때 사용할 이 PC의 IP입니다.${_F_RST}"
    if [ -n "$_DETECTED_HOST_IP" ]; then
        echo -e "  ${_F_DIM}enx 인터페이스 감지: ${_DETECTED_HOST_IP}${_F_RST}"
    fi
    echo -ne "  서버 IP (auto=enx 감지 / 직접 입력, Enter=auto): "
    read -r new_server_ip
    new_server_ip="${new_server_ip:-auto}"

    echo -ne "  HTTP 포트 (Enter=80): "
    read -r new_http_port
    new_http_port="${new_http_port:-80}"
    echo -e "  ${_OK} ${_F_GREEN}${new_server_ip}:${new_http_port}${_F_RST}"
    echo ""

    # ── [5/8] HTTP 서버 관리 방식 ─────────────────────────────────────
    echo -e "${_RUN} ${_F_BOLD}[5/8]${_F_RST} HTTP 서버 관리 방식"
    echo ""
    echo -e "  ${_F_CYAN}1)${_F_RST} off   ${_F_DIM}상시 켜진 서버 사용 (건드리지 않음) ← 권장${_F_RST}"
    echo -e "  ${_F_CYAN}2)${_F_RST} auto  ${_F_DIM}없으면 자동 시작, 있으면 그대로 사용${_F_RST}"
    echo -e "  ${_F_CYAN}3)${_F_RST} always ${_F_DIM}실행 시 항상 새로 시작${_F_RST}"
    echo -ne "  선택 (Enter=1): "
    read -r http_mode_sel
    local new_manage_http
    case "${http_mode_sel:-1}" in
        2) new_manage_http="auto" ;;
        3) new_manage_http="always" ;;
        *) new_manage_http="off" ;;
    esac
    echo -e "  ${_OK} ${_F_GREEN}${new_manage_http}${_F_RST}"
    echo ""

    # ── [6/8] 시리얼 포트 ─────────────────────────────────────────────
    echo -e "${_RUN} ${_F_BOLD}[6/8]${_F_RST} 시리얼 포트 설정"
    echo -e "  ${_F_DIM}AP 시리얼 콘솔로 wget 명령을 자동 전송합니다.${_F_RST}"
    echo -e "  ${_F_DIM}SecureCRT가 포트를 점유하면 클립보드 모드로 자동 전환됩니다.${_F_RST}"
    echo ""

    # 사용 가능한 포트 스캔
    local found_devs=()
    for d in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyACM0; do
        [ -c "$d" ] && found_devs+=("$d")
    done

    if [ ${#found_devs[@]} -gt 0 ]; then
        echo -e "  감지된 포트: ${_F_GREEN}${found_devs[*]}${_F_RST}"
    else
        echo -e "  ${_WARN} 시리얼 포트 없음 (클립보드 모드 사용)"
    fi
    echo ""
    echo -e "  ${_F_CYAN}1)${_F_RST} auto   ${_F_DIM}ttyUSB0→1→2 순 자동 탐색${_F_RST}"
    for i in "${!found_devs[@]}"; do
        echo -e "  ${_F_CYAN}$((i+2)))${_F_RST} ${found_devs[$i]}"
    done
    echo -e "  ${_F_CYAN}0)${_F_RST} off    ${_F_DIM}클립보드 모드만 사용${_F_RST}"
    echo -ne "  선택 (Enter=1): "
    read -r serial_sel
    local new_serial
    case "${serial_sel:-1}" in
        0)   new_serial="off" ;;
        1)   new_serial="auto" ;;
        2)   new_serial="${found_devs[0]:-auto}" ;;
        3)   new_serial="${found_devs[1]:-auto}" ;;
        4)   new_serial="${found_devs[2]:-auto}" ;;
        /dev/*) new_serial="$serial_sel" ;;
        *)   new_serial="auto" ;;
    esac
    echo -e "  ${_OK} 시리얼: ${_F_GREEN}${new_serial}${_F_RST}"
    echo ""

    # ── [7/8] 자동 로그인 ─────────────────────────────────────────────
    echo -e "${_RUN} ${_F_BOLD}[7/8]${_F_RST} AP 자동 로그인"
    echo -e "  ${_F_DIM}AP에 이미 로그인되어 있으면 off 권장.${_F_RST}"
    echo -ne "  자동 로그인 (on/off, Enter=off): "
    read -r new_login
    new_login="${new_login:-off}"
    local new_login_user="" new_login_pass=""
    if [ "$new_login" = "on" ]; then
        echo -ne "  유저명 (Enter=root): "
        read -r new_login_user
        new_login_user="${new_login_user:-root}"
        echo -ne "  패스워드 (없으면 Enter): "
        read -rs new_login_pass
        echo ""
        echo -e "  ${_OK} 로그인: ${_F_GREEN}${new_login_user}${_F_RST}"
    else
        echo -e "  ${_OK} off"
    fi
    echo ""

    # ── [8/8] 단축어 등록 ─────────────────────────────────────────────
    echo -e "${_RUN} ${_F_BOLD}[8/8]${_F_RST} 단축어(alias) 등록"
    echo ""
    echo -e "  ${_F_WHITE}추천 단축어:${_F_RST}"
    echo -e "  ${_F_CYAN}ftd${_F_RST}  ${_F_DIM}— file to dev (전용)${_F_RST}"
    echo -e "  ${_F_CYAN}fwd${_F_RST}  ${_F_DIM}— firmware to dev (기존 이름)${_F_RST}"
    echo -e "  ${_F_CYAN}dep${_F_RST}  ${_F_DIM}— deploy${_F_RST}"
    echo -ne "  사용할 단축어 (Enter=ftd): "
    read -r new_alias
    new_alias="${new_alias:-ftd}"

    # shell 파일 선택
    echo ""
    echo -e "  단축어 등록할 파일:"
    echo -e "  ${_F_CYAN}1)${_F_RST} ~/.bash_aliases  ${_F_DIM}← 권장${_F_RST}"
    echo -e "  ${_F_CYAN}2)${_F_RST} ~/.bashrc"
    echo -ne "  선택 (Enter=1): "
    read -r alias_target_sel
    local alias_file
    [ "${alias_target_sel:-1}" = "2" ] && alias_file="$HOME/.bashrc" || alias_file="$HOME/.bash_aliases"

    # dv 통합 여부
    local new_dv_integration="off"
    if declare -f davo_macro_tool &>/dev/null; then
        echo ""
        echo -ne "  dv 명령 통합 (dv up / dv file)? (on/off, Enter=on): "
        read -r dv_intg
        new_dv_integration="${dv_intg:-on}"
    fi
    echo ""

    # ── config 파일 생성 ──────────────────────────────────────────────
    cat > "$FTD_CONF" << CONFEOF
# ============================================================
#  ~/.config/ftd/config — file_to_dev 설정
#  생성: $(date '+%Y-%m-%d %H:%M')
#  편집: ${new_alias} set  또는  직접 편집
# ============================================================

# FW 파일 위치 모드: dv / path / scan
FTD_FW_MODE='${new_fw_mode}'

# FTD_FW_MODE=path 일때 FW 디렉토리
FTD_FW_DIR='${new_fw_dir:-}'

# FTD_FW_MODE=scan 탐색 루트 (공백 구분 다중 경로)
FTD_SCAN_DIRS='${new_scan_dirs:-~/proj}'

# TFTP 저장 파일명 (빈 문자열=원본명 유지, ex: fw_609h.img 으로 고정 시 지정)
FTD_FW_NAME='${new_fw_name:-}'

# TFTP/HTTP 서버 루트 경로
FTD_TFTP_PATH='${new_tftp}'

# 호스트(서버) IP — auto = enx 인터페이스 자동 감지
FTD_SERVER_IP='${new_server_ip}'

# HTTP 포트
FTD_HTTP_PORT='${new_http_port}'

# AP IP — auto = enx 기반 .254 자동 감지
FTD_AP_IP='auto'

# 시리얼: auto / /dev/ttyUSBx / off
FTD_SERIAL_DEV='${new_serial}'

# 자동 로그인: on / off
FTD_AUTO_LOGIN='${new_login}'
FTD_LOGIN_USER='${new_login_user:-root}'
FTD_LOGIN_PASS='${new_login_pass}'

# HTTP 서버 관리: off / auto / always
FTD_MANAGE_HTTP='${new_manage_http}'

# sysupgrade 기본 옵션 (ex: -n)
FTD_SYSUPGRADE_OPTS=''

# dv 명령 통합: on / off
FTD_DV_INTEGRATION='${new_dv_integration}'

# 등록된 단축어
FTD_ALIAS='${new_alias}'
CONFEOF
    chmod 600 "$FTD_CONF"

    # log 초기화
    [ -f "$FTD_LOG" ] || printf "%-20s %-6s %-36s %-16s %s\n" \
        "# datetime" "result" "file" "ap_ip" "opts" > "$FTD_LOG"

    # ── alias 등록 ────────────────────────────────────────────────────
    local alias_line="alias ${new_alias}='${FTD_SELF}'"
    local source_line="[ -f '${FTD_SELF}' ] && source '${FTD_SELF}'"

    if ! grep -q "file_to_dev.sh" "$alias_file" 2>/dev/null; then
        {
            echo ""
            echo "# file_to_dev — AP 파일 전송 도구"
            echo "${alias_line}"
        } >> "$alias_file"
        echo -e "${_OK} ${_F_GREEN}${new_alias}${_F_RST} alias 등록 → ${alias_file}"
    else
        # 이미 있으면 업데이트
        sed -i "s|^alias [a-z]*='.*file_to_dev.*'|${alias_line}|" "$alias_file"
        echo -e "${_OK} alias 업데이트 (${new_alias})"
    fi

    # bash_functions 또는 bashrc에 source 줄 추가 (dv 통합)
    if [ "$new_dv_integration" = "on" ]; then
        local bf="$HOME/.bash_functions"
        [ ! -f "$bf" ] && bf="$HOME/.bashrc"
        if ! grep -q "file_to_dev.sh" "$bf" 2>/dev/null; then
            {
                echo ""
                echo "# file_to_dev dv 통합"
                echo "${source_line}"
            } >> "$bf"
            echo -e "${_OK} dv 통합 source 등록 → ${bf}"
        else
            # 기존 dv_ext.sh 줄이 있으면 교체
            if grep -q "dv_ext.sh" "$bf" 2>/dev/null; then
                sed -i "s|.*dv_ext.sh.*|${source_line}|" "$bf"
                echo -e "${_OK} dv_ext.sh → file_to_dev.sh source 교체"
            else
                echo -e "${_OK} dv 통합 이미 등록됨"
            fi
        fi
    fi

    echo ""
    # ── How to Play ───────────────────────────────────────────────────
    _ftd_howtoplay "$new_alias"

    echo ""
    echo -e "${_F_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_F_RST}"
    echo -e "${_OK}  ${_F_GREEN}설치 완료!${_F_RST}"
    echo -e "${_F_GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_F_RST}"
    echo ""
    echo -e "  즉시 적용:  ${_F_CYAN}source ~/.bashrc${_F_RST}"
    echo ""
}

# ── 패키지 체크/설치 헬퍼 ────────────────────────────────────────────────
_ftd_check_pkg() {
    local cmd="$1" desc="${2:-$1}" pkg="${3:-$1}"
    printf "  %-12s" "$desc"
    if command -v "$cmd" &>/dev/null; then
        echo -e "${_OK}"
    else
        echo -e "${_WARN} 없음 — 설치 시도..."
        if sudo apt-get install -y "$pkg" &>/dev/null; then
            printf "  %-12s${_OK} 설치 완료\n" "$desc"
        else
            printf "  %-12s${_FAIL} 설치 실패 (수동: sudo apt install ${pkg})\n" "$desc"
        fi
    fi
}

_ftd_check_pyserial() {
    printf "  %-12s" "pyserial"
    if python3 -c "import serial" &>/dev/null; then
        echo -e "${_OK}"
    else
        echo -e "${_WARN} 없음 — 설치 시도..."
        pip3 install pyserial -q && echo -e "  ${_OK} pyserial 설치 완료" \
            || echo -e "  ${_FAIL} pyserial 설치 실패 (수동: pip3 install pyserial)"
    fi
}

# ── How to Play ───────────────────────────────────────────────────────────
_ftd_howtoplay() {
    local a="${1:-${FTD_ALIAS:-ftd}}"
    echo ""
    _hd "📖  How to Play"
    echo ""
    echo -e "  ${_F_WHITE}기본 워크플로우:${_F_RST}"
    echo -e "  ${_F_DIM}빌드 완료 → FW를 TFTP로 복사 → AP로 전송 → 자동 업그레이드${_F_RST}"
    echo ""
    echo -e "  ${_F_WHITE}FW 배포 (원클릭):${_F_RST}"
    echo -e "  ${_F_CYAN}${a} up${_F_RST}              최신 FW 자동 선택 → 전체 배포"
    echo -e "  ${_F_CYAN}${a} up s${_F_RST}            fzf로 FW 파일 직접 선택"
    echo -e "  ${_F_CYAN}${a} up -n${_F_RST}           sysupgrade -n (설정 초기화 포함)"
    echo -e "  ${_F_CYAN}${a} up dry${_F_RST}          dry-run (실행 안 하고 명령만 미리보기)"
    echo -e "  ${_F_CYAN}${a} up 1.2.3.4${_F_RST}      AP IP 직접 지정"
    echo ""
    echo -e "  ${_F_WHITE}파일 전송 (sysupgrade 없음):${_F_RST}"
    echo -e "  ${_F_CYAN}${a} file${_F_RST}            tftpboot 파일 목록에서 fzf 선택 → AP wget"
    echo -e "  ${_F_CYAN}${a} file test.sh${_F_RST}    특정 파일 지정 전송"
    echo ""
    echo -e "  ${_F_WHITE}설정 / 관리:${_F_RST}"
    echo -e "  ${_F_CYAN}${a} set${_F_RST}             설정 편집 (IP·포트·시리얼 등)"
    echo -e "  ${_F_CYAN}${a} log${_F_RST}             배포 이력 조회"
    echo -e "  ${_F_CYAN}${a} doctor${_F_RST}          환경 진단 (패키지·설정·서버 상태)"
    echo -e "  ${_F_CYAN}${a} help${_F_RST}            전체 도움말"
    echo -e "  ${_F_CYAN}${a} init${_F_RST}            초기 설정 재실행"
    echo ""
    echo -e "  ${_F_WHITE}시리얼 관련:${_F_RST}"
    echo -e "  ${_F_DIM}• 시리얼 열림 → 명령 자동 전송${_F_RST}"
    echo -e "  ${_F_DIM}• SecureCRT 점유 → 클립보드 복사 (붙여넣기만)${_F_RST}"
    echo -e "  ${_F_DIM}• 포트 변경: ${a} set → FTD_SERIAL_DEV 항목${_F_RST}"
    echo ""
    if declare -f davo_macro_tool &>/dev/null && [ "$(grep FTD_DV_INTEGRATION "$FTD_CONF" 2>/dev/null | cut -d= -f2 | tr -d "'")" = "on" ]; then
        echo -e "  ${_F_WHITE}dv 통합 (davolink 개발환경):${_F_RST}"
        echo -e "  ${_F_CYAN}dv up${_F_RST}  / ${_F_CYAN}dv file${_F_RST}  명령도 동일하게 사용 가능"
        echo ""
    fi
    echo -e "  ${_F_WHITE}설정 파일:${_F_RST} ${_F_UL}~/.config/ftd/config${_F_RST}"
    echo -e "  ${_F_WHITE}배포 로그:${_F_RST} ${_F_UL}~/.config/ftd/history.log${_F_RST}"
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════
#  UP — FW 배포
# ══════════════════════════════════════════════════════════════════════════
_ftd_up() {
    _ftd_load_conf
    local do_select=0 dry=0 upgrade_n=0 ap_ip_override=""

    case "${1:-}" in
        s|select) do_select=1; shift ;;
        dry)      dry=1;       shift ;;
        -n)       upgrade_n=1; shift ;;
        set)      _ftd_set; return ;;
        log)      _ftd_log_show; return ;;
        doctor)   _ftd_doctor; return ;;
        help|-h)  _ftd_help; return ;;
        [0-9]*.*) ap_ip_override="$1"; shift ;;
    esac
    # 나머지 플래그 수집
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n)         upgrade_n=1 ;;
            [0-9]*.*)   ap_ip_override="$1" ;;
        esac
        shift
    done

    # ── Step 1: FW 복사 ───────────────────────────────────────────────
    echo ""
    echo -e "${_RUN} ${_F_BOLD}[1/3]${_F_RST} FW 파일 → ${_F_UL}${FTD_TFTP_PATH}${_F_RST} 복사"

    local fw_copied_name=""

    case "$FTD_FW_MODE" in
        dv)
            if declare -f send_file_to_tftp &>/dev/null; then
                # 인자 없이 호출 → 원본 파일명 유지 (send_file_to 688번 라인 참조)
                send_file_to_tftp
                [ $? -ne 0 ] && return 1
                fw_copied_name=$(basename "$(ls -1t "${FTD_TFTP_PATH}"/*.img 2>/dev/null | head -1)")
            elif [ -n "${FW_DIR:-}" ] && [ -d "${FW_DIR:-}" ]; then
                local src_file
                if [ $do_select -eq 1 ]; then
                    src_file=$(_ftd_pick_file "${FW_DIR}" "img") || return 1
                else
                    src_file=$(ls -t "${FW_DIR}"/*.img 2>/dev/null \
                        | grep -v '_raw\|_single' | head -1)
                fi
                [ -z "$src_file" ] && echo -e "${_FAIL} ${FW_DIR} 에 .img 없음" && return 1
                fw_copied_name=$(_ftd_do_copy "$src_file" "${FTD_TFTP_PATH}") || return 1
            else
                echo -e "${_FAIL} dv 환경 없음 — ${_F_YELLOW}ftd set${_F_RST} 으로 FTD_FW_MODE 변경"
                echo -e "${_F_DIM}   path: FTD_FW_DIR 직접 지정${_F_RST}"
                echo -e "${_F_DIM}   scan: FTD_SCAN_DIRS 자동 탐지${_F_RST}"
                return 1
            fi
            ;;
        path)
            local src_file
            if [ $do_select -eq 1 ]; then
                src_file=$(_ftd_pick_file "${FTD_FW_DIR}" "img") || return 1
            else
                src_file=$(ls -t "${FTD_FW_DIR}"/*.img 2>/dev/null | grep -v '_raw\|_single' | head -1)
            fi
            [ -z "$src_file" ] && echo -e "${_FAIL} ${FTD_FW_DIR} 에 .img 없음" && return 1
            fw_copied_name=$(_ftd_do_copy "$src_file" "${FTD_TFTP_PATH}") || return 1
            ;;
        scan|*)
            local candidates
            candidates=$(_ftd_scan_fw_files)
            [ -z "$candidates" ] && \
                echo -e "${_FAIL} .img 없음 (탐색 경로: ${FTD_SCAN_DIRS})" && \
                echo -e "${_F_DIM}   ftd set → FTD_SCAN_DIRS 로 경로 추가${_F_RST}" && return 1
            local src_file
            if [ $do_select -eq 1 ] || [ "$(echo "$candidates" | wc -l)" -gt 1 ]; then
                src_file=$(_ftd_fzf_scan "$candidates") || return 1
            else
                src_file=$(echo "$candidates" | head -1 | awk '{print $NF}')
            fi
            [ -z "$src_file" ] && return 0
            fw_copied_name=$(_ftd_do_copy "$src_file" "${FTD_TFTP_PATH}") || return 1
            ;;
    esac

    echo -e "${_OK} ${_F_GREEN}${fw_copied_name}${_F_RST} 복사 완료"

    # ── Step 2+3: 전송 ────────────────────────────────────────────────
    local xfer_args=(--file "$fw_copied_name" --upgrade)
    [ "$upgrade_n" = "1" ] && xfer_args+=("-n")
    [ "$dry" = "1" ]       && xfer_args+=("--dry")
    [ -n "$ap_ip_override" ] && xfer_args+=("$ap_ip_override")
    _ftd_transfer "${xfer_args[@]}"
}

_ftd_do_copy() {
    local src="$1" dst_dir="$2"
    local src_name; src_name=$(basename "$src")
    local dst_name="${FTD_FW_NAME:-$src_name}"
    local dst="${dst_dir}/${dst_name}"

    # 기존 img 백업
    if [ -d "${dst_dir}/backup_img" ] && ls "${dst_dir}"/*.img &>/dev/null; then
        mv "${dst_dir}"/*.img "${dst_dir}/backup_img/" 2>/dev/null || true
    fi
    cp -a "$src" "$dst" || return 1
    echo "$dst_name"
}

# ══════════════════════════════════════════════════════════════════════════
#  FILE — 임의 파일 전송
# ══════════════════════════════════════════════════════════════════════════
_ftd_file() {
    _ftd_load_conf
    local target_file="${1:-}" extra_args=("${@:2}")

    if [ -z "$target_file" ] || [[ "$target_file" == --* ]]; then
        target_file=$(_ftd_pick_file "$FTD_TFTP_PATH" "*") || return 1
        [ -z "$target_file" ] && return 0
    fi

    _ftd_transfer --file "$target_file" "${extra_args[@]}"
}

# ── scan 모드 파일 탐색 ───────────────────────────────────────────────────
_ftd_scan_fw_files() {
    local all_files=""
    for scan_root in $FTD_SCAN_DIRS; do
        scan_root="${scan_root/#\~/$HOME}"
        [ -d "$scan_root" ] || continue
        local found
        # mtime(epoch) + bytes + path를 한 번에 수집 → sort → 표시 변환까지 단일 stat
        found=$(find "$scan_root" -maxdepth 7 -name "*.img" \
            -not -path '*/build_dir/*' \
            -not -path '*/.git/*' \
            -not -path '*/.svn/*' \
            -not -path '*/node_modules/*' \
            2>/dev/null \
            | grep -v '_raw\|_single' \
            | xargs -r stat --printf '%Y\t%s\t%n\n' 2>/dev/null)
        [ -n "$found" ] && all_files+="${found}"$'\n'
    done
    # 전체 결과를 mtime 내림차순 정렬 후 출력 형식 변환 (stat 추가 호출 없음)
    echo "$all_files" | grep -v '^$' | sort -rn | head -20 | \
        awk -F'\t' '{
            bytes=$2; path=$3
            if (bytes>=1073741824) sz=sprintf("%.1fG", bytes/1073741824)
            else if (bytes>=1048576) sz=sprintf("%.1fM", bytes/1048576)
            else if (bytes>=1024) sz=sprintf("%.1fK", bytes/1024)
            else sz=bytes"B"
            cmd="date -d @"$1" +\"%Y-%m-%d %H:%M\""
            cmd | getline dt; close(cmd)
            printf "%-16s  %-6s  %s\n", dt, sz, path
        }'
}

_ftd_fzf_scan() {
    # scan 전용 fzf: 날짜+크기+경로 표시, 경로만 반환
    local lines="$1"
    local selected
    if command -v fzf &>/dev/null; then
        selected=$(echo "$lines" | fzf --cycle --height 60% --reverse --border \
            --header "[ FW 파일 선택 — 날짜/크기/경로 | Esc=취소 ]" \
            --prompt "선택 > " \
            --preview $'f=$(awk \'{print $NF}\' <<< {}); echo "경로: $f"; ls -lh "$f" 2>/dev/null; echo ""; stat "$f" 2>/dev/null | grep Modify') || return 1
    else
        local arr; IFS=$'\n' read -r -d '' -a arr <<< "$lines" || true
        echo -e "${_F_YELLOW}[ FW 파일 선택 ]${_F_RST}" >&2
        select item in "${arr[@]}" "취소"; do
            [ "$item" = "취소" ] && return 0
            [ -n "$item" ] && selected="$item" && break
        done <&2
    fi
    [ -z "$selected" ] && return 0
    echo "$selected" | awk '{print $NF}'
}

# ── fzf / select 파일 선택 헬퍼 ──────────────────────────────────────────
_ftd_pick_file() {
    local dir="$1" ext="${2:-img}" header="${3:-[ 파일 선택 ]}"
    local files
    if [ "$ext" = "*" ]; then
        files=$(ls -t "$dir" 2>/dev/null | grep -v '^backup' | head -30)
    else
        files=$(ls -t "${dir}"/*.${ext} 2>/dev/null | xargs -r -n1 basename | head -15)
    fi
    [ -z "$files" ] && echo -e "${_FAIL} ${dir} 에 파일 없음" >&2 && return 1
    echo "$files" | _ftd_fzf_select "[ ${dir} ]"
}

_ftd_fzf_select() {
    local header="${1:-[ 선택 ]}"
    if command -v fzf &>/dev/null; then
        fzf --cycle --height 50% --reverse --border \
            --header "$header (Esc=취소)" --prompt "선택 > "
    else
        local arr; IFS=$'\n' read -r -d '' -a arr || true
        echo -e "${_F_YELLOW}${header}${_F_RST}" >&2
        select f in "${arr[@]}" "취소"; do
            [ "$f" = "취소" ] && return 0
            [ -n "$f" ] && echo "$f" && return 0
        done <&2
    fi
}

# ══════════════════════════════════════════════════════════════════════════
#  TRANSFER ENGINE — 실제 전송 (시리얼 or 클립보드)
# ══════════════════════════════════════════════════════════════════════════
_ftd_transfer() {
    local file_name="" do_upgrade=0 upgrade_n=0 dry=0 ap_ip_ovr=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --file)    file_name="$2"; shift 2 ;;
            --upgrade) do_upgrade=1;   shift ;;
            -n)        upgrade_n=1;    shift ;;
            --dry)     dry=1;          shift ;;
            [0-9]*.*)  ap_ip_ovr="$1"; shift ;;
            *)         shift ;;
        esac
    done

    [ -z "$file_name" ] && echo -e "${_FAIL} 파일명 없음" && return 1
    local fw_path="${FTD_TFTP_PATH}/${file_name}"
    [ ! -f "$fw_path" ] && echo -e "${_FAIL} 파일 없음: ${fw_path}" && return 1

    # 값 결정
    local server_ip; server_ip=$(_ftd_server_ip)
    local ap_ip; ap_ip="${ap_ip_ovr:-$(_ftd_ap_ip)}"
    local http_port="$FTD_HTTP_PORT"
    local sysupgrade_opts="$FTD_SYSUPGRADE_OPTS"
    [ $upgrade_n -eq 1 ] && sysupgrade_opts="${sysupgrade_opts} -n"
    sysupgrade_opts="${sysupgrade_opts# }"

    # 시리얼 감지
    local serial_dev=""
    _ftd_detect_serial "$FTD_SERIAL_DEV"

    # 헤더
    _ftd_print_header "$file_name" "$ap_ip" "$server_ip" "$http_port" \
        "$serial_dev" $do_upgrade "$sysupgrade_opts" $dry

    # dry-run
    if [ $dry -eq 1 ]; then
        _ftd_print_dry "$file_name" "$server_ip" "$http_port" $do_upgrade "$sysupgrade_opts"
        return 0
    fi

    # AP ping
    _ftd_ping_check "$ap_ip" || return 0

    echo ""

    # HTTP 서버 확인
    echo -e "${_RUN} ${_F_BOLD}[2/3]${_F_RST} HTTP 서버 확인..."
    _ftd_check_http "$server_ip" "$http_port" "$file_name" || return 1
    echo ""

    # 명령 구성
    local wget_url="http://${server_ip}:${http_port}/${file_name}"
    local cmd_wget="cd /tmp && wget ${wget_url} -O ${file_name}"
    local cmd_upgrade="sysupgrade ${sysupgrade_opts} /tmp/${file_name}"

    echo -e "${_RUN} ${_F_BOLD}[3/3]${_F_RST} AP 전송..."

    if [ -n "$serial_dev" ]; then
        # 시리얼 모드
        [ "$FTD_AUTO_LOGIN" = "on" ] && _ftd_serial_login "$serial_dev"

        echo -e "${_F_DIM}   ${cmd_wget}${_F_RST}"
        local wget_result; wget_result=$(_ftd_serial_wget "$serial_dev" "$cmd_wget")

        if echo "$wget_result" | grep -q "WGET_OK"; then
            echo -e "${_OK} ${_F_GREEN}다운로드 완료${_F_RST}"
        elif echo "$wget_result" | grep -q "WGET_FAIL"; then
            echo -e "${_FAIL} ${_F_RED}wget 실패${_F_RST}"; _ftd_log "FAIL" "$file_name" "$ap_ip"; return 1
        else
            echo -e "${_WARN} 응답 불확실 — 시리얼 출력 확인"
        fi

        if [ $do_upgrade -eq 1 ]; then
            echo ""
            echo -e "${_WARN} ${_F_YELLOW}sysupgrade 실행 시 AP 재부팅${_F_RST}"
            [ -n "$sysupgrade_opts" ] && echo -e "  ${_F_RED}옵션: ${sysupgrade_opts}${_F_RST}"
            echo -ne "   진행? [y/N]: "; read -r confirm
            [[ ! "$confirm" =~ ^[yY]$ ]] && echo -e "${_OK} 다운로드만 완료" && _ftd_log "CLIP" "$file_name" "$ap_ip" && return 0

            echo -e "${_RUN} sysupgrade 전송..."
            _ftd_serial_cmd "$serial_dev" "$cmd_upgrade" 2
            _ln; echo -e "${_OK} ${_F_GREEN}sysupgrade 전송 완료 — 재부팅 중${_F_RST}"; _ln
            _ftd_log "OK" "$file_name" "$ap_ip"
            _ftd_wait_boot "$ap_ip"
        else
            _ln; echo -e "${_OK} ${_F_GREEN}파일 전송 완료 — /tmp/${file_name}${_F_RST}"; _ln
            _ftd_log "OK" "$file_name" "$ap_ip"
        fi
    else
        # 클립보드 모드
        echo -e "${_F_YELLOW}  시리얼 사용 불가 → 클립보드 모드${_F_RST}"
        [ -n "$_SERIAL_SKIP_REASON" ] && \
            echo -e "  ${_F_DIM}  └ ${_SERIAL_SKIP_REASON}${_F_RST}"
        echo ""
        echo -e "${_F_WHITE}  ┌─ wget${_F_RST}"
        echo -e "${_F_SKY}  │ ${cmd_wget}${_F_RST}"
        echo -e "${_F_WHITE}  └─────────────${_F_RST}"
        echo "$cmd_wget" | xclip -selection clipboard 2>/dev/null \
            && echo -e "  ${_CLIP} 클립보드 복사 — SecureCRT에서 ${_F_WHITE}Ctrl+V${_F_RST}" \
            || echo -e "  ${_WARN} xclip 없음 — 위 명령 수동 복사"

        if [ $do_upgrade -eq 1 ]; then
            echo ""; echo -ne "   wget 완료 후 Enter... "; read -r
            echo ""
            echo -e "${_F_WHITE}  ┌─ sysupgrade${_F_RST}"
            echo -e "${_F_RED}  │ ${cmd_upgrade}${_F_RST}"
            echo -e "${_F_WHITE}  └─────────────${_F_RST}"
            echo "$cmd_upgrade" | xclip -selection clipboard 2>/dev/null \
                && echo -e "  ${_CLIP} 클립보드 복사 — SecureCRT에서 붙여넣기" \
                || echo -e "  ${_WARN} 위 명령 수동 복사"
        fi
        _ln; echo -e "${_OK} ${_F_GREEN}완료${_F_RST}"; _ln
        _ftd_log "CLIP" "$file_name" "$ap_ip"
    fi
    echo ""
}

# ── 헤더 출력 ─────────────────────────────────────────────────────────────
_ftd_print_header() {
    local file="$1" ap="$2" host="$3" port="$4" serial="$5"
    local do_upg="$6" opts="$7" dry="$8"
    local fw_size fw_date mode_tag enx_if enx_tag

    fw_size=$(du -h "${FTD_TFTP_PATH}/${file}" 2>/dev/null | awk '{print $1}')
    fw_date=$(stat -c '%y' "${FTD_TFTP_PATH}/${file}" 2>/dev/null | cut -d. -f1)
    local enx_if="${_DETECTED_ENX_IF:-}"
    [ -n "$enx_if" ] && enx_tag="${_F_DIM}(${enx_if})${_F_RST}" || enx_tag=""
    [ -n "$serial" ] \
        && mode_tag="${_F_GREEN}시리얼${_F_RST} ${_F_DIM}${serial}${_F_RST}" \
        || mode_tag="${_F_YELLOW}클립보드${_F_RST}${_F_DIM}(SecureCRT 수동 붙여넣기)${_F_RST}"
    local dry_tag=""; [ "$dry" = "1" ] && dry_tag=" ${_F_MAG}[DRY-RUN]${_F_RST}"

    echo ""
    _ln
    echo -e "  ${_F_BOLD}${_F_WHITE}file_to_dev${_F_RST}${dry_tag}"
    _ln
    echo -e "  File : ${_F_YELLOW}${file}${_F_RST} ${_F_DIM}(${fw_size}, ${fw_date})${_F_RST}"
    echo -e "  AP   : ${_F_YELLOW}${ap}${_F_RST} ${enx_tag}"
    echo -e "  Host : ${_F_YELLOW}${host}:${port}${_F_RST}"
    echo -e "  Mode : ${mode_tag}"
    [ "$do_upg" = "1" ] && echo -e "  Upg  : ${_F_GREEN}sysupgrade${_F_RST} ${_F_DIM}${opts:-(옵션 없음)}${_F_RST}"
    [ "$FTD_AUTO_LOGIN" = "on" ] && echo -e "  Login: ${_F_GREEN}on${_F_RST} ${_F_DIM}(${FTD_LOGIN_USER})${_F_RST}"
    _ln
    echo ""
}

_ftd_print_dry() {
    local file="$1" host="$2" port="$3" do_upg="$4" opts="$5"
    local url="http://${host}:${port}/${file}"
    echo -e "${_F_MAG}[DRY-RUN] 실행될 명령 미리보기${_F_RST}"
    echo ""
    [ "$FTD_AUTO_LOGIN" = "on" ] && echo -e "  ${_F_DIM}① 로그인: ${FTD_LOGIN_USER}${_F_RST}"
    echo -e "  ${_F_SKY}② wget${_F_RST}   : cd /tmp && wget ${url} -O ${file}"
    [ "$do_upg" = "1" ] && \
        echo -e "  ${_F_SKY}③ upgrade${_F_RST}: sysupgrade ${opts} /tmp/${file}"
    echo ""
}

# ── 시리얼 감지 ───────────────────────────────────────────────────────────
# 결과: serial_dev (경로) + _SERIAL_SKIP_REASON (실패 이유, 표시용)
_ftd_detect_serial() {
    local target="$1"
    local candidates=()
    _SERIAL_SKIP_REASON=""
    if [ "$target" = "off" ]; then serial_dev=""; return; fi
    [ "$target" = "auto" ] \
        && candidates=(/dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyACM0) \
        || candidates=("$target")

    local found_any=0
    for dev in "${candidates[@]}"; do
        [ -c "$dev" ] || continue
        found_any=1
        local rc
        rc=$(python3 -c "
import serial, sys, errno as E
try:
    s = serial.Serial('${dev}', 115200, timeout=0.5)
    s.close()
    print('OK')
except serial.SerialException as e:
    if hasattr(e, 'errno') and e.errno == E.EACCES:
        print('EPERM')
    elif hasattr(e, 'errno') and e.errno == E.EBUSY:
        print('EBUSY')
    else:
        print('EFAIL')
except Exception:
    print('EFAIL')
" 2>/dev/null)
        case "$rc" in
            OK)
                serial_dev="$dev"; _SERIAL_SKIP_REASON=""; return 0 ;;
            EPERM)
                _SERIAL_SKIP_REASON="권한 없음 (${dev}) — sudo usermod -aG dialout \$USER 후 재로그인" ;;
            EBUSY)
                _SERIAL_SKIP_REASON="사용 중 (${dev}) — SecureCRT 등 다른 프로그램이 점유 중" ;;
            *)
                _SERIAL_SKIP_REASON="열기 실패 (${dev})" ;;
        esac
    done
    if [ $found_any -eq 0 ]; then
        _SERIAL_SKIP_REASON="포트 없음 — USB 시리얼 어댑터 연결 확인"
    fi
    serial_dev=""
}

# ── 시리얼 조작 ───────────────────────────────────────────────────────────
_ftd_serial_login() {
    local dev="$1"
    python3 -c "
import serial,time
ser=serial.Serial('${dev}',115200,timeout=1)
time.sleep(0.3); ser.write(b'\r\n'); time.sleep(0.5)
buf=ser.read(ser.in_waiting).decode('utf-8',errors='ignore')
if 'login' in buf.lower():
    ser.write('${FTD_LOGIN_USER}\r'.encode()); time.sleep(0.5)
    if '${FTD_LOGIN_PASS}':
        ser.write('${FTD_LOGIN_PASS}\r'.encode()); time.sleep(0.5)
ser.close()
" 2>/dev/null && echo -e "${_OK} 로그인 완료"
}

_ftd_serial_wget() {
    local dev="$1" cmd="$2"
    python3 -c "
import serial,time,sys
ser=serial.Serial('${dev}',115200,timeout=1)
time.sleep(0.3); ser.write(b'\r'); time.sleep(0.5); ser.read(ser.in_waiting)
ser.write('${cmd}\r'.encode())
out=''; start=time.time()
while time.time()-start<120:
    d=ser.read(ser.in_waiting or 1)
    if d:
        t=d.decode('utf-8',errors='ignore'); out+=t; sys.stderr.write(t)
        if '100%' in out and ('#' in out.split('100%')[-1] or '\$' in out.split('100%')[-1]): break
        if 'bad address' in out.lower() or 'connection refused' in out.lower():
            print('WGET_FAIL'); ser.close(); sys.exit(1)
    time.sleep(0.1)
ser.close()
print('WGET_OK' if ('100%' in out or 'saved' in out.lower()) else 'WGET_TIMEOUT')
" 2>&1
}

_ftd_serial_cmd() {
    local dev="$1" cmd="$2" wait="${3:-2}"
    python3 -c "
import serial,time
ser=serial.Serial('${dev}',115200,timeout=1)
ser.write(b'\r'); time.sleep(0.3)
ser.write('${cmd}\r'.encode()); time.sleep(${wait}); ser.close()
" 2>/dev/null
}

# ── HTTP 서버 확인 ────────────────────────────────────────────────────────
_ftd_check_http() {
    local host="$1" port="$2" file="$3"
    local url="http://${host}:${port}/${file}"

    if curl -s --connect-timeout 3 "$url" -o /dev/null -w "%{http_code}" 2>/dev/null | grep -q "200"; then
        echo -e "${_OK} ${url} 접근 가능"
        return 0
    fi

    case "$FTD_MANAGE_HTTP" in
        auto|always)
            echo -e "${_F_DIM}   HTTP 서버 없음 → 자동 시작 (:${port})${_F_RST}"
            python3 -m http.server --directory "${FTD_TFTP_PATH}" "${port}" &>/dev/null &
            local pid=$!; sleep 1
            if kill -0 "$pid" 2>/dev/null; then
                echo -e "${_OK} HTTP 서버 시작 (PID:${pid})"
                return 0
            fi
            echo -e "${_FAIL} HTTP 서버 시작 실패"; return 1
            ;;
        *)
            echo -e "${_FAIL} HTTP 서버 접근 불가 (${url})"
            echo -e "${_F_DIM}   → 서버 확인 또는 ftd set → FTD_MANAGE_HTTP=auto${_F_RST}"
            return 1
            ;;
    esac
}

# ── AP ping ───────────────────────────────────────────────────────────────
_ftd_ping_check() {
    local ap="$1"
    echo -e "${_RUN} AP ping (${ap})..."
    if ping -c1 -W2 "$ap" &>/dev/null; then
        echo -e "${_OK} AP 응답 확인"
        return 0
    fi
    echo -e "${_WARN} ${_F_YELLOW}AP 응답 없음. 계속? [y/N]${_F_RST} "
    read -r ans; [[ "$ans" =~ ^[yY]$ ]]
}

_ftd_wait_boot() {
    local ap="$1"
    echo -ne "${_F_DIM}   AP 재부팅 대기"
    for ((i=1; i<=50; i++)); do
        sleep 2
        if ping -c1 -W1 "$ap" &>/dev/null; then
            echo -e "${_F_RST}"
            echo -e "${_OK} ${_F_GREEN}AP 부팅 완료! (${i}회×2 = $(( i * 2 ))초)${_F_RST}"
            return 0
        fi
        echo -ne "."
    done
    echo -e "${_F_RST}"
    echo -e "${_WARN} 100초 초과 — 수동 확인 필요"
}

# ── 로그 ──────────────────────────────────────────────────────────────────
_ftd_log() {
    local status="$1" file="$2" ap="$3" opts="${FTD_SYSUPGRADE_OPTS:--}"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    [ -w "$FTD_LOG" ] || touch "$FTD_LOG" 2>/dev/null || return
    printf "%-20s %-6s %-36s %-16s %s\n" "$ts" "$status" "$file" "$ap" "$opts" >> "$FTD_LOG"
}

# ── SET — 설정 편집 ───────────────────────────────────────────────────────
_ftd_set() {
    _ftd_load_conf
    if [ ! -f "$FTD_CONF" ]; then
        echo -e "${_WARN} 설정 파일 없음 → init 실행 권장"
        return 1
    fi

    local KEYS=(
        "FTD_FW_MODE|FW 위치 모드 (dv/path/scan)"
        "FTD_FW_DIR|FW 디렉토리 (path 모드)"
        "FTD_SCAN_DIRS|scan 탐색 루트 (공백 구분 다중 경로)"
        "FTD_FW_NAME|TFTP 저장 파일명"
        "FTD_TFTP_PATH|TFTP/HTTP 루트 경로"
        "FTD_SERVER_IP|호스트 IP (auto=enx 감지)"
        "FTD_HTTP_PORT|HTTP 포트"
        "FTD_AP_IP|AP IP (auto=.254 감지)"
        "FTD_SERIAL_DEV|시리얼 디바이스 (auto/off//dev/ttyUSBx)"
        "FTD_AUTO_LOGIN|자동 로그인 (on/off)"
        "FTD_LOGIN_USER|로그인 유저"
        "FTD_LOGIN_PASS|로그인 패스워드"
        "FTD_MANAGE_HTTP|HTTP 서버 관리 (off/auto/always)"
        "FTD_SYSUPGRADE_OPTS|sysupgrade 기본 옵션"
    )

    while true; do
        source "$FTD_CONF" 2>/dev/null
        local items=()
        for entry in "${KEYS[@]}"; do
            local key="${entry%%|*}" desc="${entry##*|}"
            local val="${!key}"
            items+=("$(printf '%-26s = %-22s  %s' "$key" "$val" "$desc")")
        done
        items+=("── 저장 후 종료 ──────────────────────────────────────────────────")

        local selected
        if command -v fzf &>/dev/null; then
            selected=$(printf '%s\n' "${items[@]}" | \
                fzf --ansi --cycle --height 60% --reverse --border \
                    --header "[ dv up 설정 — Enter=편집, Esc=종료 ]" --prompt "항목 > ")
        else
            local i=0; for item in "${items[@]}"; do echo -e "  $((i++))) $item"; done
            echo -ne "편집 번호 (Enter=종료): "; read -r num
            selected="${items[$num]:-}"
        fi

        [ -z "$selected" ] && break
        echo "$selected" | grep -q "종료" && break

        local edit_key; edit_key=$(echo "$selected" | awk '{print $1}')
        [ -z "$edit_key" ] && continue
        local cur; cur=$(grep "^${edit_key}=" "$FTD_CONF" 2>/dev/null | cut -d= -f2- | tr -d "'")
        echo -e "\n  ${_F_SKY}${edit_key}${_F_RST} 현재: ${_F_YELLOW}${cur}${_F_RST}"

        if [ "$edit_key" = "FTD_LOGIN_PASS" ]; then
            echo -ne "  새 값 (Enter=유지, 입력 숨김): "; read -rs new_val; echo ""
        else
            echo -ne "  새 값 (Enter=유지): "; read -r new_val
        fi

        if [ -n "$new_val" ]; then
            sed -i "s|^${edit_key}=.*|${edit_key}='${new_val}'|" "$FTD_CONF"
            echo -e "  ${_OK} ${edit_key}=${_F_GREEN}${new_val}${_F_RST}"
        fi
        echo ""
    done
    echo -e "${_OK} 설정 완료 → ${_F_UL}${FTD_CONF}${_F_RST}"
}

# ── LOG — 배포 이력 ───────────────────────────────────────────────────────
_ftd_log_show() {
    _ftd_load_conf
    if [ ! -f "$FTD_LOG" ]; then
        echo -e "${_WARN} 배포 이력 없음 (${FTD_LOG})"
        return
    fi
    echo ""
    _hd "📋  배포 이력"
    echo -e "${_F_DIM}  날짜                 결과  파일                                 AP IP             옵션${_F_RST}"
    echo -e "${_F_DIM}  ─────────────────────────────────────────────────────────────────────────────${_F_RST}"
    tail -25 "$FTD_LOG" | while IFS= read -r line; do
        local result; result=$(echo "$line" | awk '{print $2}')
        case "$result" in
            OK)   echo -e "  ${_F_GREEN}${line}${_F_RST}" ;;
            FAIL) echo -e "  ${_F_RED}${line}${_F_RST}" ;;
            CLIP) echo -e "  ${_F_YELLOW}${line}${_F_RST}" ;;
            *)    echo -e "  ${_F_DIM}${line}${_F_RST}" ;;
        esac
    done
    echo ""
}

# ── DOCTOR — 환경 진단 ────────────────────────────────────────────────────
_ftd_doctor() {
    _ftd_load_conf
    echo ""
    _hd "🔍  환경 진단 (doctor)"
    echo ""

    # 패키지
    echo -e "  ${_F_WHITE}패키지${_F_RST}"
    for cmd in python3 fzf xclip curl pip3; do
        printf "    %-12s" "$cmd"
        command -v "$cmd" &>/dev/null && echo -e "${_OK}" || echo -e "${_FAIL} 없음"
    done
    printf "    %-12s" "pyserial"
    python3 -c "import serial" &>/dev/null && echo -e "${_OK}" || echo -e "${_FAIL} 없음"
    echo ""

    # 설정
    echo -e "  ${_F_WHITE}설정${_F_RST}"
    printf "    %-20s " "~/.config/ftd/config"
    [ -f "$FTD_CONF" ] && echo -e "${_OK} $(ls -la "$FTD_CONF" | awk '{print $1}')" || echo -e "${_FAIL} 없음"
    printf "    %-20s " "FTD_TFTP_PATH"
    [ -d "$FTD_TFTP_PATH" ] && echo -e "${_OK} ${FTD_TFTP_PATH}" || echo -e "${_FAIL} 없음: ${FTD_TFTP_PATH}"
    printf "    %-20s " "FTD_FW_MODE"
    echo -e "${_F_YELLOW}${FTD_FW_MODE}${_F_RST}"
    echo ""

    # 시리얼
    echo -e "  ${_F_WHITE}시리얼${_F_RST}"
    printf "    %-20s " "dialout 그룹"
    if id -nG 2>/dev/null | grep -qw dialout; then
        echo -e "${_OK} $(id -un) 포함"
    else
        echo -e "${_FAIL} ${_F_RED}미포함${_F_RST} — ${_F_YELLOW}sudo usermod -aG dialout \$USER${_F_RST} 후 재로그인"
    fi
    for d in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2; do
        printf "    %-20s " "$d"
        if [ ! -c "$d" ]; then echo -e "${_F_DIM}없음${_F_RST}"; continue; fi
        local rc
        rc=$(python3 -c "
import serial, sys, errno as E
try:
    s = serial.Serial('${d}', 115200, timeout=0.3); s.close(); print('OK')
except serial.SerialException as e:
    print('EPERM' if getattr(e,'errno',0)==E.EACCES else 'EBUSY' if getattr(e,'errno',0)==E.EBUSY else 'EFAIL')
except: print('EFAIL')
" 2>/dev/null)
        case "$rc" in
            OK)    echo -e "${_OK} 열림 가능" ;;
            EPERM) echo -e "${_FAIL} ${_F_RED}권한 없음${_F_RST} — dialout 그룹 추가 필요" ;;
            EBUSY) echo -e "${_WARN} 사용 중 (다른 프로그램 점유)" ;;
            *)     echo -e "${_WARN} 응답 없음" ;;
        esac
    done
    echo ""

    # 서버
    echo -e "  ${_F_WHITE}HTTP 서버${_F_RST}"
    local host; host=$(_ftd_server_ip)
    local url="http://${host}:${FTD_HTTP_PORT}/"
    printf "    %-30s " "$url"
    curl -s --connect-timeout 2 "$url" -o /dev/null && echo -e "${_OK}" || echo -e "${_FAIL} 접근 불가"

    # 네트워크
    echo ""
    echo -e "  ${_F_WHITE}네트워크${_F_RST}"
    local enx; enx=$(ip link show 2>/dev/null | grep -oE 'enx[a-f0-9]+' | head -1)
    printf "    %-20s " "enx 인터페이스"
    [ -n "$enx" ] && echo -e "${_OK} ${enx} (${_DETECTED_HOST_IP})" || echo -e "${_WARN} 없음"
    echo ""
}

# ── HELP ──────────────────────────────────────────────────────────────────
_ftd_help() {
    _ftd_load_conf
    local a="${FTD_ALIAS:-ftd}"
    echo ""
    _hd "📖  file_to_dev — 도움말"
    echo ""
    echo -e "  ${_F_WHITE}사용법:${_F_RST}  ${_F_CYAN}${a}${_F_RST} <command> [options]"
    echo ""
    echo -e "  ${_F_WHITE}Commands:${_F_RST}"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "init"        "초기 설치 마법사 (최초 1회, 재실행 가능)"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "up"          "FW 자동 선택 → 전체 배포"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "up s"        "fzf로 FW 파일 직접 선택 후 배포"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "up -n"       "sysupgrade -n (설정 초기화 포함)"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "up dry"      "dry-run (명령 미리보기만)"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "up [AP_IP]"  "AP IP 직접 지정 (ex: up 192.168.1.254)"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "file"        "tftpboot 파일 fzf 선택 → AP wget"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "file <name>" "파일 지정 전송 (sysupgrade 없음)"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "cp <path>"  "로컬 파일 → tftpboot 복사"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "cp"         "fzf로 파일 선택 → tftpboot 복사"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "cp ."       "현재 디렉토리 .img/.bin/.zip 전부 복사"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "cmd <명령>"  "AP에 임의 명령 전송 (시리얼/클립보드)"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "reboot"     "AP 재부팅 (reboot 명령 전송 + 부팅 대기)"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "clean"      "tftpboot 파일 정리 (fzf 다중 선택 삭제)"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "set"        "설정 편집 (IP·포트·시리얼 등)"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "log"        "배포 이력 조회"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "doctor"     "환경 진단 (패키지·설정·서버)"
    printf "  ${_F_CYAN}%-20s${_F_RST} %s\n" "help"       "이 도움말"
    echo ""
    echo -e "  ${_F_WHITE}FW 위치 모드 (${_F_YELLOW}${FTD_FW_MODE}${_F_RST}${_F_WHITE}):${_F_RST}"
    echo -e "  ${_F_DIM}dv   — dv 환경 (send_file_to_tftp) 사용${_F_RST}"
    echo -e "  ${_F_DIM}path — FTD_FW_DIR 경로에서 복사${_F_RST}"
    echo -e "  ${_F_DIM}scan — ~/proj/**/bin/*.img 자동 탐지${_F_RST}"
    echo ""
    echo -e "  ${_F_WHITE}시리얼 포트:${_F_RST} ${_F_YELLOW}${FTD_SERIAL_DEV}${_F_RST}"
    echo -e "  ${_F_DIM}• 열림 → 명령 자동 전송 / SecureCRT 점유 → 클립보드 모드${_F_RST}"
    echo -e "  ${_F_DIM}• 포트 변경: ${a} set → FTD_SERIAL_DEV${_F_RST}"
    echo ""
    echo -e "  ${_F_WHITE}설정:${_F_RST} ${_F_UL}~/.config/ftd/config${_F_RST}  ${_F_DIM}(chmod 600)${_F_RST}"
    echo -e "  ${_F_WHITE}로그:${_F_RST} ${_F_UL}~/.config/ftd/history.log${_F_RST}"
    echo ""
    echo -e "  ${_F_WHITE}배포 방법:${_F_RST}"
    echo -e "  ${_F_DIM}1. 이 파일 하나만 공유 (git or 복사)${_F_RST}"
    echo -e "  ${_F_DIM}2. ./file_to_dev.sh init${_F_RST}"
    echo -e "  ${_F_DIM}3. source ~/.bashrc${_F_RST}"
    echo -e "  ${_F_DIM}4. ${a} up${_F_RST}"
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════
#  CP — 로컬 파일 → tftpboot 복사
# ══════════════════════════════════════════════════════════════════════════
_ftd_cp() {
    _ftd_load_conf
    local target="${1:-}"

    if [ -z "$target" ]; then
        # 인자 없음 → fzf로 파일 선택 (현재 디렉토리 기준)
        echo -e "${_RUN} fzf로 복사할 파일 선택..."
        target=$(find . -maxdepth 4 -type f 2>/dev/null \
            | grep -v '\.git\|\.svn' \
            | _ftd_fzf_select "[ tftpboot에 복사할 파일 선택 ]") || return 1
        [ -z "$target" ] && return 0
    fi

    # 점(.) = 현재 디렉토리 .img 전부
    if [ "$target" = "." ]; then
        local count=0
        for f in ./*.img ./*.bin ./*.zip; do
            [ -f "$f" ] || continue
            local dest="${FTD_TFTP_PATH}/$(basename "$f")"
            cp -a "$f" "$dest" && echo -e "${_OK} $(basename "$f") → ${FTD_TFTP_PATH}" && (( count++ ))
        done
        [ $count -eq 0 ] && echo -e "${_WARN} 현재 디렉토리에 .img/.bin/.zip 없음"
        return
    fi

    # 경로 확인
    local src="${target/#\~/$HOME}"
    if [ ! -f "$src" ]; then
        echo -e "${_FAIL} 파일 없음: ${src}"
        return 1
    fi

    local dest="${FTD_TFTP_PATH}/$(basename "$src")"
    cp -a "$src" "$dest"
    echo -e "${_OK} ${_F_GREEN}$(basename "$src")${_F_RST} → ${_F_UL}${FTD_TFTP_PATH}${_F_RST}"
    echo -e "  ${_F_DIM}${dest}${_F_RST}"
    echo -e "  ${_F_DIM}fwd file $(basename "$src")  으로 AP에 전송 가능${_F_RST}"
}

# ══════════════════════════════════════════════════════════════════════════
#  CMD — AP에 임의 명령 전송 (시리얼 or 클립보드)
# ══════════════════════════════════════════════════════════════════════════
_ftd_cmd() {
    _ftd_load_conf
    local cmd="${*}"

    if [ -z "$cmd" ]; then
        echo -ne "${_F_WHITE}AP에 전송할 명령: ${_F_RST}"
        read -r cmd
    fi
    [ -z "$cmd" ] && return 0

    # 시리얼 감지
    local serial_dev=""
    _ftd_detect_serial "$FTD_SERIAL_DEV"

    echo ""
    if [ -n "$serial_dev" ]; then
        echo -e "${_RUN} 시리얼 전송 (${serial_dev}): ${_F_CYAN}${cmd}${_F_RST}"
        _ftd_serial_cmd "$serial_dev" "$cmd" 1
        echo -e "${_OK} 전송 완료"
    else
        echo -e "${_F_WHITE}  ┌─ 명령${_F_RST}"
        echo -e "${_F_SKY}  │ ${cmd}${_F_RST}"
        echo -e "${_F_WHITE}  └──────${_F_RST}"
        echo "$cmd" | xclip -selection clipboard 2>/dev/null \
            && echo -e "${_CLIP} 클립보드 복사 — SecureCRT에서 ${_F_WHITE}Ctrl+V${_F_RST}" \
            || echo -e "${_WARN} xclip 없음 — 위 명령 수동 복사"
    fi
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════
#  REBOOT — AP 재부팅
# ══════════════════════════════════════════════════════════════════════════
_ftd_reboot() {
    _ftd_load_conf
    local ap_ip; ap_ip=$(_ftd_ap_ip)

    echo ""
    echo -e "${_WARN} ${_F_YELLOW}AP 재부팅 — ${ap_ip}${_F_RST}"
    echo -ne "   진행? [y/N]: "; read -r confirm
    [[ ! "$confirm" =~ ^[yY]$ ]] && return 0

    _ftd_cmd "reboot"

    echo -ne "${_F_DIM}   재부팅 대기"
    sleep 3
    _ftd_wait_boot "$ap_ip"
}

# ══════════════════════════════════════════════════════════════════════════
#  CLEAN — tftpboot 오래된 파일 정리
# ══════════════════════════════════════════════════════════════════════════
_ftd_clean() {
    _ftd_load_conf
    local tftp="$FTD_TFTP_PATH"

    echo ""
    echo -e "${_RUN} tftpboot 파일 목록 (${tftp})"
    echo ""

    # 현재 파일 목록
    local files; files=$(ls -lhrt "$tftp" 2>/dev/null | grep -v '^total\|^d')
    if [ -z "$files" ]; then
        echo -e "  ${_F_DIM}파일 없음${_F_RST}"; echo ""; return
    fi
    echo "$files" | while IFS= read -r line; do
        echo -e "  ${_F_DIM}${line}${_F_RST}"
    done
    echo ""

    if ! command -v fzf &>/dev/null; then
        echo -e "${_WARN} fzf 없음 — 수동으로 삭제하세요: ${_F_UL}${tftp}${_F_RST}"
        return
    fi

    echo -e "  ${_F_DIM}삭제할 파일을 선택하세요 (Tab=다중선택, Esc=취소)${_F_RST}"
    local to_delete
    to_delete=$(ls "$tftp" 2>/dev/null | grep -v '^backup' \
        | fzf --multi --cycle --height 50% --reverse --border \
            --header "[ 삭제할 파일 — Tab 다중 선택, Esc 취소 ]" \
            --prompt "삭제 > ")

    [ -z "$to_delete" ] && echo -e "${_OK} 취소" && return

    echo ""
    echo -e "${_F_RED}삭제 대상:${_F_RST}"
    echo "$to_delete" | while IFS= read -r f; do
        echo -e "  ${_F_RED}✘ ${f}${_F_RST}"
    done
    echo -ne "   정말 삭제? [y/N]: "; read -r confirm
    [[ ! "$confirm" =~ ^[yY]$ ]] && echo -e "${_OK} 취소" && return

    echo "$to_delete" | while IFS= read -r f; do
        rm -f "${tftp}/${f}" && echo -e "${_OK} 삭제: ${f}"
    done
    echo ""
}

# ══════════════════════════════════════════════════════════════════════════
#  dv 통합 — dv up / dv file 연결
# ══════════════════════════════════════════════════════════════════════════
_ftd_dv_up() {
    _ftd_up "$@"
}

_ftd_dv_file() {
    _ftd_file "$@"
}

function _dv_extended_ftd() {
    case "$1" in
        up)     _ftd_dv_up "${@:2}" ;;
        file)   _ftd_dv_file "${@:2}" ;;
        cp)     _ftd_cp "${@:2}" ;;
        cmd)    _ftd_cmd "${@:2}" ;;
        reboot) _ftd_reboot ;;
        clean)  _ftd_clean ;;
        *)      davo_macro_tool "$@" ;;
    esac
}

# ── sourced 모드 등록 ─────────────────────────────────────────────────────
_ftd_register() {
    _ftd_load_conf

    # alias로 등록 → 현재 쉘에서 직접 실행 (서브프로세스 X)
    # 덕분에 send_file_to_tftp 등 bash 함수 사용 가능
    local a="${FTD_ALIAS:-ftd}"
    eval "alias ${a}='_ftd_main'"

    # dv 통합
    if [ "${FTD_DV_INTEGRATION:-off}" = "on" ] && declare -f davo_macro_tool &>/dev/null; then
        alias dv='_dv_extended_ftd'
    fi
}

# ══════════════════════════════════════════════════════════════════════════
#  MAIN — 실행 or 소싱 분기
# ══════════════════════════════════════════════════════════════════════════
_ftd_main() {
    case "${1:-help}" in
        init)         _ftd_init ;;
        up)           _ftd_up "${@:2}" ;;
        file)         _ftd_file "${@:2}" ;;
        cp)           _ftd_cp "${@:2}" ;;
        cmd)          _ftd_cmd "${@:2}" ;;
        reboot)       _ftd_reboot ;;
        clean)        _ftd_clean ;;
        set)          _ftd_set ;;
        log)          _ftd_log_show ;;
        doctor)       _ftd_doctor ;;
        help|-h|--help) _ftd_help ;;
        howto)        _ftd_howtoplay ;;
        *)
            echo -e "${_WARN} 알 수 없는 명령: $1"
            _ftd_help
            return 1
            ;;
    esac
}

# 소싱 vs 직접 실행 분기
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # source 로 불림 — 함수 등록
    _ftd_register
else
    # 직접 실행
    _ftd_main "$@"
fi
