#!/bin/bash
# ============================================================================
#  ucisnap.sh — UCI 설정 스냅샷/diff 도구 v1.0.0
# ============================================================================
#  사용법:  ucisnap <명령> [인자]
#
#  Commands:
#    save [label]     현재 UCI 전체 스냅샷 저장
#    list             저장된 스냅샷 목록
#    diff [n1] [n2]   두 스냅샷 비교 (기본: 최신 2개)
#    show [n]         스냅샷 내용 출력 (기본: 최신)
#    restore [n]      스냅샷으로 UCI 복원 (confirm 필수)
#    clean [n]        오래된 스냅샷 정리 (기본: 30개 초과분 삭제)
#    help             이 도움말
# ============================================================================

US_VERSION='1.0.0'
US_CONF_DIR="$HOME/.config/ucisnap"
US_SNAPS_DIR="$US_CONF_DIR/snaps"

# ── 컬러 ─────────────────────────────────────────────────────────────────────
_F_RED='\033[1;31m';  _F_GREEN='\033[1;32m';  _F_YELLOW='\033[1;33m'
_F_CYAN='\033[1;36m'; _F_WHITE='\033[1;37m';  _F_DIM='\033[0;90m'
_F_MAG='\033[1;35m';  _F_RST='\033[0m';       _F_BOLD='\033[1m'

_OK="${_F_GREEN}✔${_F_RST}"; _FAIL="${_F_RED}✘${_F_RST}"
_RUN="${_F_CYAN}▶${_F_RST}"; _WARN="${_F_YELLOW}⚠${_F_RST}"

_ln() { echo -e "${_F_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_F_RST}"; }
_hd() { _ln; echo -e "  ${_F_BOLD}${_F_WHITE}$*${_F_RST}"; _ln; }

# ── 스냅샷 목록 파싱 ─────────────────────────────────────────────────────────
# 반환: _US_LIST 배열 (최신순)
_us_load_list() {
    _US_LIST=()
    while IFS= read -r f; do
        _US_LIST+=("$f")
    done < <(ls -1t "$US_SNAPS_DIR"/*.uci 2>/dev/null)
}

_us_fmt_ts() {
    # YYYYMMDD_HHMMSS → YYYY-MM-DD HH:MM:SS
    local raw="$1"
    echo "${raw:0:4}-${raw:4:2}-${raw:6:2} ${raw:9:2}:${raw:11:2}:${raw:13:2}"
}

_us_snap_info() {
    local f="$1"
    local base ts label size lines
    base=$(basename "$f" .uci)
    ts=$(_us_fmt_ts "${base:0:15}")
    label="${base:16}"          # YYYYMMDD_HHMMSS_label → label 부분
    [ -n "$label" ] && label=" ${_F_YELLOW}${label//_/ }${_F_RST}" || label=""
    size=$(du -sh "$f" 2>/dev/null | cut -f1)
    lines=$(wc -l < "$f" 2>/dev/null)
    echo -e "${_F_WHITE}${ts}${_F_RST}${label}  ${_F_DIM}${lines}줄  ${size}${_F_RST}"
}

_us_get_snap() {
    # 번호(1-based) 또는 레이블로 파일 경로 반환
    local arg="${1:-1}"
    _us_load_list
    if [ ${#_US_LIST[@]} -eq 0 ]; then
        echo -e "  ${_FAIL} 저장된 스냅샷이 없습니다." >&2
        return 1
    fi
    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        local idx=$(( arg - 1 ))
        if [ "$idx" -ge "${#_US_LIST[@]}" ]; then
            echo -e "  ${_FAIL} 스냅샷 번호 ${arg} 없음 (총 ${#_US_LIST[@]}개)" >&2
            return 1
        fi
        echo "${_US_LIST[$idx]}"
    else
        # 레이블 검색
        for f in "${_US_LIST[@]}"; do
            local base
            base=$(basename "$f" .uci)
            local label="${base:16}"
            if [[ "${label//_/ }" == *"$arg"* ]]; then
                echo "$f"; return 0
            fi
        done
        echo -e "  ${_FAIL} '${arg}' 레이블 스냅샷 없음" >&2
        return 1
    fi
}

# ============================================================================
#  save
# ============================================================================
_us_save() {
    local label="${*// /_}"  # 공백 → 언더스코어
    mkdir -p "$US_SNAPS_DIR"

    if ! command -v uci &>/dev/null; then
        echo -e "  ${_FAIL} uci 명령을 찾을 수 없습니다."
        return 1
    fi

    local ts
    ts=$(date '+%Y%m%d_%H%M%S')
    local fname
    if [ -n "$label" ]; then
        fname="${US_SNAPS_DIR}/${ts}_${label}.uci"
    else
        fname="${US_SNAPS_DIR}/${ts}.uci"
    fi

    echo -e "  ${_RUN} UCI 설정 저장 중..."
    if uci export > "$fname" 2>/dev/null; then
        local lines size
        lines=$(wc -l < "$fname")
        size=$(du -sh "$fname" | cut -f1)
        echo -e "  ${_OK} 저장 완료: ${_F_CYAN}$(basename "$fname")${_F_RST}  ${_F_DIM}(${lines}줄, ${size})${_F_RST}"
    else
        rm -f "$fname"
        echo -e "  ${_FAIL} uci export 실패"
        return 1
    fi
}

