#!/bin/bash
# ============================================================================
#  dv_ext.sh — davo_macro_tool 확장 (dv up / dv file)
# ============================================================================
#  ~/.bash_functions 끝에서 source됨.
#  dv 명령에 up, file 서브커맨드를 추가하고 기존 davo_macro_tool을 래핑함.
# ============================================================================

DVEXT_DEPLOY_DIR="$HOME/KscTool/scripts/deploy"
DVEXT_CONF="$HOME/.dv_up.conf"
DVEXT_LOG="$HOME/.dv_up.log"
DVEXT_SCRIPT="$DVEXT_DEPLOY_DIR/file_to_dev.sh"

# ── conf 로드 헬퍼 ────────────────────────────────────────────────────────
_dv_load_conf() {
    if [ ! -f "$DVEXT_CONF" ]; then
        echo -e "${NOTICE} ~/.dv_up.conf 없음 — ${cSky}dv up set${cReset} 또는 ${cSky}dv_up_install.sh${cReset} 실행 필요"
        return 1
    fi
    # shellcheck source=/dev/null
    source "$DVEXT_CONF"
    return 0
}

# ── dv up 메인 ────────────────────────────────────────────────────────────
#  사용법:
#    dv up           최신 fw 자동 선택 → 전체 배포
#    dv up s         fzf 파일 선택 → 전체 배포
#    dv up select    (위와 동일)
#    dv up set       설정 메뉴
#    dv up log       배포 이력 조회
#    dv up dry       dry-run
#    dv up -n        sysupgrade -n 포함
# ─────────────────────────────────────────────────────────────────────────
_dv_up_main() {
    _dv_load_conf || return 1

    local subcmd="${1:-}"
    local extra_args=()
    local do_select=0
    local do_upgrade="--upgrade"

    case "$subcmd" in
        set|setting|-s)
            _dv_up_set
            return
            ;;
        log)
            _dv_up_log
            return
            ;;
        s|select)
            do_select=1
            shift 2>/dev/null || true
            ;;
        dry)
            extra_args+=("--dry")
            shift 2>/dev/null || true
            ;;
        -n)
            extra_args+=("-n")
            shift 2>/dev/null || true
            ;;
        -h|--help|help)
            _dv_up_help
            return
            ;;
        "")
            ;;
        [0-9]*.*.*.*)
            extra_args+=("$subcmd")
            shift 2>/dev/null || true
            ;;
        *)
            echo -e "${ERROR} 알 수 없는 서브커맨드: $subcmd"
            _dv_up_help
            return 1
            ;;
    esac

    # 나머지 인자 수집 (-n, AP IP 등)
    while [[ $# -gt 0 ]]; do
        extra_args+=("$1")
        shift
    done

    # ── Step 1: CP — FW를 TFTP로 복사 ─────────────────────────────────
    local fw_file
    echo ""
    echo -e "${RUN} ${cBold}[1/3]${cReset} 이미지 복사 → ${cLine}${DVUP_TFTP_PATH}${cReset}"

    if [ $do_select -eq 1 ]; then
        # fzf로 FW_DIR에서 직접 선택
        fw_file=$(_dv_pick_fw_file) || return 1
        [ -z "$fw_file" ] && return 0

        echo -e "${RUN} 선택: ${cGreen}${fw_file}${cReset}"
        # 기존 이미지 백업
        if ls "${DVUP_TFTP_PATH}"/*.img &>/dev/null 2>&1; then
            [ -d "${DVUP_TFTP_PATH}/backup_img" ] && \
                mv "${DVUP_TFTP_PATH}"/*.img "${DVUP_TFTP_PATH}/backup_img/" 2>/dev/null
        fi
        cp -a "${FW_DIR}/${fw_file}" "${DVUP_TFTP_PATH}/${FW_NAME}"
        if [ $? -ne 0 ]; then
            echo -e "${ERROR} 파일 복사 실패"
            return 1
        fi
        echo -e "${DONE} ${cGreen}${fw_file}${cReset} → ${cLine}${DVUP_TFTP_PATH}/${FW_NAME}${cReset}"
    else
        # 기존 send_file_to_tftp 루틴 그대로 사용
        send_file_to_tftp fw
        if [ $? -ne 0 ]; then
            echo -e "${ERROR} TFTP 복사 실패"
            return 1
        fi
    fi

    # ── Step 2+3: 전송 ─────────────────────────────────────────────────
    if [ ! -x "$DVEXT_SCRIPT" ]; then
        echo -e "${ERROR} file_to_dev.sh 없음: ${DVEXT_SCRIPT}"
        return 1
    fi

    "$DVEXT_SCRIPT" \
        --file "$FW_NAME" \
        $do_upgrade \
        "${extra_args[@]}"
}

# ── FW 파일 fzf 선택 ──────────────────────────────────────────────────────
_dv_pick_fw_file() {
    local fw_dir="${FW_DIR}"
    if [ ! -d "$fw_dir" ]; then
        echo -e "${ERROR} FW_DIR 없음: $fw_dir" >&2
        return 1
    fi

    local files
    files=$(ls -t "${fw_dir}" | grep '\.img$' 2>/dev/null | head -10)
    if [ -z "$files" ]; then
        echo -e "${ERROR} ${fw_dir} 에 .img 파일 없음" >&2
        return 1
    fi

    local cnt; cnt=$(echo "$files" | wc -l)
    if [ "$cnt" -eq 1 ] && command -v fzf &>/dev/null; then
        # fzf --query로 단일 파일도 확인 가능하게
        echo "$files" | fzf --cycle --height 40% --reverse --border \
            --header "[ 전송할 FW 선택 (Esc=취소) ] ${fw_dir}"
    elif command -v fzf &>/dev/null; then
        echo "$files" | fzf --cycle --height 40% --reverse --border \
            --header "[ 전송할 FW 선택 (Esc=취소) ] ${fw_dir}"
    else
        # fzf 없으면 select
        local file_arr
        IFS=$'\n' read -r -d '' -a file_arr <<< "$files" || true
        echo -e "${cYellow}[ 전송할 FW 선택 ]${cReset}" >&2
        select f in "${file_arr[@]}" "취소"; do
            [ "$f" = "취소" ] && return 0
            [ -n "$f" ] && echo "$f" && return 0
        done <&2
    fi
}

# ── dv file 메인 ──────────────────────────────────────────────────────────
#  사용법:
#    dv file              fzf로 TFTP_PATH 파일 선택 → AP로 wget 전송
#    dv file <filename>   지정 파일 전송
#    dv file --login      로그인 포함
# ─────────────────────────────────────────────────────────────────────────
_dv_file_main() {
    _dv_load_conf || return 1

    local target_file=""
    local extra_args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --login)    extra_args+=("--login"); shift ;;
            --serial)   extra_args+=("--serial" "$2"); shift 2 ;;
            --dry)      extra_args+=("--dry"); shift ;;
            [0-9]*.*.*.*)  extra_args+=("$1"); shift ;;
            -*)         extra_args+=("$1"); shift ;;
            *)
                [ -z "$target_file" ] && target_file="$1"
                shift
                ;;
        esac
    done

    if [ -z "$target_file" ]; then
        # fzf로 tftpboot 전체 파일 선택
        target_file=$(_dv_pick_any_file) || return 1
        [ -z "$target_file" ] && return 0
    fi

    # 파일 존재 확인
    if [ ! -f "${DVUP_TFTP_PATH}/${target_file}" ]; then
        echo -e "${ERROR} 파일 없음: ${DVUP_TFTP_PATH}/${target_file}"
        return 1
    fi

    if [ ! -x "$DVEXT_SCRIPT" ]; then
        echo -e "${ERROR} file_to_dev.sh 없음: ${DVEXT_SCRIPT}"
        return 1
    fi

    # sysupgrade 없이 전송만
    "$DVEXT_SCRIPT" \
        --file "$target_file" \
        "${extra_args[@]}"
}

# ── TFTP_PATH 전체 파일 fzf 선택 ─────────────────────────────────────────
_dv_pick_any_file() {
    _dv_load_conf 2>/dev/null
    local tftp="${DVUP_TFTP_PATH:-/tftpboot}"

    if [ ! -d "$tftp" ]; then
        echo -e "${ERROR} TFTP 경로 없음: ${tftp}" >&2
        return 1
    fi

    local files
    files=$(ls -t "$tftp" | grep -v '^backup' | grep -v '^latest' | head -50)
    if [ -z "$files" ]; then
        echo -e "${ERROR} ${tftp} 에 파일 없음" >&2
        return 1
    fi

    if command -v fzf &>/dev/null; then
        echo "$files" | fzf --cycle --height 50% --reverse --border \
            --header "[ 전송할 파일 선택 (Esc=취소) ] ${tftp}" \
            --preview "ls -lh ${tftp}/{} 2>/dev/null | awk '{print \$5, \$6, \$7, \$8, \$9}'"
    else
        local arr
        IFS=$'\n' read -r -d '' -a arr <<< "$files" || true
        echo -e "${cYellow}[ 전송할 파일 선택 ]${cReset}" >&2
        select f in "${arr[@]}" "취소"; do
            [ "$f" = "취소" ] && return 0
            [ -n "$f" ] && echo "$f" && return 0
        done <&2
    fi
}

# ── dv up set — 설정 메뉴 ─────────────────────────────────────────────────
_dv_up_set() {
    local conf="$DVEXT_CONF"

    # conf 없으면 기본값으로 생성
    if [ ! -f "$conf" ]; then
        echo -e "${NOTICE} ~/.dv_up.conf 없음 → 기본값으로 생성"
        _dv_create_default_conf
    fi

    # 설정 항목 정의: "KEY|설명|현재값"
    local -a KEYS=(
        "DVUP_TFTP_PATH|TFTP/HTTP 서버 루트 경로"
        "DVUP_SERVER_IP|호스트(서버) IP  ※auto=enx감지"
        "DVUP_HTTP_PORT|HTTP 포트"
        "DVUP_AP_IP|AP IP  ※auto=enx기반 .254"
        "DVUP_SERIAL_DEV|시리얼 장치  ※auto=ttyUSB0~2탐색 / off=비활성"
        "DVUP_AUTO_LOGIN|자동 로그인 (on/off)"
        "DVUP_LOGIN_USER|로그인 유저명"
        "DVUP_LOGIN_PASS|로그인 패스워드 (없으면 빈칸)"
        "DVUP_MANAGE_HTTP|HTTP 서버 직접 관리 (on=자동시작 / off=확인만)"
        "DVUP_SYSUPGRADE_OPTS|sysupgrade 기본 옵션  ex: -n"
    )

    while true; do
        source "$conf" 2>/dev/null

        # 표시용 리스트 구성
        local display_items=()
        for entry in "${KEYS[@]}"; do
            local key desc val
            key="${entry%%|*}"
            desc="${entry##*|}"
            val=$(grep "^${key}=" "$conf" 2>/dev/null | cut -d= -f2- | sed "s/'//g")
            display_items+=("$(printf '%-30s = %-20s  %s' "$key" "$val" "${cDim}${desc}${cReset}")")
        done
        display_items+=("────────────────────────────────────────────────  저장 후 종료")

        local selected
        if command -v fzf &>/dev/null; then
            selected=$(printf '%s\n' "${display_items[@]}" | \
                fzf --ansi --cycle --height 60% --reverse --border \
                    --header "[ dv up 설정 — Enter=편집, Esc=종료 ]" \
                    --prompt "항목 선택 > ")
        else
            echo -e "${cYellow}[ dv up 설정 ]${cReset}"
            local i=0
            for item in "${display_items[@]}"; do
                echo -e "  $((i++)))  $item"
            done
            echo -ne "편집할 번호: "
            read -r num
            selected="${display_items[$num]}"
        fi

        # Esc 또는 빈 선택 = 종료
        [ -z "$selected" ] && break
        echo "$selected" | grep -q "저장 후 종료" && break

        # 선택된 항목에서 KEY 추출
        local edit_key
        edit_key=$(echo "$selected" | awk '{print $1}')
        [ -z "$edit_key" ] && continue

        # 현재값 표시 + 새값 입력
        local cur_val
        cur_val=$(grep "^${edit_key}=" "$conf" 2>/dev/null | cut -d= -f2- | sed "s/'//g")
        echo -e "\n  ${cSky}${edit_key}${cReset} 현재값: ${cYellow}${cur_val}${cReset}"
        echo -ne "  새 값 (Enter=유지): "
        read -r new_val

        if [ -n "$new_val" ]; then
            if grep -q "^${edit_key}=" "$conf"; then
                sed -i "s|^${edit_key}=.*|${edit_key}='${new_val}'|" "$conf"
            else
                echo "${edit_key}='${new_val}'" >> "$conf"
            fi
            echo -e "  ${DONE} ${edit_key}=${cGreen}${new_val}${cReset}"
        fi
        echo ""
    done

    echo -e "${DONE} 설정 저장 완료 → ${cLine}${conf}${cReset}"
}

# ── conf 기본값 생성 ──────────────────────────────────────────────────────
_dv_create_default_conf() {
    cat > "$DVEXT_CONF" << 'EOF'
# ============================================================
#  ~/.dv_up.conf — dv up / dv file 설정
#  dv up set 으로 편집 가능
# ============================================================

# HTTP/TFTP 서버 루트 경로
DVUP_TFTP_PATH='/tftpboot'

# 호스트 IP (AP에서 wget할 때 사용)
# auto = enx 인터페이스 IP 자동 감지
DVUP_SERVER_IP='auto'

# HTTP 서버 포트
DVUP_HTTP_PORT='80'

# AP IP
# auto = enx 인터페이스 기반 .254 자동 감지
DVUP_AP_IP='auto'

# 시리얼 디바이스
# auto = ttyUSB0 → ttyUSB1 → ttyUSB2 순 자동 탐색
# /dev/ttyUSBx = 고정 지정
# off = 시리얼 사용 안 함 (클립보드 모드)
DVUP_SERIAL_DEV='auto'

# 자동 로그인 (on/off)
# on = wget 전 로그인 시퀀스 자동 실행
DVUP_AUTO_LOGIN='off'
DVUP_LOGIN_USER='root'
DVUP_LOGIN_PASS=''

# HTTP 서버 직접 관리
# off = 이미 실행 중인 서버 사용 (접근만 확인)
# on  = 서버 없으면 자동 시작
DVUP_MANAGE_HTTP='off'

# sysupgrade 기본 옵션 (ex: -n)
DVUP_SYSUPGRADE_OPTS=''
EOF
    echo -e "${DONE} ~/.dv_up.conf 생성 완료"
}

# ── dv up log ─────────────────────────────────────────────────────────────
_dv_up_log() {
    if [ ! -f "$DVEXT_LOG" ]; then
        echo -e "${NOTICE} 배포 이력 없음 (${DVEXT_LOG})"
        return
    fi
    echo ""
    echo -e "${cCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${cReset}"
    echo -e "  ${cBold}배포 이력${cReset} — ${cLine}${DVEXT_LOG}${cReset}"
    echo -e "${cCyan}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${cReset}"
    echo -e "${cDim}  날짜                 결과     파일                                 AP IP             옵션${cReset}"
    echo -e "${cDim}  ─────────────────────────────────────────────────────────────────────────────${cReset}"
    tail -20 "$DVEXT_LOG" | while IFS= read -r line; do
        result=$(echo "$line" | awk '{print $2}')
        case "$result" in
            OK)   echo -e "  ${cGreen}${line}${cReset}" ;;
            FAIL) echo -e "  ${cRed}${line}${cReset}" ;;
            CLIP) echo -e "  ${cYellow}${line}${cReset}" ;;
            *)    echo -e "  ${line}" ;;
        esac
    done
    echo ""
}

# ── dv up help ────────────────────────────────────────────────────────────
_dv_up_help() {
    echo ""
    echo -e "${cSky}dv up${cReset} — AP 펌웨어 원클릭 배포 (dv cp + wget + sysupgrade)"
    echo ""
    echo -e "  ${cWhite}사용법:${cReset}"
    echo -e "    ${cSky}dv up${cReset}                최신 fw 자동 선택 → 전체 배포"
    echo -e "    ${cSky}dv up s${cReset}              fzf로 fw 파일 선택 → 전체 배포"
    echo -e "    ${cSky}dv up -n${cReset}             sysupgrade -n (설정 초기화)"
    echo -e "    ${cSky}dv up set${cReset}            설정 메뉴 (IP, 포트, 시리얼 등)"
    echo -e "    ${cSky}dv up log${cReset}            배포 이력 조회"
    echo -e "    ${cSky}dv up dry${cReset}            dry-run (명령 미리보기만)"
    echo -e "    ${cSky}dv up <AP_IP>${cReset}        AP IP 직접 지정"
    echo ""
    echo -e "  ${cWhite}설정 파일:${cReset} ~/.dv_up.conf"
    echo -e "  ${cWhite}배포 로그:${cReset} ~/.dv_up.log"
    echo ""
    echo -e "${cSky}dv file${cReset} — tftpboot 파일을 AP로 전송 (sysupgrade 없음)"
    echo ""
    echo -e "  ${cWhite}사용법:${cReset}"
    echo -e "    ${cSky}dv file${cReset}              fzf로 파일 선택 → AP wget"
    echo -e "    ${cSky}dv file <name>${cReset}       지정 파일 → AP wget"
    echo -e "    ${cSky}dv file --login${cReset}      로그인 포함"
    echo ""
    echo -e "  ${cDim}시리얼 변경: dv up set → DVUP_SERIAL_DEV 편집${cReset}"
    echo ""
}

# ── dv wrapper ───────────────────────────────────────────────────────────
#  dv up, dv file 처리 후 나머지는 기존 davo_macro_tool로 위임
# ─────────────────────────────────────────────────────────────────────────
function _dv_extended() {
    case "$1" in
        up)
            _dv_up_main "${@:2}"
            ;;
        file)
            _dv_file_main "${@:2}"
            ;;
        *)
            davo_macro_tool "$@"
            ;;
    esac
}

# davo_macro_tool의 help도 dv up/file 항목 추가
_dv_help_patch() {
    echo -e " * ${cSky}dv up${cReset}\t\t: AP 펌웨어 원클릭 배포 (cp+wget+sysupgrade)"
    echo -e " * ${cSky}dv up set${cReset}\t: dv up 설정 (IP, 포트, 시리얼 등)"
    echo -e " * ${cSky}dv file${cReset}\t\t: tftpboot 파일 → AP wget 전송"
    echo -e " * ${cSky}dv up -h${cReset}\t: dv up 상세 도움말"
}

# alias override (bash_functions의 alias dv='davo_macro_tool' 덮어씌움)
alias dv='_dv_extended'

# cCyan 정의 (bash_functions에 없을 경우 대비)
[ -z "${cCyan+x}" ] && cCyan='\e[36m'
