#!/bin/bash
# ============================================================================
#  cpbak.sh — SVN/Git 수정 파일 백업 & 원복 도구 v1.3
# ============================================================================
#  단독 실행:  ./cpbak.sh <command> [args]
#  소싱(bash): source cpbak.sh  → 함수 등록
#
#  Commands:
#    init     최초 설치 (bash_functions/bash_aliases 자동 등록)
#    status   필터 적용된 수정 파일 목록 미리보기
#    save     수정 파일 백업 (~/temp_copy/{proj}_{timestamp}/)
#    restore  백업 → 원위치 복원
#    list     백업 목록 표시 (날짜/파일수/메모)
#    diff     백업 시점 vs 현재 파일 diff
#    clean    오래된 백업 삭제
#    ignore   ignore 패턴 관리 (list/add/rm/edit)
#    help     도움말
#
#  설정/데이터 저장 경로: ~/.devtools/cpbak/
#  ignore 파일:
#    글로벌   : ~/.devtools/cpbak/ignore      (모든 프로젝트 공통)
#    프로젝트 : {VCS_ROOT}/.cpbakignore       (프로젝트별)
# ============================================================================

# ── 컬러/아이콘 (_CB_ prefix) ─────────────────────────────────────────────
_CB_RED='\033[1;31m';   _CB_GREEN='\033[1;32m';  _CB_YELLOW='\033[1;33m'
_CB_CYAN='\033[1;36m';  _CB_MAG='\033[1;35m';    _CB_WHITE='\033[1;37m'
_CB_SKY='\033[0;36m';   _CB_DIM='\033[0;90m';    _CB_RST='\033[0m'
_CB_BOLD='\033[1m'

_CB_OK="${_CB_GREEN}✔${_CB_RST}"
_CB_FAIL="${_CB_RED}✘${_CB_RST}"
_CB_RUN="${_CB_CYAN}▶${_CB_RST}"
_CB_WARN="${_CB_YELLOW}⚠${_CB_RST}"
_CB_NEW="${_CB_MAG}◆${_CB_RST}"
_CB_DEL="${_CB_RED}✖${_CB_RST}"
_CB_IGN="${_CB_DIM}⊘${_CB_RST}"

_cb_ln()  { echo -e "${_CB_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_CB_RST}"; }
_cb_hd()  { _cb_ln; echo -e "  ${_CB_BOLD}${_CB_WHITE}$*${_CB_RST}"; _cb_ln; }
_cb_sec() { echo -e "\n${_CB_CYAN}[${_CB_RST}${_CB_BOLD}$*${_CB_RST}${_CB_CYAN}]${_CB_RST}"; }

# ── 설정 경로 ─────────────────────────────────────────────────────────────
CPBAK_CONF_DIR="$HOME/.devtools/cpbak"
CPBAK_CONF="${CPBAK_CONF_DIR}/config"
CPBAK_LOG="${CPBAK_CONF_DIR}/history.log"
CPBAK_GLOBAL_IGNORE="${CPBAK_CONF_DIR}/ignore"
CPBAK_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── 기본값 ────────────────────────────────────────────────────────────────
CPBAK_BACKUP_ROOT="$HOME/temp_copy"
CPBAK_ALIAS="cpbak"
CPBAK_USE_FZF="auto"

# ── conf 로드 ─────────────────────────────────────────────────────────────
_cpbak_load_conf() {
    [ -f "$CPBAK_CONF" ] && source "$CPBAK_CONF" 2>/dev/null
}
_cpbak_load_conf

# ── VCS 루트 자동 감지 ────────────────────────────────────────────────────
_cpbak_detect_vcs_root() {
    local dir="${1:-$PWD}"
    _CPBAK_VCS_ROOT=""
    _CPBAK_VCS_TYPE="none"
    _CPBAK_GIT_ROOT=""

    local svn_root
    svn_root=$(LANG=C svn info "$dir" 2>/dev/null | grep '^Working Copy Root Path:' | awk '{print $NF}')
    if [ -n "$svn_root" ]; then
        _CPBAK_VCS_ROOT="$svn_root"
        _CPBAK_VCS_TYPE="svn"
    fi

    local git_root
    git_root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$git_root" ]; then
        _CPBAK_GIT_ROOT="$git_root"
        if [ "$_CPBAK_VCS_TYPE" = "svn" ]; then
            _CPBAK_VCS_TYPE="both"
        else
            _CPBAK_VCS_ROOT="$git_root"
            _CPBAK_VCS_TYPE="git"
        fi
    fi

    if [ "$_CPBAK_VCS_TYPE" = "none" ]; then
        echo -e "${_CB_FAIL} SVN/Git 루트를 찾을 수 없습니다: ${dir}" >&2
        return 1
    fi
    return 0
}

# ── ignore 패턴 로드 ──────────────────────────────────────────────────────
_CB_IGNORE_PATTERNS=()
_CB_IGNORE_GLOBAL_CNT=0
_CB_IGNORE_PROJECT_CNT=0

