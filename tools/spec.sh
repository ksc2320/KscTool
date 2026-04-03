#!/bin/bash
# ============================================================================
#  spec.sh — KT 규격서 버전 현황 v2.0.0
# ============================================================================
#  사용법:  spec [명령] [인자]
#
#  Commands:
#    (없음)              latest/ 규격서 버전 목록 출력
#    list                latest/ 최신본 목록 (fzf 선택 → 열기)
#    list all            Document/ 전체 PDF 목록
#    open <키워드>       키워드로 규격서 찾아 열기 (재검색 루프)
#    path <키워드>       키워드로 규격서 경로 출력
#    check               latest/ 심볼릭 링크 유효성 검사
#    scan                등록된 경로 스캔 → latest/ 심볼릭 링크 갱신
#    scan add <경로>     스캔 경로 추가
#    scan rm  <경로>     스캔 경로 제거
#    scan dirs           등록된 스캔 경로 목록
#    help                이 도움말
# ============================================================================

SV_VERSION='2.0.0'
SV_DOC_DIR="$HOME/문서/Document"
SV_LATEST_DIR="$SV_DOC_DIR/latest"
SV_INDEX="$SV_LATEST_DIR/INDEX.md"
SV_CONF_DIR="$HOME/.devtools/spec"
SV_SCAN_CONF="$SV_CONF_DIR/scan_dirs"

# ── 컬러 ─────────────────────────────────────────────────────────────────────
_F_RED='\033[1;31m';  _F_GREEN='\033[1;32m';  _F_YELLOW='\033[1;33m'
_F_CYAN='\033[1;36m'; _F_WHITE='\033[1;37m';  _F_DIM='\033[0;90m'
_F_MAG='\033[1;35m';  _F_RST='\033[0m';       _F_BOLD='\033[1m'

_OK="${_F_GREEN}✔${_F_RST}";  _FAIL="${_F_RED}✘${_F_RST}"
_WARN="${_F_YELLOW}⚠${_F_RST}"; _RUN="${_F_CYAN}▶${_F_RST}"

_ln() { echo -e "${_F_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_F_RST}"; }
_hd() { _ln; echo -e "  ${_F_BOLD}${_F_WHITE}$*${_F_RST}"; _ln; }

# ── 공통 헬퍼 ────────────────────────────────────────────────────────────────

_sv_need_latest() {
    [ -d "$SV_LATEST_DIR" ] && return 0
    echo -e "  ${_FAIL} latest/ 디렉토리 없음: ${SV_LATEST_DIR}"
    return 1
}

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

# latest/ 에서 키워드 매칭 파일 목록 → _sv_matches 배열에 저장
_sv_find_matches() {
    local keyword="$1"
    _sv_matches=()
    while IFS= read -r f; do
        _sv_matches+=("$f")
    done < <(find "$SV_LATEST_DIR" \( -type f -o -type l \) -iname "*${keyword}*" 2>/dev/null | sort)
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

    [ "$found" -eq 0 ] && echo -e "  ${_F_DIM}테이블 항목을 파싱할 수 없습니다.${_F_RST}"

    echo ""
    echo -e "  ${_F_DIM}latest/: ${SV_LATEST_DIR}${_F_RST}"
    echo -e "  ${_F_DIM}열기  : spec list  또는  spec open <키워드>${_F_RST}"
    _ln
}

# ============================================================================
#  list — latest/ 최신본 목록 / list all — Document/ 전체 PDF 목록
# ============================================================================
_sv_list() {
    local show_all="${1:-}"

    if [ "$show_all" = 'all' ]; then
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
    echo -e "  ${_F_DIM}총 ${#files[@]}개  |  열기: spec open <키워드>${_F_RST}"
    _ln
}