# ============================================================================
#  list
# ============================================================================
_us_list() {
    _hd "📦  ucisnap 목록  v${US_VERSION}"
    echo ""
    _us_load_list

    if [ ${#_US_LIST[@]} -eq 0 ]; then
        echo -e "  ${_F_DIM}저장된 스냅샷이 없습니다.  ucisnap save 로 생성하세요.${_F_RST}"
        echo ""
        _ln
        return
    fi

    local i=1
    for f in "${_US_LIST[@]}"; do
        printf "  ${_F_BOLD}[%d]${_F_RST}  " "$i"
        _us_snap_info "$f"
        ((i++))
    done
    echo ""
    echo -e "  ${_F_DIM}총 ${#_US_LIST[@]}개  |  저장 경로: ${US_SNAPS_DIR}${_F_RST}"
    _ln
}

# ============================================================================
#  diff
# ============================================================================
_us_diff() {
    local a_arg="${1:-1}" b_arg="${2:-2}"

    local a b
    a=$(_us_get_snap "$a_arg") || return 1
    b=$(_us_get_snap "$b_arg") || return 1

    if [ "$a" = "$b" ]; then
        echo -e "  ${_WARN} 같은 스냅샷입니다."
        return
    fi

    echo ""
    _ln
    echo -e "  ${_F_BOLD}diff${_F_RST}  ${_F_DIM}[${a_arg}]${_F_RST} $(_us_snap_info "$a")"
    echo -e "       ${_F_DIM}[${b_arg}]${_F_RST} $(_us_snap_info "$b")"
    _ln
    echo ""

    # diff with color: - 빨강, + 초록, @@ 노랑
    diff -u "$a" "$b" | while IFS= read -r line; do
        case "${line:0:1}" in
            -)  echo -e "${_F_RED}${line}${_F_RST}" ;;
            +)  echo -e "${_F_GREEN}${line}${_F_RST}" ;;
            @)  echo -e "${_F_YELLOW}${line}${_F_RST}" ;;
            *)  echo "$line" ;;
        esac
    done

    echo ""
    _ln
}

# ============================================================================
#  show
# ============================================================================
_us_show() {
    local f
    f=$(_us_get_snap "${1:-1}") || return 1

    echo ""
    _ln
    echo -e "  ${_F_BOLD}[${1:-1}]${_F_RST}  $(_us_snap_info "$f")"
    _ln
    echo ""
    cat "$f"
    echo ""
    _ln
}

# ============================================================================
#  restore
# ============================================================================
_us_restore() {
    local f
    f=$(_us_get_snap "${1:-1}") || return 1

    if ! command -v uci &>/dev/null; then
        echo -e "  ${_FAIL} uci 명령을 찾을 수 없습니다."
        return 1
    fi

    echo ""
    echo -e "  ${_WARN} 복원 대상: $(_us_snap_info "$f")"
    echo -e "  ${_F_RED}현재 UCI 설정이 모두 덮어쓰기됩니다.${_F_RST}"
    printf "  계속할까요? [y/N] "
    read -r yn
    [[ "$yn" != [yY] ]] && { echo -e "  ${_F_DIM}취소${_F_RST}"; return; }

    # 복원 전 현재 상태 자동 백업
    echo -e "  ${_RUN} 현재 설정 자동 백업 중..."
    _us_save "pre_restore" >/dev/null

    echo -e "  ${_RUN} 복원 중..."
    if uci import < "$f" 2>/dev/null; then
        echo -e "  ${_OK} 복원 완료"
    else
        echo -e "  ${_FAIL} uci import 실패"
        return 1
    fi
}

