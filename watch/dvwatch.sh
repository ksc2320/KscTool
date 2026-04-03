#!/bin/bash
# ============================================================================
#  dvwatch.sh — AP 로그 감시 도구 v1.0.0
# ============================================================================
#  사용법:  dvwatch [옵션]
#
#  Commands:
#    (없음)          AP에 SSH/시리얼로 접속 → logread -f 스트림
#    sessions        저장된 세션 목록 보기
#    help            이 도움말
#
#  옵션:
#    --serial [포트] 시리얼 모드 (기본: ftd config)
#    --ssh           SSH 모드 강제
#    -f <파일>       로컬 파일 tail 모드
#    -p <패턴>       하이라이팅 패턴 (여러 개 가능, 대소문자 무시)
#    -s              세션 전체 자동 저장
#    --save-on-match 패턴 첫 감지 시 저장 시작
#    --notify        패턴 감지 시 알림 (notify-send / 터미널 벨)
#
#  단축키:
#    Ctrl+C          종료
#    Ctrl+\          마커 삽입 (─── MARK HH:MM:SS ───)
# ============================================================================

DW_VERSION='1.0.0'
DW_CONF_DIR="$HOME/.config/dvwatch"
DW_CONF="$DW_CONF_DIR/config"
DW_SESSIONS_DIR="$DW_CONF_DIR/sessions"
FTD_CONF="$HOME/.config/ftd/config"

# ── 컬러 ─────────────────────────────────────────────────────────────────────
_F_RED='\033[1;31m';  _F_GREEN='\033[1;32m';  _F_YELLOW='\033[1;33m'
_F_CYAN='\033[1;36m'; _F_MAG='\033[1;35m';    _F_WHITE='\033[1;37m'
_F_SKY='\033[0;36m';  _F_DIM='\033[0;90m';    _F_RST='\033[0m'
_F_BOLD='\033[1m'

_OK="${_F_GREEN}✔${_F_RST}"; _FAIL="${_F_RED}✘${_F_RST}"
_RUN="${_F_CYAN}▶${_F_RST}"; _WARN="${_F_YELLOW}⚠${_F_RST}"

_ln() { echo -e "${_F_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_F_RST}"; }
_hd() { _ln; echo -e "  ${_F_BOLD}${_F_WHITE}$*${_F_RST}"; _ln; }

# 패턴별 컬러 순환: Yellow → Cyan → Magenta → Green (Red는 [ksc] 전용)
_DW_PAT_COLORS=(
    '\033[1;33m'  # Yellow
    '\033[1;36m'  # Cyan
    '\033[1;35m'  # Magenta
    '\033[1;32m'  # Green
    '\033[0;36m'  # Sky
)

# ── 기본값 (ftd config 로드 후 덮어쓰기 가능) ─────────────────────────────────
DW_AP_IP='auto'
DW_AP_USER='root'
DW_AP_PASS=''
DW_SERIAL_DEV='auto'
DW_SERIAL_BAUD='115200'
DW_DEFAULT_PATTERNS=''

# ── 런타임 상태 ───────────────────────────────────────────────────────────────
_dw_patterns=()
_dw_save=0
_dw_save_on_match=0
_dw_save_file=''
_dw_source='auto'   # auto / ssh / serial / file
_dw_file=''
_dw_notify=0
_dw_mark_count=0

# ============================================================================
#  설정 로드
# ============================================================================
_dw_load_conf() {
    # 1) ftd config에서 AP IP / 시리얼 / 로그인 정보 가져오기
    if [ -f "$FTD_CONF" ]; then
        local FTD_AP_IP FTD_SERIAL_DEV FTD_LOGIN_USER FTD_LOGIN_PASS
        # shellcheck disable=SC1090
        source "$FTD_CONF" 2>/dev/null
        [ "$DW_AP_IP"     = 'auto' ] && DW_AP_IP="${FTD_AP_IP:-auto}"
        [ "$DW_SERIAL_DEV" = 'auto' ] && DW_SERIAL_DEV="${FTD_SERIAL_DEV:-auto}"
        [ -z "$DW_AP_USER" ] && DW_AP_USER="${FTD_LOGIN_USER:-root}"
        [ -z "$DW_AP_PASS" ] && DW_AP_PASS="${FTD_LOGIN_PASS:-}"
    fi

    # 2) dvwatch 전용 config로 덮어쓰기 (선택)
    # shellcheck disable=SC1090
    [ -f "$DW_CONF" ] && source "$DW_CONF" 2>/dev/null

    # 3) 기본 패턴 등록
    if [ -n "$DW_DEFAULT_PATTERNS" ]; then
        read -ra _default_pats <<< "$DW_DEFAULT_PATTERNS"
        _dw_patterns=("${_default_pats[@]}" "${_dw_patterns[@]}")
    fi
}

