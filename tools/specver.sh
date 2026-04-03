#!/bin/bash
# ============================================================================
#  specver.sh — KT 규격서 버전 현황 v1.0.1
# ============================================================================
#  사용법:  specver [명령] [키워드]
#
#  Commands:
#    (없음)           latest/ 규격서 버전 목록 출력
#    list             latest/ 최신본 목록 (fzf 선택 → 열기)
#    list all         Document/ 전체 PDF 목록
#    check            latest/ 심볼릭 링크 유효성 검사
#    open <키워드>    키워드로 규격서 찾아 열기 (xdg-open)
#    help             이 도움말
# ============================================================================

SV_VERSION='1.0.1'
SV_DOC_DIR="$HOME/문서/Document"
SV_LATEST_DIR="$SV_DOC_DIR/latest"
SV_INDEX="$SV_LATEST_DIR/INDEX.md"

# ── 컬러 ─────────────────────────────────────────────────────────────────────
_F_RED='\033[1;31m';  _F_GREEN='\033[1;32m';  _F_YELLOW='\033[1;33m'
_F_CYAN='\033[1;36m'; _F_WHITE='\033[1;37m';  _F_DIM='\033[0;90m'
_F_MAG='\033[1;35m';  _F_RST='\033[0m';       _F_BOLD='\033[1m'

_OK="${_F_GREEN}✔${_F_RST}"; _FAIL="${_F_RED}✘${_F_RST}"
_WARN="${_F_YELLOW}⚠${_F_RST}"; _RUN="${_F_CYAN}▶${_F_RST}"

_ln() { echo -e "${_F_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_F_RST}"; }
_hd() { _ln; echo -e "  ${_F_BOLD}${_F_WHITE}$*${_F_RST}"; _ln; }

# ── 공통 헬퍼 ────────────────────────────────────────────────────────────────

# latest/ 디렉토리 존재 확인
_sv_need_latest() {
    [ -d "$SV_LATEST_DIR" ] && return 0
    echo -e "  ${_FAIL} latest/ 디렉토리 없음: ${SV_LATEST_DIR}"
    return 1
}

# 파일 열기 (xdg-open + fallback 메시지)
_sv_open_file() {
    local f="$1"
    echo -e "  ${_RUN} 열기: ${_F_CYAN}${f##*/}${_F_RST}"
    xdg-open "$f" 2>/dev/null || echo -e "  ${_WARN} xdg-open 실패. 경로: ${f}"
}

# fzf picker: stdin으로 목록 받아 선택 → 열기
_sv_fzf_pick() {
    local prompt="$1"
    local selected
    selected=$(fzf --ansi \
        --prompt="$prompt" \
        --preview="basename {}" \
        --preview-window=up:1 \
        --color="prompt:cyan,pointer:green")
    [ -n "$selected" ] && _sv_open_file "$selected"
}