_cpbak_load_ignore() {
    _CB_IGNORE_PATTERNS=()
    _CB_IGNORE_GLOBAL_CNT=0
    _CB_IGNORE_PROJECT_CNT=0
    local line

    if [ -f "$CPBAK_GLOBAL_IGNORE" ]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
            _CB_IGNORE_PATTERNS+=("$line")
            (( _CB_IGNORE_GLOBAL_CNT++ ))
        done < "$CPBAK_GLOBAL_IGNORE"
    fi

    local proj_ignore="${_CPBAK_VCS_ROOT}/.cpbakignore"
    if [ -n "$_CPBAK_VCS_ROOT" ] && [ -f "$proj_ignore" ]; then
        while IFS= read -r line; do
            [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
            _CB_IGNORE_PATTERNS+=("$line")
            (( _CB_IGNORE_PROJECT_CNT++ ))
        done < "$proj_ignore"
    fi
}

# ── ignore 패턴 매칭 ──────────────────────────────────────────────────────
_cpbak_is_ignored() {
    local rel="$1"
    local pat p
    for pat in "${_CB_IGNORE_PATTERNS[@]}"; do
        p="${pat%/}"
        # shellcheck disable=SC2254
        if [[ "$rel" == $p || "$rel" == $p/* ]]; then
            return 0
        fi
    done
    return 1
}

# ── 내장 필터: M 파일 제외 (autoconf 자동생성) ────────────────────────────
_cpbak_is_excluded_M() {
    local rel="$1"
    local fname="${rel##*/}"

    if [[ "$rel" == build_dir/* ]] && [[ "$rel" != build_dir/*/dv_pkg/* ]]; then
        case "$fname" in
            configure|config.guess|config.sub|config.h.in|install-sh|\
            ltmain.sh|sysoptions.h|.dep_files|Makefile.in)
                return 0 ;;
        esac
        [[ "$fname" == *.h.in ]] && return 0
        [[ "$rel" == *ipkg-arm_* || "$rel" == *ipkg-install/* ]] && return 0
    fi
    return 1
}

# ── 내장 필터: ? IDE 설정 포함 ────────────────────────────────────────────
_cpbak_match_include_Q() {
    local rel="$1"
    case "$rel" in
        .vscode/*|.vscode) return 0 ;;
        .cursor/*|.cursor) return 0 ;;
        *.code-workspace)  return 0 ;;
    esac
    return 1
}

# ── 내장 필터: ? 빌드 산출물 제외 ────────────────────────────────────────
_cpbak_match_exclude_Q() {
    local rel="$1"
    local fname="${rel##*/}"
    [[ "$rel" == build_dir/* ]] && return 0
    case "$fname" in
        *.o|*.so|*.so.*|*.a|*.d|*.tmp) return 0 ;;
    esac
    return 1
}

# ── 파일 상태 분류 (SVN/Git 공통) ────────────────────────────────────────
_cpbak_classify_file() {
    local flag="$1" rel="$2"
    case "$flag" in
        M)
            if _cpbak_is_excluded_M "$rel"; then
                _CB_FILES_M_EXCL+=("$rel")
            else
                _CB_FILES_M+=("$rel")
            fi
            ;;
        A) _CB_FILES_A+=("$rel") ;;
        D) _CB_FILES_D+=("$rel") ;;
        \?)
            if _cpbak_match_include_Q "$rel"; then
                _CB_FILES_Q_INC+=("$rel")
            elif ! _cpbak_match_exclude_Q "$rel"; then
                _CB_FILES_Q_AMB+=("$rel")
            fi
            ;;
    esac
}

# ── SVN + Git status 파싱 + 필터/ignore 적용 ─────────────────────────────
_cpbak_get_files() {
    local scope="${1:-$_CPBAK_VCS_ROOT}"

    _CB_FILES_M=()
    _CB_FILES_A=()
    _CB_FILES_D=()
    _CB_FILES_Q_INC=()
    _CB_FILES_Q_AMB=()
    _CB_FILES_M_EXCL=()
    _CB_FILES_IGNORED=()

    _cpbak_load_ignore

    local line flag rel

    if [[ "$_CPBAK_VCS_TYPE" == svn || "$_CPBAK_VCS_TYPE" == both ]]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            flag="${line:0:1}"
            rel="${line:8}"
            rel="${rel#$_CPBAK_VCS_ROOT/}"

            if _cpbak_is_ignored "$rel"; then
                _CB_FILES_IGNORED+=("$rel"); continue
            fi
            _cpbak_classify_file "$flag" "$rel"
        done < <(svn status -q "$scope" 2>/dev/null)
    fi

    if [[ "$_CPBAK_VCS_TYPE" == git || "$_CPBAK_VCS_TYPE" == both ]]; then
        local git_root="${_CPBAK_GIT_ROOT:-$_CPBAK_VCS_ROOT}"
        # SVN에서 이미 처리된 파일 lookup용 associative array
        local -A _seen=()
        local f
        for f in "${_CB_FILES_M[@]}" "${_CB_FILES_A[@]}" "${_CB_FILES_D[@]}" \
                 "${_CB_FILES_Q_INC[@]}" "${_CB_FILES_Q_AMB[@]}" \
                 "${_CB_FILES_M_EXCL[@]}" "${_CB_FILES_IGNORED[@]}"; do
            _seen["$f"]=1
        done

        while IFS= read -r line; do
            [ -z "$line" ] && continue
            flag="${line:0:2}"
            rel="${line:3}"
            rel="${rel#$_CPBAK_VCS_ROOT/}"

            [ "${_seen[$rel]+_}" ] && continue

            if _cpbak_is_ignored "$rel"; then
                _CB_FILES_IGNORED+=("$rel"); continue
            fi
            _cpbak_classify_file "${flag:0:1}" "$rel"
        done < <(git -C "$git_root" status --porcelain 2>/dev/null)
    fi
}

# ── fzf / 텍스트 선택 ─────────────────────────────────────────────────────
_cpbak_fzf_select() {
    local title="$1"; shift
    local items=("$@")
    [ ${#items[@]} -eq 0 ] && return

    if command -v fzf >/dev/null 2>&1 && [ "${CPBAK_USE_FZF:-auto}" != "off" ]; then
        printf '%s\n' "${items[@]}" \
            | fzf --multi \
                  --prompt="cpbak> " \
                  --header="${title}  (Tab=다중선택  Enter=확정  Esc=전체취소)" \
                  --color='header:yellow,pointer:cyan,info:green'
    else
        local result=()
        for item in "${items[@]}"; do
            printf "  ${_CB_WARN} 백업 포함? ${_CB_YELLOW}%-60s${_CB_RST} [y/N]: " "$item"
            local yn; read -r yn
            [[ "$yn" =~ ^[yY]$ ]] && result+=("$item")
        done
        printf '%s\n' "${result[@]}"
    fi
}

# ── status ────────────────────────────────────────────────────────────────
_cpbak_cmd_status() {
    local verbose="" scope=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose) verbose=1; shift ;;
            --scope)      scope="$2"; shift 2 ;;
            *)            scope="$1"; shift ;;
        esac
    done
    scope="${scope:-$_CPBAK_VCS_ROOT}"

    _cb_hd "cpbak status"
    echo -e "  ${_CB_RUN} VCS 루트: ${_CB_BOLD}${_CPBAK_VCS_ROOT}${_CB_RST}  (${_CPBAK_VCS_TYPE})"
    echo -e "  ${_CB_RUN} 스캔 범위: ${_CB_SKY}${scope}${_CB_RST}"

    _cpbak_get_files "$scope"

    if [ "$_CB_IGNORE_GLOBAL_CNT" -gt 0 ] || [ "$_CB_IGNORE_PROJECT_CNT" -gt 0 ]; then
        echo -e "  ${_CB_IGN} ignore: 글로벌 ${_CB_IGNORE_GLOBAL_CNT}개 / 프로젝트 ${_CB_IGNORE_PROJECT_CNT}개 패턴 적용 중"
    fi

    _cb_sec "M - 수정  (백업 대상: ${#_CB_FILES_M[@]}개)"
    if [ ${#_CB_FILES_M[@]} -gt 0 ]; then
        for f in "${_CB_FILES_M[@]}"; do echo -e "  ${_CB_GREEN}M${_CB_RST}  $f"; done
    else
        echo -e "  ${_CB_DIM}(없음)${_CB_RST}"
    fi

    if [ ${#_CB_FILES_A[@]} -gt 0 ]; then
        _cb_sec "A - 추가  (${#_CB_FILES_A[@]}개)"
        for f in "${_CB_FILES_A[@]}"; do echo -e "  ${_CB_CYAN}A${_CB_RST}  $f"; done
    fi

    if [ ${#_CB_FILES_D[@]} -gt 0 ]; then
        _cb_sec "D - 삭제  (${#_CB_FILES_D[@]}개, 목록만 기록)"
        for f in "${_CB_FILES_D[@]}"; do echo -e "  ${_CB_DEL} ${_CB_DIM}$f${_CB_RST}"; done
    fi

    if [ ${#_CB_FILES_Q_INC[@]} -gt 0 ]; then
        _cb_sec "? - IDE 설정  (자동 포함: ${#_CB_FILES_Q_INC[@]}개)"
        for f in "${_CB_FILES_Q_INC[@]}"; do echo -e "  ${_CB_NEW} ${_CB_MAG}$f${_CB_RST}"; done
    fi

    if [ ${#_CB_FILES_Q_AMB[@]} -gt 0 ]; then
        _cb_sec "? - 미결정  (save 시 interactive 선택: ${#_CB_FILES_Q_AMB[@]}개)"
        for f in "${_CB_FILES_Q_AMB[@]}"; do echo -e "  ${_CB_WARN} ${_CB_YELLOW}$f${_CB_RST}"; done
    fi

    if [ ${#_CB_FILES_IGNORED[@]} -gt 0 ]; then
        _cb_sec "⊘ - ignore 제외  (${#_CB_FILES_IGNORED[@]}개)"
        if [ -n "$verbose" ]; then
            for f in "${_CB_FILES_IGNORED[@]}"; do echo -e "  ${_CB_IGN} ${_CB_DIM}$f${_CB_RST}"; done
        else
            echo -e "  ${_CB_DIM}(--verbose 로 목록 표시)${_CB_RST}"
        fi
    fi

    _cb_sec "~ - 내장필터 제외  (autoconf: ${#_CB_FILES_M_EXCL[@]}개)"
    if [ -n "$verbose" ] && [ ${#_CB_FILES_M_EXCL[@]} -gt 0 ]; then
        for f in "${_CB_FILES_M_EXCL[@]}"; do echo -e "  ${_CB_DIM}~  $f${_CB_RST}"; done
    else
        echo -e "  ${_CB_DIM}(--verbose 로 목록 표시)${_CB_RST}"
    fi

    echo ""
    local total=$(( ${#_CB_FILES_M[@]} + ${#_CB_FILES_A[@]} + ${#_CB_FILES_Q_INC[@]} ))
    echo -e "  ${_CB_OK} 백업 예정: ${_CB_BOLD}${total}개${_CB_RST}  (ignore ${#_CB_FILES_IGNORED[@]}개 / 미결정 ${#_CB_FILES_Q_AMB[@]}개 제외)"
    [ ${#_CB_FILES_IGNORED[@]} -gt 0 ] && \
        echo -e "  ${_CB_DIM}  ignore 관리: cpbak ignore list${_CB_RST}"
}

# ── save ──────────────────────────────────────────────────────────────────
_cpbak_cmd_save() {
    local memo="" scope=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--memo) memo="$2"; shift 2 ;;
            --scope)   scope="$2"; shift 2 ;;
            *)         scope="$1"; shift ;;
        esac
    done
    scope="${scope:-$_CPBAK_VCS_ROOT}"

    _cb_hd "cpbak save"
    echo -e "  ${_CB_RUN} VCS 루트: ${_CB_BOLD}${_CPBAK_VCS_ROOT}${_CB_RST}  (${_CPBAK_VCS_TYPE})"
    echo -e "  ${_CB_RUN} 스캔 범위: ${_CB_SKY}${scope}${_CB_RST}"
    [ -n "$memo" ] && echo -e "  ${_CB_RUN} 메모: ${memo}"
    echo ""

    _cpbak_get_files "$scope"

    [ ${#_CB_FILES_IGNORED[@]} -gt 0 ] && \
        echo -e "  ${_CB_IGN} ignore 제외: ${#_CB_FILES_IGNORED[@]}개"

    local q_selected=()
    if [ ${#_CB_FILES_Q_AMB[@]} -gt 0 ]; then
        echo -e "  ${_CB_WARN} 미결정 미추적 파일 ${#_CB_FILES_Q_AMB[@]}개 — 백업할 항목 선택:"
        while IFS= read -r line; do
            [ -n "$line" ] && q_selected+=("$line")
        done < <(_cpbak_fzf_select "미추적 파일 백업 선택" "${_CB_FILES_Q_AMB[@]}")
        echo ""
    fi

    local copy_list=()
    copy_list+=("${_CB_FILES_M[@]}" "${_CB_FILES_A[@]}" "${_CB_FILES_Q_INC[@]}" "${q_selected[@]}")

    if [ ${#copy_list[@]} -eq 0 ]; then
        echo -e "  ${_CB_WARN} 백업할 파일이 없습니다."; return 0
    fi

    local timestamp; timestamp=$(date +%Y%m%d_%H%M%S)
    local proj_name; proj_name=$(basename "$PWD")
    local backup_dir="${CPBAK_BACKUP_ROOT}/${proj_name}_${timestamp}"
    mkdir -p "$backup_dir"
    echo -e "  ${_CB_RUN} 백업 경로: ${_CB_BOLD}${backup_dir}${_CB_RST}"; echo ""

    local ok_cnt=0 fail_cnt=0
    for rel in "${copy_list[@]}"; do
        local src="${_CPBAK_VCS_ROOT}/${rel}"
        local dst="${backup_dir}/${rel}"
        mkdir -p "$(dirname "$dst")"
        if cp -p "$src" "$dst" 2>/dev/null; then
            echo -e "  ${_CB_OK} ${rel}"; (( ok_cnt++ ))
        else
            echo -e "  ${_CB_FAIL} ${_CB_RED}${rel}${_CB_RST}  (복사 실패)"; (( fail_cnt++ ))
        fi
    done

    {
        echo "CPBAK_DATE=\"${timestamp}\""
        echo "CPBAK_VCS_ROOT=\"${_CPBAK_VCS_ROOT}\""
        echo "CPBAK_VCS_TYPE=\"${_CPBAK_VCS_TYPE}\""
        echo "CPBAK_SCOPE=\"${scope}\""
        echo "CPBAK_MEMO=\"${memo}\""
        echo "CPBAK_FILES_M=($(printf '%q ' "${_CB_FILES_M[@]}"))"
        echo "CPBAK_FILES_A=($(printf '%q ' "${_CB_FILES_A[@]}"))"
        echo "CPBAK_FILES_D=($(printf '%q ' "${_CB_FILES_D[@]}"))"
        echo "CPBAK_FILES_Q=($(printf '%q ' "${_CB_FILES_Q_INC[@]}" "${q_selected[@]}"))"
    } > "${backup_dir}/.cpbak_meta"

    mkdir -p "$CPBAK_CONF_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | save | ${ok_cnt}파일 | ${backup_dir} | ${memo}" >> "$CPBAK_LOG"

    echo ""; _cb_ln
    echo -e "  ${_CB_OK} 완료: ${_CB_GREEN}${ok_cnt}개${_CB_RST} 복사  /  ${_CB_RED}${fail_cnt}개${_CB_RST} 실패"
    [ ${#_CB_FILES_D[@]} -gt 0 ] && \
        echo -e "  ${_CB_WARN} 삭제 파일 ${#_CB_FILES_D[@]}개는 복사 불가 — 메타에 목록만 기록됨"
    echo -e "  ${_CB_RUN} 복원 시: ${_CB_BOLD}cpbak restore ${proj_name}_${timestamp}${_CB_RST}"
}

# ── 백업 디렉토리 경로 확인 ───────────────────────────────────────────────
_cpbak_resolve_backup_dir() {
    local target="$1" out
    if [ "$target" = "last" ]; then
        out=$(ls -dt "${CPBAK_BACKUP_ROOT}"/*/  2>/dev/null | head -1)
        out="${out%/}"
        if [ -z "$out" ]; then
            echo -e "${_CB_FAIL} 백업 없음: ${CPBAK_BACKUP_ROOT}" >&2
            return 1
        fi
    else
        out="${CPBAK_BACKUP_ROOT}/${target}"
    fi
    echo "$out"
}

# ── restore ───────────────────────────────────────────────────────────────
_cpbak_cmd_restore() {
    local target="last"
    local dry_run=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=1 ;;
            *)         target="$1" ;;
        esac
        shift
    done

    local backup_dir
    backup_dir=$(_cpbak_resolve_backup_dir "$target") || return 1
    [ ! -d "$backup_dir" ] && echo -e "${_CB_FAIL} 백업 없음: ${backup_dir}" >&2 && return 1

    local meta_file="${backup_dir}/.cpbak_meta"
    if [ -f "$meta_file" ]; then
        source "$meta_file" 2>/dev/null || \
            echo -e "${_CB_WARN} 메타 파일 읽기 실패 — 폴더 구조로 복원 시도"
    else
        echo -e "${_CB_WARN} 메타 파일 없음 — 폴더 구조로 복원 시도"
    fi

    _cb_hd "cpbak restore"
    echo -e "  ${_CB_RUN} 백업 시각: ${_CB_BOLD}${CPBAK_DATE:-${backup_dir##*/}}${_CB_RST}"
    echo -e "  ${_CB_RUN} 메모: ${CPBAK_MEMO:-(없음)}"
    echo -e "  ${_CB_RUN} 원본 루트: ${CPBAK_VCS_ROOT:-$_CPBAK_VCS_ROOT}"
    [ -n "$dry_run" ] && echo -e "  ${_CB_WARN} ${_CB_YELLOW}DRY-RUN 모드${_CB_RST}"
    echo ""

    # VCS 루트 불일치 경고
    if [ -n "$CPBAK_VCS_ROOT" ] && [ "$CPBAK_VCS_ROOT" != "$_CPBAK_VCS_ROOT" ]; then
        echo -e "  ${_CB_WARN} ${_CB_RED}VCS 루트 불일치!${_CB_RST}"
        echo -e "       백업 시: ${_CB_YELLOW}${CPBAK_VCS_ROOT}${_CB_RST}"
        echo -e "       현재:    ${_CB_YELLOW}${_CPBAK_VCS_ROOT}${_CB_RST}"
        echo -e "       파일이 잘못된 경로에 복원될 수 있습니다."
        printf "  계속하시겠습니까? [y/N]: "
        local cont; read -r cont
        [[ ! "$cont" =~ ^[yY]$ ]] && echo -e "  취소했습니다." && return 0
        echo ""
    fi

    local restore_files=()
    if [ -n "${CPBAK_FILES_M+x}" ] || [ -n "${CPBAK_FILES_A+x}" ] || [ -n "${CPBAK_FILES_Q+x}" ]; then
        restore_files+=("${CPBAK_FILES_M[@]}" "${CPBAK_FILES_A[@]}" "${CPBAK_FILES_Q[@]}")
    else
        while IFS= read -r f; do restore_files+=("$f"); done \
            < <(find "$backup_dir" -not -name '.cpbak_meta' -type f | sed "s|^${backup_dir}/||")
    fi

    [ ${#restore_files[@]} -eq 0 ] && echo -e "  ${_CB_WARN} 복원할 파일 없음" >&2 && return 1

    echo -e "  복원 대상 ${_CB_BOLD}${#restore_files[@]}개${_CB_RST}:"
    for f in "${restore_files[@]}"; do echo -e "    ${_CB_GREEN}←${_CB_RST}  $f"; done
    echo ""

    if [ -z "$dry_run" ]; then
        printf "  ${_CB_WARN} 정말 복원하시겠습니까? [y/N]: "
        local confirm; read -r confirm
        [[ ! "$confirm" =~ ^[yY]$ ]] && echo -e "  취소했습니다." && return 0
        echo ""
    fi

    local vcs_root="${CPBAK_VCS_ROOT:-$_CPBAK_VCS_ROOT}"
    local ok_cnt=0 fail_cnt=0
    for rel in "${restore_files[@]}"; do
        local src="${backup_dir}/${rel}"
        local dst="${vcs_root}/${rel}"
        [ ! -f "$src" ] && echo -e "  ${_CB_WARN} 백업 없음: ${rel}" && continue
        if [ -n "$dry_run" ]; then
            echo -e "  ${_CB_DIM}[dry]${_CB_RST} ${rel}"
        else
            mkdir -p "$(dirname "$dst")"
            if cp -p "$src" "$dst" 2>/dev/null; then
                echo -e "  ${_CB_OK} ${rel}"; (( ok_cnt++ ))
            else
                echo -e "  ${_CB_FAIL} ${_CB_RED}${rel}${_CB_RST}"; (( fail_cnt++ ))
            fi
        fi
    done

    if [ -z "$dry_run" ]; then
        mkdir -p "$CPBAK_CONF_DIR"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | restore | ${ok_cnt}파일 | from ${backup_dir}" >> "$CPBAK_LOG"
        echo ""; _cb_ln
        echo -e "  ${_CB_OK} 완료: ${_CB_GREEN}${ok_cnt}개${_CB_RST} 복원  /  ${_CB_RED}${fail_cnt}개${_CB_RST} 실패"
    fi

    if [ -n "${CPBAK_FILES_D+x}" ] && [ ${#CPBAK_FILES_D[@]} -gt 0 ]; then
        echo ""; echo -e "  ${_CB_WARN} 백업 당시 삭제된 파일 ${#CPBAK_FILES_D[@]}개는 복원 불가:"
        for f in "${CPBAK_FILES_D[@]}"; do echo -e "    ${_CB_DEL} ${_CB_DIM}$f${_CB_RST}  → svn revert 사용"; done
    fi
}

# ── list ──────────────────────────────────────────────────────────────────
_cpbak_cmd_list() {
    _cb_hd "cpbak list — 백업 목록"

    local dirs=()
    while IFS= read -r d; do dirs+=("${d%/}"); done \
        < <(ls -dt "${CPBAK_BACKUP_ROOT}"/*/  2>/dev/null)

    if [ ${#dirs[@]} -eq 0 ]; then
        echo -e "  ${_CB_DIM}(백업 없음: ${CPBAK_BACKUP_ROOT})${_CB_RST}"
        return 0
    fi

    printf "  ${_CB_BOLD}%-36s  %6s  %s${_CB_RST}\n" "이름" "파일수" "메모"
    _cb_ln

    local d
    for d in "${dirs[@]}"; do
        local meta="${d}/.cpbak_meta"
        local memo cnt
        if [ -f "$meta" ]; then
            source "$meta" 2>/dev/null
            cnt=$(( ${#CPBAK_FILES_M[@]} + ${#CPBAK_FILES_A[@]} + ${#CPBAK_FILES_Q[@]} ))
            memo="${CPBAK_MEMO:-(메모 없음)}"
        else
            cnt=$(find "$d" -not -name '.cpbak_meta' -type f 2>/dev/null | wc -l)
            memo="${_CB_DIM}(메타 없음)${_CB_RST}"
        fi
        printf "  %-36s  %5s개  %s\n" "${d##*/}" "$cnt" "$memo"
    done

    echo ""
    echo -e "  ${_CB_DIM}총 ${#dirs[@]}개 백업  |  cpbak restore <이름>  |  cpbak diff <이름>  |  cpbak clean --days <N>${_CB_RST}"
}

# ── diff ──────────────────────────────────────────────────────────────────
_cpbak_cmd_diff() {
    local target="last"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) ;;  # 무시 (diff는 항상 read-only)
            *)         target="$1" ;;
        esac
        shift
    done

    local backup_dir
    backup_dir=$(_cpbak_resolve_backup_dir "$target") || return 1
    [ ! -d "$backup_dir" ] && echo -e "${_CB_FAIL} 백업 없음: ${backup_dir}" >&2 && return 1

    local meta="${backup_dir}/.cpbak_meta"
    local vcs_root="" memo=""
    if [ -f "$meta" ]; then
        source "$meta" 2>/dev/null
        vcs_root="${CPBAK_VCS_ROOT:-$_CPBAK_VCS_ROOT}"
        memo="$CPBAK_MEMO"
    fi
    vcs_root="${vcs_root:-$_CPBAK_VCS_ROOT}"

    _cb_hd "cpbak diff — ${backup_dir##*/}"
    [ -n "$memo" ] && echo -e "  ${_CB_RUN} 메모: ${memo}"
    echo ""

    local diff_tool="diff"
    command -v colordiff >/dev/null 2>&1 && diff_tool="colordiff"

    local changed=0
    while IFS= read -r -d '' bak_file; do
        local rel="${bak_file#${backup_dir}/}"
        local cur="${vcs_root}/${rel}"

        if [ ! -f "$cur" ]; then
            echo -e "  ${_CB_WARN} ${_CB_YELLOW}${rel}${_CB_RST}  (현재 파일 없음 — 삭제됨)"
            (( changed++ ))
            continue
        fi

        local out; out=$($diff_tool -u "$bak_file" "$cur" 2>/dev/null)
        if [ -n "$out" ]; then
            echo -e "\n  ${_CB_BOLD}${_CB_CYAN}── ${rel} ──${_CB_RST}"
            echo "$out" | head -100
            (( changed++ ))
        fi
    done < <(find "$backup_dir" -not -name '.cpbak_meta' -type f -print0 | sort -z)

    echo ""
    if [ "$changed" -eq 0 ]; then
        echo -e "  ${_CB_OK} 변경 없음 (백업과 현재 파일이 동일)"
    else
        echo -e "  ${_CB_WARN} 변경된 파일: ${_CB_BOLD}${changed}개${_CB_RST}"
    fi
}

# ── clean ─────────────────────────────────────────────────────────────────
_cpbak_cmd_clean() {
    local days=7
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days|-d) days="$2"; shift 2 ;;
            *)         shift ;;
        esac
    done

    _cb_hd "cpbak clean — ${days}일 이상 된 백업 삭제"

    local old_dirs=()
    while IFS= read -r d; do
        old_dirs+=("$d")
    done < <(find "${CPBAK_BACKUP_ROOT}" -maxdepth 1 -mindepth 1 -type d -mtime "+${days}" 2>/dev/null | sort)

    if [ ${#old_dirs[@]} -eq 0 ]; then
        echo -e "  ${_CB_OK} ${days}일 이상 된 백업 없음"
        return 0
    fi

    echo -e "  삭제 대상 ${_CB_RED}${#old_dirs[@]}개${_CB_RST}:"
    local d
    for d in "${old_dirs[@]}"; do
        local size; size=$(du -sh "$d" 2>/dev/null | cut -f1)
        local memo="(메모 없음)"
        if [ -f "${d}/.cpbak_meta" ]; then
            source "${d}/.cpbak_meta" 2>/dev/null
            memo="${CPBAK_MEMO:-(메모 없음)}"
        fi
        printf "  ${_CB_RED}✖${_CB_RST}  %-36s  %6s  %s\n" "${d##*/}" "$size" "$memo"
    done

    echo ""
    printf "  ${_CB_WARN} 정말 삭제하시겠습니까? [y/N]: "
    local confirm; read -r confirm
    [[ ! "$confirm" =~ ^[yY]$ ]] && echo -e "  취소했습니다." && return 0

    for d in "${old_dirs[@]}"; do
        rm -rf "$d" && echo -e "  ${_CB_OK} 삭제: ${d##*/}"
    done
    echo ""
    echo -e "  ${_CB_OK} ${_CB_GREEN}${#old_dirs[@]}개 백업 삭제 완료${_CB_RST}"
}

# ── ignore ────────────────────────────────────────────────────────────────
_cpbak_cmd_ignore() {
    local subcmd="${1:-list}"; shift

    case "$subcmd" in
        list|ls)
            _cb_hd "cpbak ignore 목록"
            local proj_ignore="${_CPBAK_VCS_ROOT}/.cpbakignore"

            echo -e "  ${_CB_BOLD}글로벌${_CB_RST}  (${CPBAK_GLOBAL_IGNORE}):"
            if [ -f "$CPBAK_GLOBAL_IGNORE" ]; then
                local n=0
                while IFS= read -r line; do
                    [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
                    echo -e "    ${_CB_DIM}[g]${_CB_RST} ${_CB_YELLOW}${line}${_CB_RST}"; (( n++ ))
                done < "$CPBAK_GLOBAL_IGNORE"
                [ "$n" -eq 0 ] && echo -e "    ${_CB_DIM}(없음)${_CB_RST}"
            else
                echo -e "    ${_CB_DIM}(파일 없음)${_CB_RST}"
            fi

            echo ""
            echo -e "  ${_CB_BOLD}프로젝트${_CB_RST}  (${proj_ignore}):"
            if [ -f "$proj_ignore" ]; then
                local n=0
                while IFS= read -r line; do
                    [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]] && continue
                    echo -e "    ${_CB_DIM}[p]${_CB_RST} ${_CB_YELLOW}${line}${_CB_RST}"; (( n++ ))
                done < "$proj_ignore"
                [ "$n" -eq 0 ] && echo -e "    ${_CB_DIM}(없음)${_CB_RST}"
            else
                echo -e "    ${_CB_DIM}(파일 없음)${_CB_RST}"
            fi
            echo ""
            echo -e "  패턴 예시:  build_dir/*/iperf*/  |  .vscode/settings.json  |  *.min.js"
            ;;

        add)
            local global="" pattern=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -g|--global) global=1; shift ;;
                    *) pattern="$1"; shift ;;
                esac
            done
            if [ -z "$pattern" ]; then
                echo -e "${_CB_FAIL} 사용법: cpbak ignore add [-g] \"<패턴>\"" >&2; return 1
            fi
            if [ -n "$global" ]; then
                mkdir -p "$CPBAK_CONF_DIR"
                echo "$pattern" >> "$CPBAK_GLOBAL_IGNORE"
                echo -e "${_CB_OK} 글로벌 추가: ${_CB_YELLOW}${pattern}${_CB_RST}  (${CPBAK_GLOBAL_IGNORE})"
            else
                echo "$pattern" >> "${_CPBAK_VCS_ROOT}/.cpbakignore"
                echo -e "${_CB_OK} 프로젝트 추가: ${_CB_YELLOW}${pattern}${_CB_RST}  (${_CPBAK_VCS_ROOT}/.cpbakignore)"
            fi
            ;;

        rm|remove)
            local global="" pattern=""
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    -g|--global) global=1; shift ;;
                    *) pattern="$1"; shift ;;
                esac
            done
            [ -z "$pattern" ] && echo -e "${_CB_FAIL} 사용법: cpbak ignore rm [-g] \"<패턴>\"" >&2 && return 1
            local target_file
            [ -n "$global" ] && target_file="$CPBAK_GLOBAL_IGNORE" \
                             || target_file="${_CPBAK_VCS_ROOT}/.cpbakignore"
            [ ! -f "$target_file" ] && echo -e "${_CB_FAIL} 파일 없음: ${target_file}" >&2 && return 1
            local escaped; escaped=$(printf '%s\n' "$pattern" | sed 's/[[\.*^$()+?{|]/\\&/g')
            local tmp; tmp=$(mktemp)
            grep -v "^${escaped}$" "$target_file" > "$tmp" && mv "$tmp" "$target_file"
            echo -e "${_CB_OK} 제거: ${_CB_YELLOW}${pattern}${_CB_RST}"
            ;;

        edit)
            local global=""
            [[ "$1" == "-g" || "$1" == "--global" ]] && global=1
            local target_file
            if [ -n "$global" ]; then
                mkdir -p "$CPBAK_CONF_DIR"; touch "$CPBAK_GLOBAL_IGNORE"
                target_file="$CPBAK_GLOBAL_IGNORE"
            else
                touch "${_CPBAK_VCS_ROOT}/.cpbakignore"
                target_file="${_CPBAK_VCS_ROOT}/.cpbakignore"
            fi
            echo -e "${_CB_RUN} 편집: ${target_file}"
            ${EDITOR:-vi} "$target_file"
            ;;

        *)
            echo -e "${_CB_WARN} 알 수 없는 서브커맨드: $subcmd"
            echo -e "  사용법: cpbak ignore [list|add|rm|edit] ..."
            return 1 ;;
    esac
}