# ── 네트워크 감지 (ftd와 동일 로직) ──────────────────────────────────────────
_dw_detect_network() {
    local enx_info
    enx_info=$(ip -4 addr show 2>/dev/null | grep -A2 'enx' | grep 'inet ' | head -1)
    if [ -n "$enx_info" ]; then
        local host_ip
        host_ip=$(echo "$enx_info" | awk '{print $2}' | cut -d/ -f1)
        _DETECTED_AP_IP=$(echo "$host_ip" | sed 's/\.[0-9]*$/.254/')
    fi
}

_dw_ap_ip() {
    [ "$DW_AP_IP" = 'auto' ] \
        && echo "${_DETECTED_AP_IP:-192.168.1.254}" \
        || echo "$DW_AP_IP"
}

# ============================================================================
#  시리얼 감지
# ============================================================================
_dw_detect_serial() {
    local target="$1"
    _DW_SERIAL_RESULT=''
    _DW_SERIAL_REASON=''

    [ "$target" = 'off' ] && return 1

    local candidates=()
    [ "$target" = 'auto' ] \
        && candidates=(/dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyACM0) \
        || candidates=("$target")

    local found_any=0
    for dev in "${candidates[@]}"; do
        [ -c "$dev" ] || continue
        found_any=1
        local rc
        rc=$(python3 -c "
import serial, errno as E
try:
    s = serial.Serial('${dev}', 115200, timeout=0.5)
    s.close()
    print('OK')
except serial.SerialException as e:
    if hasattr(e,'errno') and e.errno == E.EACCES: print('EPERM')
    elif hasattr(e,'errno') and e.errno == E.EBUSY: print('EBUSY')
    else: print('EFAIL')
except:
    print('EFAIL')
" 2>/dev/null)
        case "$rc" in
            OK)    _DW_SERIAL_RESULT="$dev"; return 0 ;;
            EPERM) _DW_SERIAL_REASON="권한 없음 (${dev}) — sudo usermod -aG dialout \$USER 후 재로그인" ;;
            EBUSY) _DW_SERIAL_REASON="사용 중 (${dev}) — SecureCRT 등 점유" ;;
            *)     _DW_SERIAL_REASON="열기 실패 (${dev})" ;;
        esac
    done
    [ $found_any -eq 0 ] && _DW_SERIAL_REASON="포트 없음 — USB 시리얼 어댑터 연결 확인"
    return 1
}

# ============================================================================
#  스트림 소스
# ============================================================================
_dw_stream_ssh() {
    local ip="$1" user="$2" pass="$3"
    if [ -n "$pass" ] && command -v sshpass &>/dev/null; then
        sshpass -p "$pass" ssh \
            -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -o ServerAliveInterval=10 \
            "${user}@${ip}" "logread -f" 2>/dev/null
    else
        ssh \
            -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            -o ServerAliveInterval=10 \
            "${user}@${ip}" "logread -f" 2>/dev/null
    fi
}

_dw_stream_serial() {
    local dev="$1" baud="$2"
    python3 -u -c "
import serial, sys
try:
    s = serial.Serial('${dev}', ${baud}, timeout=None)
    while True:
        line = s.readline().decode('utf-8', errors='replace')
        sys.stdout.write(line)
        sys.stdout.flush()
except KeyboardInterrupt:
    pass
except Exception as e:
    sys.stderr.write(f'시리얼 오류: {e}\n')
" 2>/dev/null
}