# ============================================================================
#  clean
# ============================================================================
_us_clean() {
    local keep="${1:-30}"
    _us_load_list
    local total=${#_US_LIST[@]}

    if [ "$total" -le "$keep" ]; then
        echo -e "  ${_F_DIM}정리 불필요 (${total}개 / 기준 ${keep}개)${_F_RST}"
        return
    fi

    local del_count=$(( total - keep ))
    echo -e "  ${_WARN} ${total}개 중 오래된 ${del_count}개 삭제 예정"
    printf "  계속할까요? [y/N] "
    read -r yn
    [[ "$yn" != [yY] ]] && { echo -e "  ${_F_DIM}취소${_F_RST}"; return; }

    local i=0
    for f in "${_US_LIST[@]}"; do
        (( i++ ))
        [ "$i" -le "$keep" ] && continue
        rm -f "$f"
        echo -e "  ${_F_DIM}삭제: $(basename "$f")${_F_RST}"
    done
    echo -e "  ${_OK} ${del_count}개 삭제 완료"
}

# ============================================================================
#  help
# ============================================================================
_us_help() {
    _hd "📦  ucisnap  v${US_VERSION}"
    echo ""
    echo -e "  ${_F_BOLD}사용법:${_F_RST}  ucisnap <명령> [인자]"
    echo ""
    echo -e "  ${_F_CYAN}save [레이블]${_F_RST}      현재 UCI 설정 스냅샷 저장"
    echo -e "  ${_F_CYAN}list${_F_RST}               저장된 스냅샷 목록"
    echo -e "  ${_F_CYAN}diff [n1] [n2]${_F_RST}     두 스냅샷 비교 ${_F_DIM}(기본: 1 2 = 최신 두 개)${_F_RST}"
    echo -e "  ${_F_CYAN}show [n]${_F_RST}           스냅샷 내용 출력 ${_F_DIM}(기본: 1 = 최신)${_F_RST}"
    echo -e "  ${_F_CYAN}restore [n]${_F_RST}        스냅샷으로 UCI 복원 ${_F_DIM}(복원 전 자동 백업)${_F_RST}"
    echo -e "  ${_F_CYAN}clean [n]${_F_RST}          오래된 스냅샷 정리 ${_F_DIM}(기본: 30개 초과분)${_F_RST}"
    echo ""
    echo -e "  ${_F_BOLD}예시:${_F_RST}"
    echo -e "    ${_F_DIM}ucisnap save${_F_RST}                  타임스탬프만"
    echo -e "    ${_F_DIM}ucisnap save IPv6 활성화 전${_F_RST}   레이블 포함"
    echo -e "    ${_F_DIM}ucisnap diff${_F_RST}                  최신 2개 비교"
    echo -e "    ${_F_DIM}ucisnap diff 1 3${_F_RST}              번호로 지정"
    echo -e "    ${_F_DIM}ucisnap diff 'IPv6 전' 'IPv6 후'${_F_RST}  레이블로 지정"
    echo -e "    ${_F_DIM}ucisnap restore 2${_F_RST}             2번 스냅샷으로 복원"
    echo ""
    echo -e "  ${_F_DIM}저장 경로: ${US_SNAPS_DIR}${_F_RST}"
    _ln
}

# ============================================================================
#  엔트리포인트
# ============================================================================
case "${1:-}" in
    save)    shift; _us_save "$@" ;;
    list|ls) _us_list ;;
    diff)    shift; _us_diff "$@" ;;
    show)    shift; _us_show "$@" ;;
    restore) shift; _us_restore "$@" ;;
    clean)   shift; _us_clean "$@" ;;
    help|--help|-h|'') _us_help ;;
    *)
        echo -e "  ${_FAIL} 알 수 없는 명령: ${_F_WHITE}$1${_F_RST}"
        echo -e "  ${_F_DIM}ucisnap help 로 확인${_F_RST}"
        exit 1 ;;
esac
