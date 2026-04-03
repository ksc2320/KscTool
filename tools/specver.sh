#!/bin/bash
# ============================================================================
#  specver.sh — KT 규격서 버전 현황 v1.0.0
# ============================================================================
#  사용법:  specver [명령] [키워드]
#
#  Commands:
#    (없음)           latest/ 규격서 버전 목록 출력
#    list             Document/ 하위 전체 PDF 목록 (버전 강조)
#    check            latest/ 심볼릭 링크 유효성 검사
#    open <키워드>    키워드로 규격서 찾아 열기 (xdg-open)
#    help             이 도움말
# ============================================================================

SV_VERSION='1.0.0'
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

    # INDEX.md 테이블 파싱 (| 로 구분된 줄만)
    local found=0
    while IFS='|' read -ra cols; do
        # 헤더·구분선 스킵
        [[ "${cols[1]:-}" =~ ^[[:space:]]*[-]+[[:space:]]*$ ]] && continue
        [[ "${cols[1]:-}" =~ ^[[:space:]]*약칭 ]] && continue
        [ "${#cols[@]}" -lt 4 ] && continue

        local name ver file
        name=$(echo "${cols[1]:-}" | xargs)
        file=$(echo "${cols[2]:-}" | xargs)
        ver=$(echo "${cols[3]:-}" | xargs)
        [ -z "$name" ] && continue

        # latest/ 파일 존재 여부 확인
        local status icon
        if [ -f "$SV_LATEST_DIR/$file" ] || [ -L "$SV_LATEST_DIR/$file" ]; then
            icon="${_OK}"
        else
            icon="${_FAIL}"
        fi

        # 버전 컬러
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
#  list — Document/ 하위 전체 버전 있는 PDF 목록
# ============================================================================
_sv_list() {
    if [ ! -d "$SV_DOC_DIR" ]; then
        echo -e "  ${_FAIL} Document 디렉토리 없음: ${SV_DOC_DIR}"
        return 1
    fi

    # fzf 있으면 인터랙티브 선택 → xdg-open
    if command -v fzf &>/dev/null; then
        local selected
        selected=$(find "$SV_DOC_DIR" -name "*.pdf" ! -path "*/latest/*" | sort | \
            fzf --ansi \
                --prompt="📋 규격서 선택 (Enter=열기) > " \
                --preview="basename {}" \
                --preview-window=up:1 \
                --bind="enter:accept" \
                --color="prompt:cyan,pointer:green")
        if [ -n "$selected" ]; then
            echo -e "  ${_RUN} 열기: ${_F_CYAN}$(basename "$selected")${_F_RST}"
            xdg-open "$selected" 2>/dev/null || \
                echo -e "  ${_WARN} xdg-open 실패. 경로: ${selected}"
        fi
        return
    fi

    # fzf 없으면 일반 목록 출력
    echo ""
    _hd "📁  Document/ 전체 버전 목록"
    echo ""

    local count=0
    while IFS= read -r f; do
        local base dir ver in_latest
        base=$(basename "$f")
        dir=$(dirname "$f" | sed "s|${SV_DOC_DIR}/||")
        if [[ "$base" =~ V([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
            ver="${_F_CYAN}V${BASH_REMATCH[1]}${_F_RST}"
        else
            ver="${_F_DIM}-${_F_RST}"
        fi
        in_latest=''
        if [ -f "$SV_LATEST_DIR/$base" ] || [ -L "$SV_LATEST_DIR/$base" ]; then
            in_latest=" ${_F_GREEN}[latest]${_F_RST}"
        fi
        echo -e "  ${ver}  ${_F_DIM}$(printf '%-30s' "$dir")${_F_RST}  ${_F_WHITE}${base}${_F_RST}${in_latest}"
        ((count++))
    done < <(find "$SV_DOC_DIR" -name "*.pdf" ! -path "*/latest/*" | sort)

    echo ""
    echo -e "  ${_F_DIM}총 ${count}개 PDF  |  fzf 설치 시 인터랙티브 선택 가능${_F_RST}"
    _ln
}

# ============================================================================
#  check — latest/ 심볼릭 링크 유효성 검사
# ============================================================================
_sv_check() {
    if [ ! -d "$SV_LATEST_DIR" ]; then
        echo -e "  ${_FAIL} latest/ 디렉토리 없음: ${SV_LATEST_DIR}"
        return 1
    fi

    echo ""
    _hd "🔍  latest/ 링크 유효성 검사"
    echo ""

    local ok=0 broken=0
    for f in "$SV_LATEST_DIR"/*; do
        [ -e "$f" ] || [ -L "$f" ] || continue
        [[ "$f" == *.md ]] && continue
        [[ "$f" == *.xlsx ]] && continue

        local base
        base=$(basename "$f")

        if [ -L "$f" ]; then
            local target
            target=$(readlink -f "$f" 2>/dev/null)
            if [ -f "$target" ]; then
                echo -e "  ${_OK}  ${_F_WHITE}${base}${_F_RST}  ${_F_DIM}→ $(basename "$target")${_F_RST}"
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

    if [ ! -d "$SV_LATEST_DIR" ]; then
        echo -e "  ${_FAIL} latest/ 디렉토리 없음"
        return 1
    fi

    # latest/ 에서 키워드 매칭 파일 검색
    local matches=()
    while IFS= read -r f; do
        matches+=("$f")
    done < <(find "$SV_LATEST_DIR" -type f -o -type l 2>/dev/null \
        | grep -i "$keyword" | sort)

    if [ ${#matches[@]} -eq 0 ]; then
        echo -e "  ${_FAIL} '${keyword}' 매칭 파일 없음 (latest/ 검색)"
        echo -e "  ${_F_DIM}specver list 로 전체 파일 확인${_F_RST}"
        return 1
    fi

    if [ ${#matches[@]} -eq 1 ]; then
        local f="${matches[0]}"
        echo -e "  ${_RUN} 열기: ${_F_CYAN}$(basename "$f")${_F_RST}"
        xdg-open "$f" 2>/dev/null || \
            echo -e "  ${_WARN} xdg-open 실패. 경로: ${f}"
        return
    fi

    # 여러 개 매칭 → 선택
    echo ""
    echo -e "  '${keyword}' 매칭 파일 ${#matches[@]}개:"
    local i=1
    for f in "${matches[@]}"; do
        echo -e "    ${_F_BOLD}[${i}]${_F_RST}  $(basename "$f")"
        ((i++))
    done
    printf "  번호 선택 [1-%d]: " "${#matches[@]}"
    read -r sel
    if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#matches[@]}" ]; then
        local f="${matches[$((sel-1))]}"
        echo -e "  ${_RUN} 열기: ${_F_CYAN}$(basename "$f")${_F_RST}"
        xdg-open "$f" 2>/dev/null || \
            echo -e "  ${_WARN} xdg-open 실패. 경로: ${f}"
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
    echo -e "  ${_F_CYAN}list${_F_RST}               Document/ 전체 버전 PDF 목록"
    echo -e "  ${_F_CYAN}check${_F_RST}              latest/ 심볼릭 링크 유효성 검사"
    echo -e "  ${_F_CYAN}open <키워드>${_F_RST}       키워드로 규격서 찾아서 열기"
    echo ""
    echo -e "  ${_F_BOLD}예시:${_F_RST}"
    echo -e "    ${_F_DIM}specver${_F_RST}              현재 최신 버전 한눈에 보기"
    echo -e "    ${_F_DIM}specver list${_F_RST}          Document/ 전체 PDF 스캔"
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
    list)           _sv_list ;;
    check)          _sv_check ;;
    open)           shift; _sv_open "$@" ;;
    help|--help|-h) _sv_help ;;
    '')             _sv_show ;;
    *)
        # 인자 있으면 open 단축으로 처리
        _sv_open "$@" ;;
esac