# ============================================================================
#  컬러 필터 루프 (패턴 하이라이팅 + 저장 + 알림)
# ============================================================================
_dw_filter_loop() {
    local line saving=0
    local pat_count=${#_dw_patterns[@]}

    while IFS= read -r line; do
        # ── 패턴 매칭 (저장·알림 트리거) ──────────────────────────────────
        local matched_pat=''
        if [ "$pat_count" -gt 0 ]; then
            for pat in "${_dw_patterns[@]}"; do
                if echo "$line" | grep -qi "$pat" 2>/dev/null; then
                    matched_pat="$pat"
                    break
                fi
            done
        fi

        # ── save-on-match: 첫 패턴 감지 시 저장 시작 ─────────────────────
        if [ "$_dw_save_on_match" -eq 1 ] && [ "$saving" -eq 0 ] && [ -n "$matched_pat" ]; then
            saving=1
            echo -e "\n${_WARN} 패턴 감지 [${_F_YELLOW}${matched_pat}${_F_RST}] → 저장 시작: ${_F_CYAN}${_dw_save_file}${_F_RST}\n"
        fi

        # ── 알림 ──────────────────────────────────────────────────────────
        if [ "$_dw_notify" -eq 1 ] && [ -n "$matched_pat" ]; then
            notify-send "dvwatch" "패턴 감지: ${matched_pat}" 2>/dev/null || printf '\a'
        fi

        # ── 컬러 출력 ─────────────────────────────────────────────────────
        local colored_line="$line"

        # [ksc] 태그: 항상 빨간색 (하드코딩)
        colored_line=$(echo "$colored_line" \
            | sed "s/\(\[ksc\][^)]*\)/${_F_RED//\\/\\\\}\1${_F_RST//\\/\\\\}/g")

        # 사용자 패턴: 컬러 순환
        local i=0
        for pat in "${_dw_patterns[@]}"; do
            local color="${_DW_PAT_COLORS[$((i % ${#_DW_PAT_COLORS[@]}))]}"
            colored_line=$(echo "$colored_line" \
                | sed "s/\(${pat}\)/${color//\\/\\\\}\1${_F_RST//\\/\\\\}/gI")
            ((i++))
        done

        echo -e "$colored_line"

        # ── 저장 ──────────────────────────────────────────────────────────
        if [ -n "$_dw_save_file" ]; then
            if [ "$_dw_save" -eq 1 ] || [ "$saving" -eq 1 ]; then
                echo "$line" >> "$_dw_save_file"
            fi
        fi
    done
}

# ============================================================================
#  종료 핸들러
# ============================================================================
_dw_cleanup() {
    echo ""
    _ln
    if [ -n "$_dw_save_file" ] && [ -f "$_dw_save_file" ]; then
        local lines
        lines=$(wc -l < "$_dw_save_file")
        echo -e "  ${_OK} 세션 저장 완료: ${_F_CYAN}${_dw_save_file}${_F_RST} ${_F_DIM}(${lines}줄)${_F_RST}"
    fi
    if [ "$_dw_mark_count" -gt 0 ]; then
        echo -e "  ${_F_DIM}마커 ${_dw_mark_count}개 삽입됨${_F_RST}"
    fi
    echo -e "  ${_F_DIM}dvwatch 종료${_F_RST}"
    _ln
    exit 0
}

_dw_insert_mark() {
    local ts
    ts=$(date '+%H:%M:%S')
    local mark="─── MARK ${ts} ───"
    echo -e "\n${_F_MAG}${_F_BOLD}${mark}${_F_RST}\n"
    if [ -n "$_dw_save_file" ]; then
        { echo ""; echo "$mark"; echo ""; } >> "$_dw_save_file"
    fi
    ((_dw_mark_count++))
}

# ============================================================================
#  메인 실행
# ============================================================================
_dw_run() {
    local ap_ip
    ap_ip=$(_dw_ap_ip)

    # ── 소스 결정 ──────────────────────────────────────────────────────────
    local actual_source="$_dw_source"
    local serial_dev=''

    if [ "$actual_source" = 'auto' ] || [ "$actual_source" = 'serial' ]; then
        if _dw_detect_serial "$DW_SERIAL_DEV"; then
            serial_dev="$_DW_SERIAL_RESULT"
            actual_source='serial'
        else
            if [ "$_dw_source" = 'serial' ]; then
                # 명시적 시리얼 요청인데 실패
                echo -e "\n  ${_FAIL} 시리얼 연결 실패: ${_DW_SERIAL_REASON}\n"
                return 1
            fi
            # auto: SSH로 폴백
            if [ -n "$_DW_SERIAL_REASON" ]; then
                echo -e "  ${_WARN} 시리얼: ${_DW_SERIAL_REASON}"
                echo -e "  ${_RUN} SSH 모드로 전환"
            fi
            actual_source='ssh'
        fi
    fi

    # ── 헤더 출력 ──────────────────────────────────────────────────────────
    echo ""
    _hd "👁  dvwatch  v${DW_VERSION}"
    echo ""
    case "$actual_source" in
        ssh)
            echo -e "  ${_RUN} 소스  : ${_F_CYAN}SSH${_F_RST}  →  ${_F_WHITE}${ap_ip}${_F_RST}  ${_F_DIM}(${DW_AP_USER})${_F_RST}" ;;
        serial)
            echo -e "  ${_RUN} 소스  : ${_F_CYAN}시리얼${_F_RST}  →  ${_F_WHITE}${serial_dev}${_F_RST}  ${_F_DIM}@${DW_SERIAL_BAUD}${_F_RST}" ;;
        file)
            echo -e "  ${_RUN} 소스  : ${_F_CYAN}파일${_F_RST}  →  ${_F_WHITE}${_dw_file}${_F_RST}" ;;
    esac

    if [ ${#_dw_patterns[@]} -gt 0 ]; then
        local i=0
        printf "  ${_F_BOLD}패턴  :${_F_RST}"
        for pat in "${_dw_patterns[@]}"; do
            local color="${_DW_PAT_COLORS[$((i % ${#_DW_PAT_COLORS[@]}))]}"
            printf "  ${color}%s${_F_RST}" "$pat"
            ((i++))
        done
        echo ""
    fi

    # ── 저장 설정 ──────────────────────────────────────────────────────────
    if [ "$_dw_save" -eq 1 ] || [ "$_dw_save_on_match" -eq 1 ]; then
        mkdir -p "$DW_SESSIONS_DIR"
        local ts
        ts=$(date '+%Y%m%d_%H%M%S')
        _dw_save_file="${DW_SESSIONS_DIR}/${ts}.log"
        if [ "$_dw_save" -eq 1 ]; then
            echo -e "  ${_F_BOLD}저장  :${_F_RST}  ${_F_CYAN}${_dw_save_file}${_F_RST}"
        else
            echo -e "  ${_F_BOLD}저장  :${_F_RST}  ${_F_DIM}패턴 감지 시 자동 시작${_F_RST}"
        fi
    fi

    echo ""
    echo -e "  ${_F_DIM}Ctrl+C: 종료  |  Ctrl+\\: 마커 삽입${_F_RST}"
    _ln
    echo ""

    # ── 시그널 핸들러 ──────────────────────────────────────────────────────
    trap '_dw_cleanup' INT TERM
    trap '_dw_insert_mark' QUIT

    # ── 스트림 시작 ────────────────────────────────────────────────────────
    case "$actual_source" in
        ssh)
            _dw_stream_ssh "$ap_ip" "$DW_AP_USER" "$DW_AP_PASS" \
                | _dw_filter_loop
            ;;
        serial)
            _dw_stream_serial "$serial_dev" "$DW_SERIAL_BAUD" \
                | _dw_filter_loop
            ;;
        file)
            tail -f "$_dw_file" \
                | _dw_filter_loop
            ;;
    esac

    _dw_cleanup
}