# ============================================================================
#  기본 — INDEX.md 파싱 후 컬러 출력
# ============================================================================
_sv_show() {
    if [ ! -f "$SV_INDEX" ]; then
        echo -e "  ${_FAIL} INDEX.md 없음: ${SV_INDEX}"
        return 1
    fi

    local today
    today=$(date '+%Y-%m-%d')

    echo ""
    _hd "📋  KT 규격서 현황  (${today})"
    echo ""

    local found=0
    while IFS='|' read -ra cols; do
        [[ "${cols[1]:-}" =~ ^[[:space:]]*[-]+[[:space:]]*$ ]] && continue
        [[ "${cols[1]:-}" =~ ^[[:space:]]*약칭 ]] && continue
        [ "${#cols[@]}" -lt 4 ] && continue

        # bash 트림 (fork 없음)
        local name="${cols[1]#"${cols[1]%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
        local file="${cols[2]#"${cols[2]%%[![:space:]]*}"}"; file="${file%"${file##*[![:space:]]}"}"
        local ver="${cols[3]#"${cols[3]%%[![:space:]]*}"}";  ver="${ver%"${ver##*[![:space:]]}"}"
        [ -z "$name" ] && continue

        local icon
        if [ -f "$SV_LATEST_DIR/$file" ] || [ -L "$SV_LATEST_DIR/$file" ]; then
            icon="${_OK}"
        else
            icon="${_FAIL}"
        fi

        local ver_colored
        if [ -n "$ver" ] && [ "$ver" != "-" ]; then
            ver_colored="${_F_CYAN}${ver}${_F_RST}"
        else
            ver_colored="${_F_DIM}-${_F_RST}"
        fi

        echo -e "  ${icon}  ${_F_WHITE}$(printf '%-20s' "$name")${_F_RST}  ${ver_colored}  ${_F_DIM}${file}${_F_RST}"
        found=1
    done < "$SV_INDEX"

    if [ "$found" -eq 0 ]; then
        echo -e "  ${_F_DIM}테이블 항목을 파싱할 수 없습니다.${_F_RST}"
    fi

    echo ""
    echo -e "  ${_F_DIM}latest/: ${SV_LATEST_DIR}${_F_RST}"
    echo -e "  ${_F_DIM}열기  : specver list  또는  specver open <키워드>${_F_RST}"
    _ln
}

# ============================================================================
#  list — latest/ 최신본 목록 (fzf 선택 → 열기)
#  list all — Document/ 전체 PDF 목록
# ============================================================================
_sv_list() {
    local show_all="${1:-}"

    if [ "$show_all" = 'all' ]; then
        # ── 전체 목록 ────────────────────────────────────────────────────────
        if [ ! -d "$SV_DOC_DIR" ]; then
            echo -e "  ${_FAIL} Document 디렉토리 없음: ${SV_DOC_DIR}"
            return 1
        fi

        if command -v fzf &>/dev/null; then
            find "$SV_DOC_DIR" -name "*.pdf" ! -path "*/latest/*" | sort | \
                _sv_fzf_pick "📁 전체 규격서 선택 (Enter=열기) > "
            return
        fi

        echo ""
        _hd "📁  Document/ 전체 PDF 목록"
        echo ""
        local count=0
        while IFS= read -r f; do
            local base="${f##*/}"
            local dir="${f%/*}"; dir="${dir#"${SV_DOC_DIR}/"}"
            local ver in_latest=''
            [[ "$base" =~ V([0-9]+\.[0-9]+(\.[0-9]+)?) ]] \
                && ver="${_F_CYAN}V${BASH_REMATCH[1]}${_F_RST}" \
                || ver="${_F_DIM}-${_F_RST}"
            { [ -f "$SV_LATEST_DIR/$base" ] || [ -L "$SV_LATEST_DIR/$base" ]; } \
                && in_latest=" ${_F_GREEN}[latest]${_F_RST}"
            echo -e "  ${ver}  ${_F_DIM}$(printf '%-28s' "$dir")${_F_RST}  ${_F_WHITE}${base}${_F_RST}${in_latest}"
            ((count++))
        done < <(find "$SV_DOC_DIR" -name "*.pdf" ! -path "*/latest/*" | sort)
        echo ""
        echo -e "  ${_F_DIM}총 ${count}개${_F_RST}"
        _ln
        return
    fi

    # ── 기본: latest/ 최신본만 ───────────────────────────────────────────────
    _sv_need_latest || return 1

    local files=()
    while IFS= read -r f; do
        files+=("$f")
    done < <(find "$SV_LATEST_DIR" \( -type f -o -type l \) -name "*.pdf" | sort)

    if [ ${#files[@]} -eq 0 ]; then
        echo -e "  ${_F_DIM}latest/ 에 PDF 없음${_F_RST}"
        return
    fi

    if command -v fzf &>/dev/null; then
        printf '%s\n' "${files[@]}" | \
            _sv_fzf_pick "📋 최신 규격서 선택 (Enter=열기) > "
        return
    fi

    # fzf 없으면 텍스트 목록
    echo ""
    _hd "📋  최신 규격서 목록 (latest/)"
    echo ""
    local i=1
    for f in "${files[@]}"; do
        local base="${f##*/}" ver=''
        [[ "$base" =~ V([0-9]+\.[0-9]+(\.[0-9]+)?) ]] \
            && ver=" ${_F_CYAN}V${BASH_REMATCH[1]}${_F_RST}"
        printf "  ${_F_BOLD}[%d]${_F_RST}  ${_F_WHITE}%s${_F_RST}%b\n" "$i" "$base" "$ver"
        ((i++))
    done
    echo ""
    echo -e "  ${_F_DIM}총 ${#files[@]}개  |  열기: specver open <키워드>${_F_RST}"
    _ln
}

# ============================================================================
#  check — latest/ 심볼릭 링크 유효성 검사
# ============================================================================
_sv_check() {
    _sv_need_latest || return 1

    echo ""
    _hd "🔍  latest/ 링크 유효성 검사"
    echo ""

    local ok=0 broken=0
    for f in "$SV_LATEST_DIR"/*; do
        [ -e "$f" ] || [ -L "$f" ] || continue
        [[ "$f" == *.pdf ]] || continue   # PDF만 검사

        local base="${f##*/}"

        if [ -L "$f" ]; then
            local target
            target=$(readlink -f "$f" 2>/dev/null)
            if [ -f "$target" ]; then
                echo -e "  ${_OK}  ${_F_WHITE}${base}${_F_RST}  ${_F_DIM}→ ${target##*/}${_F_RST}"
                ((ok++))
            else
                echo -e "  ${_FAIL}  ${_F_RED}${base}${_F_RST}  ${_F_DIM}→ 링크 깨짐${_F_RST}"
                ((broken++))
            fi
        elif [ -f "$f" ]; then
            echo -e "  ${_OK}  ${_F_WHITE}${base}${_F_RST}  ${_F_DIM}(직접 파일)${_F_RST}"
            ((ok++))
        fi
    done

    echo ""
    if [ "$broken" -eq 0 ]; then
        echo -e "  ${_OK} 모두 정상  ${_F_DIM}(${ok}개)${_F_RST}"
    else
        echo -e "  ${_WARN} 깨진 링크 ${broken}개  ${_F_DIM}(정상 ${ok}개)${_F_RST}"
    fi
    _ln

    return "$broken"
}

# ============================================================================
#  open — 키워드로 규격서 열기
# ============================================================================
_sv_open() {
    local keyword="${*}"
    if [ -z "$keyword" ]; then
        echo -e "  ${_FAIL} 키워드를 입력하세요.  예: specver open IPv6"
        return 1
    fi

    _sv_need_latest || return 1

    local matches=()
    while IFS= read -r f; do
        matches+=("$f")
    done < <(find "$SV_LATEST_DIR" \( -type f -o -type l \) -iname "*${keyword}*" 2>/dev/null | sort)

    if [ ${#matches[@]} -eq 0 ]; then
        echo -e "  ${_FAIL} '${keyword}' 매칭 파일 없음 (latest/ 검색)"
        echo -e "  ${_F_DIM}specver list 로 전체 파일 확인${_F_RST}"
        return 1
    fi

    if [ ${#matches[@]} -eq 1 ]; then
        _sv_open_file "${matches[0]}"
        return
    fi

    echo ""
    echo -e "  '${keyword}' 매칭 파일 ${#matches[@]}개:"
    local i=1
    for f in "${matches[@]}"; do
        echo -e "    ${_F_BOLD}[${i}]${_F_RST}  ${f##*/}"
        ((i++))
    done
    printf "  번호 선택 [1-%d]: " "${#matches[@]}"
    read -r sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#matches[@]}" ]; then
        _sv_open_file "${matches[$((sel-1))]}"
    else
        echo -e "  ${_F_DIM}취소${_F_RST}"
    fi
}

# ============================================================================
#  help
# ============================================================================
_sv_help() {
    _hd "📋  specver  v${SV_VERSION}"
    echo ""
    echo -e "  ${_F_BOLD}사용법:${_F_RST}  specver [명령] [인자]"
    echo ""
    echo -e "  ${_F_CYAN}(없음)${_F_RST}             latest/ 규격서 버전 목록 출력"
    echo -e "  ${_F_CYAN}list${_F_RST}               latest/ 최신본 목록 (fzf 또는 텍스트)"
    echo -e "  ${_F_CYAN}list all${_F_RST}           Document/ 전체 버전 PDF 목록"
    echo -e "  ${_F_CYAN}check${_F_RST}              latest/ 심볼릭 링크 유효성 검사"
    echo -e "  ${_F_CYAN}open <키워드>${_F_RST}       키워드로 규격서 찾아서 열기"
    echo ""
    echo -e "  ${_F_BOLD}예시:${_F_RST}"
    echo -e "    ${_F_DIM}specver${_F_RST}              현재 최신 버전 한눈에 보기"
    echo -e "    ${_F_DIM}specver list${_F_RST}          최신본 fzf 선택"
    echo -e "    ${_F_DIM}specver list all${_F_RST}      Document/ 전체 PDF 스캔"
    echo -e "    ${_F_DIM}specver check${_F_RST}         링크 깨진 파일 확인"
    echo -e "    ${_F_DIM}specver open 기능규격${_F_RST}  키워드로 PDF 열기"
    echo -e "    ${_F_DIM}specver open Web${_F_RST}      WebManager 규격 열기"
    echo ""
    echo -e "  ${_F_DIM}INDEX : ${SV_INDEX}${_F_RST}"
    _ln
}

# ============================================================================
#  엔트리포인트
# ============================================================================
case "${1:-}" in
    list)           shift; _sv_list "${1:-}" ;;
    check)          _sv_check ;;
    open)           shift; _sv_open "$@" ;;
    help|--help|-h) _sv_help ;;
    '')             _sv_show ;;
    *)              _sv_open "$@" ;;
esac