# ── init ──────────────────────────────────────────────────────────────────
_cpbak_init() {
    _cb_hd "cpbak init — 설치 마법사"

    # 1. 설정 디렉토리 생성
    mkdir -p "$CPBAK_CONF_DIR"
    echo -e "  ${_CB_OK} 설정 디렉토리: ${_CB_BOLD}${CPBAK_CONF_DIR}${_CB_RST}"

    # 1-1. 백업 경로 설정
    echo ""
    echo -e "  ${_CB_BOLD}백업 저장 경로 설정${_CB_RST}"
    echo -e "  현재 기본값: ${_CB_YELLOW}${CPBAK_BACKUP_ROOT}${_CB_RST}"
    printf "  변경할 경로 입력 (Enter = 기본값 유지): "
    local input_root; read -r input_root
    if [ -n "$input_root" ]; then
        # ~ 확장 처리
        input_root="${input_root/#\~/$HOME}"
        CPBAK_BACKUP_ROOT="$input_root"
        echo -e "  ${_CB_OK} 백업 경로: ${_CB_GREEN}${CPBAK_BACKUP_ROOT}${_CB_RST}"
    else
        echo -e "  ${_CB_OK} 백업 경로: ${_CB_DIM}${CPBAK_BACKUP_ROOT} (기본값)${_CB_RST}"
    fi
    mkdir -p "$CPBAK_BACKUP_ROOT"
    echo ""

    # 2. ~/.bash_functions 에 source 등록
    local bash_funcs="$HOME/.bash_functions"
    if [ ! -f "$bash_funcs" ]; then
        touch "$bash_funcs"
        echo -e "  ${_CB_OK} ${bash_funcs} 생성"
    fi

    if grep -qF "cpbak.sh" "$bash_funcs" 2>/dev/null; then
        echo -e "  ${_CB_OK} bash_functions: ${_CB_DIM}이미 등록됨${_CB_RST}"
    else
        {
            echo ""
            echo "# cpbak — SVN/Git 수정 파일 백업 & 원복 도구"
            echo "[ -f \"${CPBAK_SELF}\" ] && source \"${CPBAK_SELF}\""
        } >> "$bash_funcs"
        echo -e "  ${_CB_OK} bash_functions: ${_CB_GREEN}source 등록 완료${_CB_RST}"
    fi

    # 3. ~/.bash_aliases 에 alias 등록
    local bash_aliases="$HOME/.bash_aliases"
    if [ ! -f "$bash_aliases" ]; then
        touch "$bash_aliases"
        echo -e "  ${_CB_OK} ${bash_aliases} 생성"
    fi

    if grep -qE "alias cpbak|alias.*_cpbak_main" "$bash_aliases" 2>/dev/null; then
        echo -e "  ${_CB_OK} bash_aliases: ${_CB_DIM}이미 등록됨${_CB_RST}"
    else
        {
            echo ""
            echo "## cpbak (SVN/Git 수정 파일 백업)"
            echo "alias cpbak='_cpbak_main'"
        } >> "$bash_aliases"
        echo -e "  ${_CB_OK} bash_aliases: ${_CB_GREEN}alias 등록 완료${_CB_RST}"
    fi

    # 4. 기본 config 생성 (없는 경우)
    if [ ! -f "$CPBAK_CONF" ]; then
        cat > "$CPBAK_CONF" <<EOF
# cpbak 설정 파일
CPBAK_BACKUP_ROOT="${CPBAK_BACKUP_ROOT}"
# CPBAK_USE_FZF="auto"    # fzf 사용: auto|on|off
# CPBAK_ALIAS="cpbak"     # alias 이름
EOF
        echo -e "  ${_CB_OK} config 파일 생성: ${CPBAK_CONF}"
    else
        # 이미 있으면 BACKUP_ROOT만 업데이트 (경로가 바뀐 경우)
        if grep -q "^CPBAK_BACKUP_ROOT=" "$CPBAK_CONF" 2>/dev/null; then
            sed -i "s|^CPBAK_BACKUP_ROOT=.*|CPBAK_BACKUP_ROOT=\"${CPBAK_BACKUP_ROOT}\"|" "$CPBAK_CONF"
        else
            echo "CPBAK_BACKUP_ROOT=\"${CPBAK_BACKUP_ROOT}\"" >> "$CPBAK_CONF"
        fi
        echo -e "  ${_CB_OK} config 업데이트: ${_CB_DIM}${CPBAK_CONF}${_CB_RST}"
    fi

    echo ""
    _cb_ln
    echo -e "  ${_CB_OK} ${_CB_GREEN}설치 완료${_CB_RST}"
    echo -e "  적용: ${_CB_BOLD}source ~/.bash_functions${_CB_RST}  또는 새 터미널 열기"
    echo -e "  테스트: ${_CB_BOLD}cpbak help${_CB_RST}"
}