# ============================================================================
#  서브 명령
# ============================================================================
_dw_show_sessions() {
    local dir="$DW_SESSIONS_DIR"
    _hd "📁  dvwatch 저장 세션"
    echo ""
    if [ ! -d "$dir" ] || [ -z "$(ls -A "$dir" 2>/dev/null)" ]; then
        echo -e "  ${_F_DIM}저장된 세션이 없습니다.${_F_RST}"
        echo ""
        _ln
        return
    fi
    local i=1
    while IFS= read -r f; do
        local size lines ts_raw
        size=$(du -sh "$f" 2>/dev/null | cut -f1)
        lines=$(wc -l < "$f" 2>/dev/null)
        ts_raw=$(basename "$f" .log)
        # YYYYMMDD_HHMMSS → YYYY-MM-DD HH:MM:SS
        local ts_fmt="${ts_raw:0:4}-${ts_raw:4:2}-${ts_raw:6:2} ${ts_raw:9:2}:${ts_raw:11:2}:${ts_raw:13:2}"
        printf "  ${_F_BOLD}[%d]${_F_RST}  ${_F_WHITE}%s${_F_RST}  ${_F_DIM}%s줄  %s${_F_RST}\n" \
            "$i" "$ts_fmt" "$lines" "$size"
        printf "       ${_F_DIM}%s${_F_RST}\n" "$f"
        echo ""
        ((i++))
    done < <(ls -1t "$dir"/*.log 2>/dev/null)
    _ln
}

_dw_show_help() {
    _hd "👁  dvwatch  v${DW_VERSION}"
    echo ""
    echo -e "  ${_F_BOLD}사용법:${_F_RST}  dvwatch [옵션]  |  dvwatch <명령>"
    echo ""
    echo -e "  ${_F_BOLD}소스 옵션:${_F_RST}"
    echo -e "    ${_F_CYAN}--serial [포트]${_F_RST}   시리얼 모드 (기본: ftd config → auto 감지)"
    echo -e "    ${_F_CYAN}--ssh${_F_RST}             SSH 모드 강제"
    echo -e "    ${_F_CYAN}-f <파일>${_F_RST}         로컬 파일 tail 모드"
    echo ""
    echo -e "  ${_F_BOLD}필터/하이라이팅:${_F_RST}"
    echo -e "    ${_F_CYAN}-p <패턴>${_F_RST}         하이라이팅 패턴 (여러 개 가능, 대소문자 무시)"
    echo -e "                    ${_F_DIM}[ksc] 태그는 항상 빨간색 (기본값)${_F_RST}"
    echo ""
    echo -e "  ${_F_BOLD}저장 옵션:${_F_RST}"
    echo -e "    ${_F_CYAN}-s${_F_RST}                세션 전체 저장  (~/.config/dvwatch/sessions/)"
    echo -e "    ${_F_CYAN}--save-on-match${_F_RST}   패턴 첫 감지 시 저장 시작"
    echo ""
    echo -e "  ${_F_BOLD}기타 옵션:${_F_RST}"
    echo -e "    ${_F_CYAN}--notify${_F_RST}          패턴 감지 시 notify-send / 터미널 벨"
    echo ""
    echo -e "  ${_F_BOLD}명령:${_F_RST}"
    echo -e "    ${_F_CYAN}sessions${_F_RST}          저장된 세션 목록"
    echo -e "    ${_F_CYAN}help${_F_RST}              이 도움말"
    echo ""
    echo -e "  ${_F_BOLD}단축키:${_F_RST}  ${_F_CYAN}Ctrl+C${_F_RST} 종료  |  ${_F_CYAN}Ctrl+\\${_F_RST} 마커 삽입"
    echo ""
    echo -e "  ${_F_BOLD}예시:${_F_RST}"
    echo -e "    ${_F_DIM}dvwatch${_F_RST}                            SSH → logread -f"
    echo -e "    ${_F_DIM}dvwatch -p 'dying gasp'${_F_RST}            패턴 하이라이팅"
    echo -e "    ${_F_DIM}dvwatch -p ERROR -p WARN -s${_F_RST}        멀티 패턴 + 세션 저장"
    echo -e "    ${_F_DIM}dvwatch --serial -p 'kernel panic'${_F_RST}  시리얼 모드"
    echo -e "    ${_F_DIM}dvwatch --serial /dev/ttyUSB1${_F_RST}       포트 명시"
    echo -e "    ${_F_DIM}dvwatch -f /tmp/sys.log -p ERR${_F_RST}     로컬 파일 감시"
    echo -e "    ${_F_DIM}dvwatch --save-on-match -p PANIC${_F_RST}    PANIC 감지 시 자동 저장"
    _ln
}

# ============================================================================
#  엔트리포인트
# ============================================================================
_dw_main() {
    _dw_load_conf
    _dw_detect_network

    # 인자 파싱
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p)
                [ -z "$2" ] && { echo -e "  ${_FAIL} -p 옵션에 패턴을 지정하세요"; exit 1; }
                _dw_patterns+=("$2"); shift 2 ;;
            -p=*)
                _dw_patterns+=("${1#-p=}"); shift ;;
            -s)
                _dw_save=1; shift ;;
            --save-on-match)
                _dw_save_on_match=1; shift ;;
            --notify)
                _dw_notify=1; shift ;;
            --serial)
                _dw_source='serial'
                if [ -n "${2:-}" ] && [[ "$2" != -* ]]; then
                    DW_SERIAL_DEV="$2"; shift
                fi
                shift ;;
            --ssh)
                _dw_source='ssh'; shift ;;
            -f)
                [ -z "${2:-}" ] && { echo -e "  ${_FAIL} -f 옵션에 파일 경로를 지정하세요"; exit 1; }
                _dw_source='file'; _dw_file="$2"; shift 2 ;;
            sessions)
                _dw_show_sessions; exit 0 ;;
            help|--help|-h)
                _dw_show_help; exit 0 ;;
            *)
                echo -e "  ${_FAIL} 알 수 없는 옵션: ${_F_WHITE}$1${_F_RST}"
                echo -e "  ${_F_DIM}dvwatch help  로 사용법 확인${_F_RST}"
                exit 1 ;;
        esac
    done

    # --save-on-match는 패턴 없으면 의미 없음
    if [ "$_dw_save_on_match" -eq 1 ] && [ ${#_dw_patterns[@]} -eq 0 ]; then
        echo -e "  ${_WARN} --save-on-match 는 -p 패턴과 함께 사용하세요"
        exit 1
    fi

    _dw_run
}

_dw_main "$@"
