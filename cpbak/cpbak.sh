#!/bin/bash
# ============================================================================
#  cpbak.sh — SVN/Git 수정 파일 백업 & 원복 도구 v1.0
# ============================================================================
#  단독 실행:  ./cpbak.sh <command> [args]
#  소싱(bash): source cpbak.sh  → 함수 등록
#
#  Commands:
#    status   필터 적용된 수정 파일 목록 미리보기
#    save     수정 파일 백업 (~/temp_copy/YYYYMMDD_HHMMSS/)
#    restore  백업 → 원위치 복원
#    help     도움말
#
#  설치:
#    ~/.bash_functions 말미에: source ~/KscTool/cpbak/cpbak.sh
#    ~/.bash_aliases에:        alias cpbak='_cpbak_main'
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

_cb_ln()  { echo -e "${_CB_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_CB_RST}"; }
_cb_hd()  { _cb_ln; echo -e "  ${_CB_BOLD}${_CB_WHITE}$*${_CB_RST}"; _cb_ln; }
_cb_sec() { echo -e "\n${_CB_CYAN}[${_CB_RST}${_CB_BOLD}$*${_CB_RST}${_CB_CYAN}]${_CB_RST}"; }

# ── 설정 경로 ─────────────────────────────────────────────────────────────
CPBAK_CONF_DIR="$HOME/.config/cpbak"
CPBAK_CONF="${CPBAK_CONF_DIR}/config"
CPBAK_LOG="${CPBAK_CONF_DIR}/history.log"

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
# 반환: _CPBAK_VCS_ROOT, _CPBAK_VCS_TYPE ("svn", "git", "both", "none")
_cpbak_detect_vcs_root() {
    local dir="${1:-$PWD}"
    _CPBAK_VCS_ROOT=""
    _CPBAK_VCS_TYPE="none"
    _CPBAK_GIT_ROOT=""

    # SVN 루트 감지 (LANG=C로 영문 출력 강제)
    local svn_root
    svn_root=$(LANG=C svn info "$dir" 2>/dev/null | grep '^Working Copy Root Path:' | awk '{print $NF}')
    if [ -n "$svn_root" ]; then
        _CPBAK_VCS_ROOT="$svn_root"
        _CPBAK_VCS_TYPE="svn"
    fi

    # Git 루트 감지
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

# ── 필터: M 파일 제외 판단 ────────────────────────────────────────────────
# 반환값: 0=제외, 1=포함
_cpbak_is_excluded_M() {
    local rel="$1"
    local fname
    fname=$(basename "$rel")

    # build_dir 하위이면서 dv_pkg가 아닌 경우 → autoconf 자동생성 파일 제외
    if [[ "$rel" == build_dir/* ]] && [[ "$rel" != build_dir/*/dv_pkg/* ]]; then
        case "$fname" in
            configure|config.guess|config.sub|config.h.in|install-sh|\
            ltmain.sh|sysoptions.h|.dep_files|Makefile.in)
                return 0 ;;
        esac
        # ipkg-* 하위 (패키징 산출물)
        [[ "$rel" == *ipkg-arm_* || "$rel" == *ipkg-install/* ]] && return 0
        # *.h.in 변형 (autoconf 자동생성)
        [[ "$fname" == *.h.in ]] && return 0
        # linux 커널 소스 하위 (직접 수정한 게 아니면 제외)
        # 단, 사용자가 직접 수정한 .dts 등은 포함하기 위해 linux-* 패턴만 제외
        # (아래 패턴: build_dir/.../linux-ipq53xx_*/linux-.../arch/.../...dts 제외 X → 포함)
    fi
    return 1
}

# ── 필터: ? 파일 → IDE 설정 포함 판단 ────────────────────────────────────
# 반환값: 0=포함(IDE설정), 1=해당없음
_cpbak_match_include_Q() {
    local rel="$1"
    case "$rel" in
        .vscode/*|.vscode) return 0 ;;
        .cursor/*|.cursor) return 0 ;;
        *.code-workspace)  return 0 ;;
    esac
    return 1
}

# ── 필터: ? 파일 → 빌드 산출물 제외 판단 ────────────────────────────────
# 반환값: 0=제외(빌드산출물), 1=해당없음
_cpbak_match_exclude_Q() {
    local rel="$1"
    local fname
    fname=$(basename "$rel")

    # build_dir 하위 (dv_pkg 포함, 미추적은 전부 빌드 산출물로 간주)
    [[ "$rel" == build_dir/* ]] && return 0
    # 오브젝트/라이브러리
    case "$fname" in
        *.o|*.so|*.so.*|*.a|*.d|*.tmp) return 0 ;;
    esac
    return 1
}

# ── SVN + Git status 파싱 + 필터 적용 ────────────────────────────────────
# 결과는 전역 배열에 저장
_cpbak_get_files() {
    local scope="${1:-$_CPBAK_VCS_ROOT}"
    local verbose="${2:-}"

    _CB_FILES_M=()       # 수정, 백업 대상
    _CB_FILES_A=()       # 추가, 백업 대상
    _CB_FILES_D=()       # 삭제, 목록만
    _CB_FILES_Q_INC=()   # 미추적, IDE설정 → 자동 포함
    _CB_FILES_Q_AMB=()   # 미추적, interactive 선택 필요
    _CB_FILES_M_EXCL=()  # M이지만 필터 제외됨 (통계용)

    local raw_lines=()
    local line flag rel

    # ── SVN status ──
    if [[ "$_CPBAK_VCS_TYPE" == svn || "$_CPBAK_VCS_TYPE" == both ]]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            flag="${line:0:1}"
            rel="${line:8}"
            # VCS 루트 기준 상대 경로로 변환
            rel="${rel#$_CPBAK_VCS_ROOT/}"

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
                    elif _cpbak_match_exclude_Q "$rel"; then
                        : # 빌드 산출물, 무시
                    else
                        _CB_FILES_Q_AMB+=("$rel")
                    fi
                    ;;
            esac
        done < <(svn status -q "$scope" 2>/dev/null)
    fi

    # ── Git status (SVN과 중복 제거) ──
    if [[ "$_CPBAK_VCS_TYPE" == git || "$_CPBAK_VCS_TYPE" == both ]]; then
        local git_root="${_CPBAK_GIT_ROOT:-$_CPBAK_VCS_ROOT}"
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            flag="${line:0:2}"
            rel="${line:3}"
            # VCS 루트 기준 상대 경로
            rel="${rel#$_CPBAK_VCS_ROOT/}"

            # SVN에서 이미 포함된 파일은 skip
            local already=0
            for f in "${_CB_FILES_M[@]}" "${_CB_FILES_A[@]}" "${_CB_FILES_D[@]}" \
                     "${_CB_FILES_Q_INC[@]}" "${_CB_FILES_Q_AMB[@]}" "${_CB_FILES_M_EXCL[@]}"; do
                [[ "$f" == "$rel" ]] && already=1 && break
            done
            [ "$already" -eq 1 ] && continue

            case "${flag:0:1}" in
                M|' ')
                    # XY 형식: 1번째=staged, 2번째=unstaged
                    local gflag="${flag// /M}"
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
                    elif _cpbak_match_exclude_Q "$rel"; then
                        :
                    else
                        _CB_FILES_Q_AMB+=("$rel")
                    fi
                    ;;
            esac
        done < <(git -C "$git_root" status --porcelain 2>/dev/null)
    fi
}

# ── fzf 또는 텍스트 기반 interactive 선택 ────────────────────────────────
# 인자: 타이틀, 항목들...
# 출력: 선택된 항목 (줄바꿈 구분)
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
        # fzf 없을 때: 텍스트 y/n 루프
        local result=()
        for item in "${items[@]}"; do
            printf "  ${_CB_WARN} 백업 포함? ${_CB_YELLOW}%-60s${_CB_RST} [y/N]: " "$item"
            local yn
            read -r yn
            [[ "$yn" =~ ^[yY]$ ]] && result+=("$item")
        done
        printf '%s\n' "${result[@]}"
    fi
}

# ── status 명령 ───────────────────────────────────────────────────────────
_cpbak_cmd_status() {
    local scope="${1:-}"
    local verbose=""
    while [[ "$1" == --* ]]; do
        [[ "$1" == "--verbose" || "$1" == "-v" ]] && verbose=1
        shift
    done
    scope="${1:-$_CPBAK_VCS_ROOT}"

    _cb_hd "cpbak status"
    echo -e "  ${_CB_RUN} VCS 루트: ${_CB_BOLD}${_CPBAK_VCS_ROOT}${_CB_RST}  (${_CPBAK_VCS_TYPE})"
    echo -e "  ${_CB_RUN} 스캔 범위: ${_CB_SKY}${scope}${_CB_RST}"

    _cpbak_get_files "$scope"

    _cb_sec "M - 수정  (백업 대상: ${#_CB_FILES_M[@]}개)"
    if [ ${#_CB_FILES_M[@]} -gt 0 ]; then
        for f in "${_CB_FILES_M[@]}"; do
            echo -e "  ${_CB_GREEN}M${_CB_RST}  $f"
        done
    else
        echo -e "  ${_CB_DIM}(없음)${_CB_RST}"
    fi

    if [ ${#_CB_FILES_A[@]} -gt 0 ]; then
        _cb_sec "A - 추가  (${#_CB_FILES_A[@]}개)"
        for f in "${_CB_FILES_A[@]}"; do
            echo -e "  ${_CB_CYAN}A${_CB_RST}  $f"
        done
    fi

    if [ ${#_CB_FILES_D[@]} -gt 0 ]; then
        _cb_sec "D - 삭제  (${#_CB_FILES_D[@]}개, 목록만 기록)"
        for f in "${_CB_FILES_D[@]}"; do
            echo -e "  ${_CB_DEL} ${_CB_DIM}$f${_CB_RST}"
        done
    fi

    if [ ${#_CB_FILES_Q_INC[@]} -gt 0 ]; then
        _cb_sec "? - IDE 설정  (자동 포함: ${#_CB_FILES_Q_INC[@]}개)"
        for f in "${_CB_FILES_Q_INC[@]}"; do
            echo -e "  ${_CB_NEW} ${_CB_MAG}$f${_CB_RST}"
        done
    fi

    if [ ${#_CB_FILES_Q_AMB[@]} -gt 0 ]; then
        _cb_sec "? - 미결정  (save 시 interactive 선택: ${#_CB_FILES_Q_AMB[@]}개)"
        for f in "${_CB_FILES_Q_AMB[@]}"; do
            echo -e "  ${_CB_WARN} ${_CB_YELLOW}$f${_CB_RST}"
        done
    fi

    _cb_sec "필터 제외  (autoconf 자동생성: ${#_CB_FILES_M_EXCL[@]}개)"
    if [ -n "$verbose" ] && [ ${#_CB_FILES_M_EXCL[@]} -gt 0 ]; then
        for f in "${_CB_FILES_M_EXCL[@]}"; do
            echo -e "  ${_CB_DIM}~  $f${_CB_RST}"
        done
    else
        echo -e "  ${_CB_DIM}(--verbose 로 목록 표시)${_CB_RST}"
    fi

    echo ""
    local total=$(( ${#_CB_FILES_M[@]} + ${#_CB_FILES_A[@]} + ${#_CB_FILES_Q_INC[@]} ))
    echo -e "  ${_CB_OK} 백업 예정: ${_CB_BOLD}${total}개${_CB_RST}  (미결정 ${#_CB_FILES_Q_AMB[@]}개 제외)"
}

# ── save 명령 ─────────────────────────────────────────────────────────────
_cpbak_cmd_save() {
    local memo="" scope="" verbose=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--memo) memo="$2"; shift 2 ;;
            -v|--verbose) verbose=1; shift ;;
            --scope) scope="$2"; shift 2 ;;
            *) scope="$1"; shift ;;
        esac
    done
    scope="${scope:-$_CPBAK_VCS_ROOT}"

    _cb_hd "cpbak save"
    echo -e "  ${_CB_RUN} VCS 루트: ${_CB_BOLD}${_CPBAK_VCS_ROOT}${_CB_RST}  (${_CPBAK_VCS_TYPE})"
    echo -e "  ${_CB_RUN} 스캔 범위: ${_CB_SKY}${scope}${_CB_RST}"
    [ -n "$memo" ] && echo -e "  ${_CB_RUN} 메모: ${memo}"
    echo ""

    _cpbak_get_files "$scope"

    # 미결정 파일 interactive 선택
    local q_selected=()
    if [ ${#_CB_FILES_Q_AMB[@]} -gt 0 ]; then
        echo -e "  ${_CB_WARN} 미결정 미추적 파일 ${#_CB_FILES_Q_AMB[@]}개 — 백업할 항목 선택:"
        while IFS= read -r line; do
            [ -n "$line" ] && q_selected+=("$line")
        done < <(_cpbak_fzf_select "미추적 파일 백업 선택" "${_CB_FILES_Q_AMB[@]}")
        echo ""
    fi

    # 최종 백업 목록
    local copy_list=()
    copy_list+=("${_CB_FILES_M[@]}" "${_CB_FILES_A[@]}" "${_CB_FILES_Q_INC[@]}" "${q_selected[@]}")

    if [ ${#copy_list[@]} -eq 0 ]; then
        echo -e "  ${_CB_WARN} 백업할 파일이 없습니다."
        return 0
    fi

    # 백업 디렉토리 생성
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${CPBAK_BACKUP_ROOT}/${timestamp}"
    mkdir -p "$backup_dir"

    echo -e "  ${_CB_RUN} 백업 경로: ${_CB_BOLD}${backup_dir}${_CB_RST}"
    echo ""

    # 파일 복사
    local ok_cnt=0 fail_cnt=0
    for rel in "${copy_list[@]}"; do
        local src="${_CPBAK_VCS_ROOT}/${rel}"
        local dst="${backup_dir}/${rel}"
        mkdir -p "$(dirname "$dst")"
        if cp -p "$src" "$dst" 2>/dev/null; then
            echo -e "  ${_CB_OK} ${rel}"
            (( ok_cnt++ ))
        else
            echo -e "  ${_CB_FAIL} ${_CB_RED}${rel}${_CB_RST}  (복사 실패)"
            (( fail_cnt++ ))
        fi
    done

    # 메타 파일 기록
    local meta_file="${backup_dir}/.cpbak_meta"
    {
        echo "CPBAK_DATE=\"${timestamp}\""
        echo "CPBAK_VCS_ROOT=\"${_CPBAK_VCS_ROOT}\""
        echo "CPBAK_VCS_TYPE=\"${_CPBAK_VCS_TYPE}\""
        echo "CPBAK_SCOPE=\"${scope}\""
        echo "CPBAK_MEMO=\"${memo}\""
        echo "CPBAK_FILES_M=($(printf '"%s" ' "${_CB_FILES_M[@]}"))"
        echo "CPBAK_FILES_A=($(printf '"%s" ' "${_CB_FILES_A[@]}"))"
        echo "CPBAK_FILES_D=($(printf '"%s" ' "${_CB_FILES_D[@]}"))"
        echo "CPBAK_FILES_Q=($(printf '"%s" ' "${_CB_FILES_Q_INC[@]}" "${q_selected[@]}"))"
    } > "$meta_file"

    # 히스토리 로그
    mkdir -p "$CPBAK_CONF_DIR"
    echo "$(date '+%Y-%m-%d %H:%M:%S') | save | ${ok_cnt}파일 | ${backup_dir} | ${memo}" >> "$CPBAK_LOG"

    echo ""
    _cb_ln
    echo -e "  ${_CB_OK} 완료: ${_CB_GREEN}${ok_cnt}개${_CB_RST} 복사  /  ${_CB_RED}${fail_cnt}개${_CB_RST} 실패"
    [ ${#_CB_FILES_D[@]} -gt 0 ] && \
        echo -e "  ${_CB_WARN} 삭제 파일 ${#_CB_FILES_D[@]}개는 복사 불가 — 메타에 목록만 기록됨"
    echo -e "  ${_CB_RUN} 복원 시: ${_CB_BOLD}cpbak restore ${timestamp}${_CB_RST}"
}

# ── restore 명령 ──────────────────────────────────────────────────────────
_cpbak_cmd_restore() {
    local target="${1:-last}"
    local dry_run=""
    [ "$2" = "--dry-run" ] && dry_run=1

    local backup_dir
    if [ "$target" = "last" ]; then
        # 가장 최근 백업 디렉토리
        backup_dir=$(ls -dt "${CPBAK_BACKUP_ROOT}"/[0-9]* 2>/dev/null | head -1)
        if [ -z "$backup_dir" ]; then
            echo -e "${_CB_FAIL} 백업 디렉토리가 없습니다: ${CPBAK_BACKUP_ROOT}" >&2
            return 1
        fi
    else
        backup_dir="${CPBAK_BACKUP_ROOT}/${target}"
    fi

    if [ ! -d "$backup_dir" ]; then
        echo -e "${_CB_FAIL} 백업 없음: ${backup_dir}" >&2
        return 1
    fi

    local meta_file="${backup_dir}/.cpbak_meta"
    if [ ! -f "$meta_file" ]; then
        echo -e "${_CB_WARN} 메타 파일 없음 — 폴더 구조로 복원을 시도합니다."
    else
        source "$meta_file" 2>/dev/null
    fi

    _cb_hd "cpbak restore"
    echo -e "  ${_CB_RUN} 백업 시각: ${_CB_BOLD}${CPBAK_DATE:-$(basename "$backup_dir")}${_CB_RST}"
    echo -e "  ${_CB_RUN} 메모: ${CPBAK_MEMO:-(없음)}"
    echo -e "  ${_CB_RUN} 원본 루트: ${CPBAK_VCS_ROOT:-$_CPBAK_VCS_ROOT}"
    [ -n "$dry_run" ] && echo -e "  ${_CB_WARN} ${_CB_YELLOW}DRY-RUN 모드 — 실제 복사 없음${_CB_RST}"
    echo ""

    # 복원 대상 파일 목록 (메타에 없으면 백업 폴더 탐색)
    local restore_files=()
    if [ -n "${CPBAK_FILES_M+x}" ] || [ -n "${CPBAK_FILES_A+x}" ] || [ -n "${CPBAK_FILES_Q+x}" ]; then
        restore_files+=("${CPBAK_FILES_M[@]}" "${CPBAK_FILES_A[@]}" "${CPBAK_FILES_Q[@]}")
    else
        while IFS= read -r f; do
            restore_files+=("$f")
        done < <(find "$backup_dir" -not -name '.cpbak_meta' -type f \
                     | sed "s|^${backup_dir}/||")
    fi

    if [ ${#restore_files[@]} -eq 0 ]; then
        echo -e "  ${_CB_WARN} 복원할 파일이 없습니다." >&2
        return 1
    fi

    echo -e "  복원 대상 ${_CB_BOLD}${#restore_files[@]}개${_CB_RST}:"
    for f in "${restore_files[@]}"; do
        echo -e "    ${_CB_GREEN}←${_CB_RST}  $f"
    done
    echo ""

    if [ -z "$dry_run" ]; then
        printf "  ${_CB_WARN} 정말 복원하시겠습니까? [y/N]: "
        local confirm
        read -r confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then
            echo -e "  취소했습니다."
            return 0
        fi
        echo ""
    fi

    local vcs_root="${CPBAK_VCS_ROOT:-$_CPBAK_VCS_ROOT}"
    local ok_cnt=0 fail_cnt=0
    for rel in "${restore_files[@]}"; do
        local src="${backup_dir}/${rel}"
        local dst="${vcs_root}/${rel}"
        if [ ! -f "$src" ]; then
            echo -e "  ${_CB_WARN} 백업 없음: ${rel}"
            continue
        fi
        if [ -n "$dry_run" ]; then
            echo -e "  ${_CB_DIM}[dry]${_CB_RST} ${rel}"
        else
            mkdir -p "$(dirname "$dst")"
            if cp -p "$src" "$dst" 2>/dev/null; then
                echo -e "  ${_CB_OK} ${rel}"
                (( ok_cnt++ ))
            else
                echo -e "  ${_CB_FAIL} ${_CB_RED}${rel}${_CB_RST}"
                (( fail_cnt++ ))
            fi
        fi
    done

    if [ -z "$dry_run" ]; then
        mkdir -p "$CPBAK_CONF_DIR"
        echo "$(date '+%Y-%m-%d %H:%M:%S') | restore | ${ok_cnt}파일 | from ${backup_dir}" >> "$CPBAK_LOG"
        echo ""
        _cb_ln
        echo -e "  ${_CB_OK} 완료: ${_CB_GREEN}${ok_cnt}개${_CB_RST} 복원  /  ${_CB_RED}${fail_cnt}개${_CB_RST} 실패"
    fi

    # 삭제 파일 경고
    if [ -n "${CPBAK_FILES_D+x}" ] && [ ${#CPBAK_FILES_D[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${_CB_WARN} 백업 당시 삭제된 파일 ${#CPBAK_FILES_D[@]}개는 복원 불가:"
        for f in "${CPBAK_FILES_D[@]}"; do
            echo -e "    ${_CB_DEL} ${_CB_DIM}$f${_CB_RST}  → svn revert 사용"
        done
    fi
}

# ── help ──────────────────────────────────────────────────────────────────
_cpbak_help() {
    _cb_hd "cpbak — SVN/Git 수정 파일 백업 & 원복 도구"
    echo -e "  ${_CB_BOLD}사용법:${_CB_RST}"
    echo -e "    cpbak status  [--verbose] [<경로>]"
    echo -e "    cpbak save    [-m <메모>] [--scope <경로>]"
    echo -e "    cpbak restore [<timestamp | last>] [--dry-run]"
    echo -e "    cpbak help"
    echo ""
    echo -e "  ${_CB_BOLD}예시:${_CB_RST}"
    echo -e "    cpbak status                       # 수정 파일 미리보기"
    echo -e "    cpbak save -m \"IPv6 작업 전 백업\"  # 백업 생성"
    echo -e "    cpbak restore last                 # 가장 최근 백업으로 복원"
    echo -e "    cpbak restore 20260403_153042      # 특정 시각 백업으로 복원"
    echo -e "    cpbak restore last --dry-run       # 복원 시뮬레이션"
    echo ""
    echo -e "  ${_CB_BOLD}백업 경로:${_CB_RST}  ${CPBAK_BACKUP_ROOT}/"
    echo -e "  ${_CB_BOLD}설정 파일:${_CB_RST}  ${CPBAK_CONF}"
    echo ""
}

# ── MAIN ──────────────────────────────────────────────────────────────────
_cpbak_main() {
    case "${1:-help}" in
        help|-h|--help) _cpbak_help; return 0 ;;
    esac

    # VCS 루트 감지 (실패 시 abort)
    if ! _cpbak_detect_vcs_root "$PWD"; then
        return 1
    fi

    case "${1:-help}" in
        status|st)  shift; _cpbak_cmd_status "$@" ;;
        save|s)     shift; _cpbak_cmd_save "$@" ;;
        restore|r)  shift; _cpbak_cmd_restore "$@" ;;
        *)
            echo -e "${_CB_WARN} 알 수 없는 명령: $1"
            _cpbak_help
            return 1
            ;;
    esac
}

# ── sourced 모드 등록 ─────────────────────────────────────────────────────
_cpbak_register() {
    _cpbak_load_conf
    local a="${CPBAK_ALIAS:-cpbak}"
    eval "alias ${a}='_cpbak_main'"
}

# ── 소싱 vs 직접 실행 분기 ────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _cpbak_register
else
    _cpbak_main "$@"
fi