# ── help ──────────────────────────────────────────────────────────────────
_cpbak_help() {
    _cb_hd "cpbak v1.3 — SVN/Git 수정 파일 백업 & 원복 도구"
    echo -e "  ${_CB_BOLD}사용법:${_CB_RST}"
    echo -e "    cpbak init"
    echo -e "    cpbak status  [-v|--verbose] [--scope <경로>]"
    echo -e "    cpbak save    [-m <메모>] [--scope <경로>]"
    echo -e "    cpbak restore [<이름 | last>] [--dry-run]"
    echo -e "    cpbak list"
    echo -e "    cpbak diff    [<이름 | last>]"
    echo -e "    cpbak clean   [--days <N>]"
    echo -e "    cpbak ignore  list | add [-g] \"<패턴>\" | rm [-g] \"<패턴>\" | edit [-g]"
    echo ""
    echo -e "  ${_CB_BOLD}예시:${_CB_RST}"
    echo -e "    cpbak init                                 # 최초 설치"
    echo -e "    cpbak status                               # 수정 파일 미리보기"
    echo -e "    cpbak status -v --scope davo/feeds         # 범위 지정 + 제외 목록 표시"
    echo -e "    cpbak save -m \"IPv6 작업 전\"              # 백업 생성"
    echo -e "    cpbak list                                 # 백업 목록 + 메모 표시"
    echo -e "    cpbak diff last                            # 최근 백업 vs 현재 diff"
    echo -e "    cpbak restore last                         # 최근 백업 복원"
    echo -e "    cpbak restore last --dry-run               # 복원 시뮬레이션"
    echo -e "    cpbak clean --days 7                       # 7일 이상 된 백업 삭제"
    echo -e "    cpbak ignore add \"build_dir/*/iperf*/\"    # iperf 패키지 무시"
    echo -e "    cpbak ignore add -g \".vscode/settings.json\"  # 글로벌 무시"
    echo ""
    echo -e "  ${_CB_BOLD}데이터 경로:${_CB_RST}  ${CPBAK_CONF_DIR}/"
    echo -e "    ignore (글로벌): ${CPBAK_GLOBAL_IGNORE}"
    echo -e "    ignore (프로젝트): {VCS_ROOT}/.cpbakignore"
    echo -e "  ${_CB_BOLD}백업 경로:${_CB_RST}   ${CPBAK_BACKUP_ROOT}/"
    echo ""
}