# ============================================================================
#  open — 키워드로 규격서 열기 (재검색 루프)
# ============================================================================
_sv_open() {
    _sv_need_latest || return 1

    local keyword="${*}"

    while true; do
        if [ -z "$keyword" ]; then
            printf "  키워드 입력 [Enter=종료]: "
            read -r keyword
            [ -z "$keyword" ] && return
        fi

        _sv_find_matches "$keyword"

        if [ ${#_sv_matches[@]} -eq 0 ]; then
            echo -e "  ${_FAIL} '${keyword}' 매칭 파일 없음  ${_F_DIM}(latest/ 검색)${_F_RST}"
        elif [ ${#_sv_matches[@]} -eq 1 ]; then
            _sv_open_file "${_sv_matches[0]}"
        else
            echo ""
            echo -e "  ${_F_WHITE}'${keyword}'${_F_RST} 매칭 ${#_sv_matches[@]}개:"
            local i=1
            for f in "${_sv_matches[@]}"; do
                echo -e "    ${_F_BOLD}[${i}]${_F_RST}  ${f##*/}"
                ((i++))
            done
            printf "  번호 선택 [1-%d / Enter=건너뜀]: " "${#_sv_matches[@]}"
            read -r sel
            if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#_sv_matches[@]}" ]; then
                _sv_open_file "${_sv_matches[$((sel-1))]}"
            fi
        fi

        echo ""
        printf "  다시 검색 [키워드 / Enter=종료]: "
        read -r keyword
        [ -z "$keyword" ] && return
        echo ""
    done
}

# ============================================================================
#  path — 키워드로 규격서 경로 출력
# ============================================================================
_sv_path() {
    local keyword="${*}"
    if [ -z "$keyword" ]; then
        echo -e "  ${_FAIL} 키워드를 입력하세요.  예: spec path IPv6"
        return 1
    fi

    _sv_need_latest || return 1
    _sv_find_matches "$keyword"

    if [ ${#_sv_matches[@]} -eq 0 ]; then
        echo -e "  ${_FAIL} '${keyword}' 매칭 없음" >&2
        return 1
    fi

    if [ ${#_sv_matches[@]} -eq 1 ]; then
        local f="${_sv_matches[0]}"
        echo -e "  ${_F_DIM}경로:${_F_RST} ${_F_WHITE}${f}${_F_RST}" >&2
        echo "$f"
        return
    fi

    # 여러 개: 선택 UI는 stderr, 경로(순수 경로)는 stdout
    echo "" >&2
    echo -e "  ${_F_WHITE}'${keyword}'${_F_RST} 매칭 ${#_sv_matches[@]}개:" >&2
    local i=1
    for f in "${_sv_matches[@]}"; do
        echo -e "    ${_F_BOLD}[${i}]${_F_RST}  ${f##*/}" >&2
        ((i++))
    done
    printf "  번호 선택 [1-%d]: " "${#_sv_matches[@]}" >&2
    read -r sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#_sv_matches[@]}" ]; then
        local f="${_sv_matches[$((sel-1))]}"
        echo -e "  ${_F_DIM}경로:${_F_RST} ${_F_WHITE}${f}${_F_RST}" >&2
        echo "$f"
    fi
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
        [[ "$f" == *.pdf ]] || continue

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
#  scan — 등록 경로 스캔 → latest/ 심볼릭 링크 갱신
# ============================================================================
_sv_scan() {
    local subcmd="${1:-}"
    case "$subcmd" in
        add)  shift; _sv_scan_add "$@" ;;
        rm)   shift; _sv_scan_rm  "$@" ;;
        dirs) _sv_scan_dirs ;;
        '')   _sv_scan_run ;;
        *)
            echo -e "  ${_FAIL} 알 수 없는 서브명령: ${_F_WHITE}${subcmd}${_F_RST}"
            echo -e "  ${_F_DIM}spec scan [add|rm|dirs]${_F_RST}"
            return 1 ;;
    esac
}

_sv_scan_add() {
    local dir="${1:-}"
    if [ -z "$dir" ]; then
        echo -e "  ${_FAIL} 경로를 입력하세요.  예: spec scan add ~/문서/oldspecs"
        return 1
    fi
    dir="${dir/#\~/$HOME}"
    dir="${dir%/}"

    mkdir -p "$SV_CONF_DIR"
    if grep -qxF "$dir" "$SV_SCAN_CONF" 2>/dev/null; then
        echo -e "  ${_WARN} 이미 등록됨: ${_F_DIM}${dir}${_F_RST}"
        return
    fi
    echo "$dir" >> "$SV_SCAN_CONF"
    if [ -d "$dir" ]; then
        echo -e "  ${_OK} 추가됨: ${_F_CYAN}${dir}${_F_RST}"
    else
        echo -e "  ${_OK} 추가됨: ${_F_CYAN}${dir}${_F_RST}  ${_F_DIM}(경로 없음 — 스캔 시 스킵)${_F_RST}"
    fi
}

_sv_scan_rm() {
    local dir="${1:-}"
    if [ -z "$dir" ]; then
        echo -e "  ${_FAIL} 경로를 입력하세요."
        return 1
    fi
    dir="${dir/#\~/$HOME}"
    dir="${dir%/}"

    if [ ! -f "$SV_SCAN_CONF" ] || ! grep -qxF "$dir" "$SV_SCAN_CONF" 2>/dev/null; then
        echo -e "  ${_FAIL} 등록되지 않은 경로: ${dir}"
        return 1
    fi
    local tmp; tmp=$(mktemp)
    grep -vxF "$dir" "$SV_SCAN_CONF" > "$tmp" && mv "$tmp" "$SV_SCAN_CONF"
    echo -e "  ${_OK} 제거됨: ${dir}"
}

_sv_scan_dirs() {
    echo ""
    _hd "📂  스캔 경로 목록"
    echo ""
    if [ ! -f "$SV_SCAN_CONF" ] || [ ! -s "$SV_SCAN_CONF" ]; then
        echo -e "  ${_F_DIM}등록된 경로 없음.  spec scan add <경로> 로 추가하세요.${_F_RST}"
        echo ""
        _ln
        return
    fi
    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        if [ -d "$dir" ]; then
            echo -e "  ${_OK}  ${_F_WHITE}${dir}${_F_RST}"
        else
            echo -e "  ${_FAIL}  ${_F_DIM}${dir}${_F_RST}  ${_F_RED}(없음)${_F_RST}"
        fi
    done < "$SV_SCAN_CONF"
    echo ""
    _ln
}

_sv_scan_run() {
    if [ ! -f "$SV_SCAN_CONF" ] || [ ! -s "$SV_SCAN_CONF" ]; then
        echo -e "  ${_FAIL} 스캔 경로 없음.  spec scan add <경로> 로 먼저 추가하세요."
        return 1
    fi

    mkdir -p "$SV_LATEST_DIR"
    echo ""
    _hd "🔍  규격서 스캔"
    echo ""

    declare -A _best_file  # 문서키 → 파일 경로
    declare -A _best_ver   # 문서키 → 버전 문자열

    while IFS= read -r dir; do
        [ -z "$dir" ] && continue
        if [ ! -d "$dir" ]; then
            echo -e "  ${_WARN} 경로 없음 (스킵): ${_F_DIM}${dir}${_F_RST}"
            continue
        fi
        echo -e "  ${_RUN} 스캔: ${_F_DIM}${dir}${_F_RST}"

        while IFS= read -r f; do
            local base="${f##*/}"

            # 문서 키: _Vx.x 이전까지
            local key="${base%.pdf}"
            [[ "$key" =~ ^(.+)_V[0-9]+\.[0-9] ]] && key="${BASH_REMATCH[1]}"

            # 버전 추출 (없으면 0.0.0)
            local ver='0.0.0'
            [[ "$base" =~ _V([0-9]+\.[0-9]+(\.[0-9]+)?) ]] && ver="${BASH_REMATCH[1]}"

            if [ -z "${_best_file[$key]+x}" ]; then
                _best_file["$key"]="$f"
                _best_ver["$key"]="$ver"
            else
                local winner
                winner=$(printf '%s\n%s\n' "${_best_ver[$key]}" "$ver" | sort -V | tail -1)
                if [ "$winner" = "$ver" ] && [ "$ver" != "${_best_ver[$key]}" ]; then
                    _best_file["$key"]="$f"
                    _best_ver["$key"]="$ver"
                fi
            fi
        done < <(find "$dir" -name "*.pdf" ! -path "*/latest/*" 2>/dev/null)

    done < "$SV_SCAN_CONF"

    echo ""
    local added=0 updated=0 same=0
    for key in "${!_best_file[@]}"; do
        local src="${_best_file[$key]}"
        local base="${src##*/}"
        local link="$SV_LATEST_DIR/$base"

        if [ -L "$link" ]; then
            local cur_target
            cur_target=$(readlink -f "$link" 2>/dev/null)
            if [ "$cur_target" = "$src" ]; then
                echo -e "  ${_F_DIM}━  ${base}  (이미 최신)${_F_RST}"
                ((same++))
            else
                ln -sf "$src" "$link"
                echo -e "  ${_F_YELLOW}↑${_F_RST}  ${_F_WHITE}${base}${_F_RST}  ${_F_DIM}갱신${_F_RST}"
                ((updated++))
            fi
        elif [ -f "$link" ]; then
            echo -e "  ${_WARN}  ${base}  ${_F_DIM}(직접 파일 존재, 스킵)${_F_RST}"
        else
            ln -sf "$src" "$link"
            echo -e "  ${_OK}  ${_F_WHITE}${base}${_F_RST}  ${_F_DIM}신규 등록${_F_RST}"
            ((added++))
        fi
    done

    echo ""
    echo -e "  ${_F_DIM}신규 ${added}개  갱신 ${updated}개  유지 ${same}개${_F_RST}"
    _ln
}

# ============================================================================
#  help
# ============================================================================
_sv_help() {
    _hd "📋  spec  v${SV_VERSION}"
    echo ""
    echo -e "  ${_F_BOLD}사용법:${_F_RST}  spec [명령] [인자]"
    echo ""
    echo -e "  ${_F_CYAN}(없음)${_F_RST}              latest/ 규격서 버전 목록 출력"
    echo -e "  ${_F_CYAN}list${_F_RST}                최신본 목록 (fzf 또는 텍스트)"
    echo -e "  ${_F_CYAN}list all${_F_RST}            Document/ 전체 버전 PDF 목록"
    echo -e "  ${_F_CYAN}open <키워드>${_F_RST}        키워드로 규격서 찾아서 열기 (재검색 루프)"
    echo -e "  ${_F_CYAN}path <키워드>${_F_RST}        키워드로 규격서 경로 출력"
    echo -e "  ${_F_CYAN}check${_F_RST}               latest/ 심볼릭 링크 유효성 검사"
    echo -e "  ${_F_CYAN}scan${_F_RST}                등록 경로 스캔 → latest/ 링크 갱신"
    echo -e "  ${_F_CYAN}scan add <경로>${_F_RST}      스캔 경로 추가"
    echo -e "  ${_F_CYAN}scan rm  <경로>${_F_RST}      스캔 경로 제거"
    echo -e "  ${_F_CYAN}scan dirs${_F_RST}           등록된 스캔 경로 목록"
    echo ""
    echo -e "  ${_F_BOLD}예시:${_F_RST}"
    echo -e "    ${_F_DIM}spec${_F_RST}                    현재 최신 버전 한눈에 보기"
    echo -e "    ${_F_DIM}spec list${_F_RST}               최신본 fzf 선택 → 열기"
    echo -e "    ${_F_DIM}spec open IPv6${_F_RST}          IPv6 규격서 열기 (재검색 가능)"
    echo -e "    ${_F_DIM}spec path Web${_F_RST}           WebManager 규격 경로 출력"
    echo -e "    ${_F_DIM}spec scan add ~/문서/old${_F_RST}  스캔 경로 추가"
    echo -e "    ${_F_DIM}spec scan${_F_RST}               스캔 실행 → latest/ 갱신"
    echo ""
    echo -e "  ${_F_DIM}latest/ : ${SV_LATEST_DIR}${_F_RST}"
    echo -e "  ${_F_DIM}스캔 설정: ${SV_SCAN_CONF}${_F_RST}"
    _ln
}

# ============================================================================
#  엔트리포인트
# ============================================================================
case "${1:-}" in
    list)           shift; _sv_list "${1:-}" ;;
    open)           shift; _sv_open "$@" ;;
    path)           shift; _sv_path "$@" ;;
    check)          _sv_check ;;
    scan)           shift; _sv_scan "$@" ;;
    help|--help|-h) _sv_help ;;
    '')             _sv_show ;;
    *)              _sv_open "$@" ;;
esac