# ── MAIN ──────────────────────────────────────────────────────────────────
_cpbak_main() {
    case "${1:-help}" in
        help|-h|--help) _cpbak_help; return 0 ;;
        init)           _cpbak_init; return 0 ;;
    esac

    if ! _cpbak_detect_vcs_root "$PWD"; then
        return 1
    fi

    case "${1}" in
        status|st)   shift; _cpbak_cmd_status "$@" ;;
        save|s)      shift; _cpbak_cmd_save "$@" ;;
        restore|r)   shift; _cpbak_cmd_restore "$@" ;;
        list|ls)     shift; _cpbak_cmd_list "$@" ;;
        diff|d)      shift; _cpbak_cmd_diff "$@" ;;
        clean)       shift; _cpbak_cmd_clean "$@" ;;
        ignore|ig)   shift; _cpbak_cmd_ignore "$@" ;;
        *)
            echo -e "${_CB_WARN} 알 수 없는 명령: $1"
            _cpbak_help; return 1 ;;
    esac
}

# ── sourced 모드 등록 ─────────────────────────────────────────────────────
_cpbak_register() {
    local a="${CPBAK_ALIAS:-cpbak}"
    eval "alias ${a}='_cpbak_main'"
}

# ── 소싱 vs 직접 실행 분기 ────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _cpbak_register
else
    _cpbak_main "$@"
fi
