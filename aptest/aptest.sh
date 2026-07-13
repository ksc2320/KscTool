#!/bin/bash
# ============================================================================
#  aptest.sh — AP 실기 디버그 테스트 하네스 v1.4.0
# ============================================================================
#  사용법: aptest <command> [args]
#
#  Commands:
#    init            설정/alias 초기화
#    status          현재 대상 AP와 실행 가드/모델 확인
#    smoke           기본 smoke suite 미리보기(dry-run)
#    smoke --live    사용자가 명시적으로 요청했을 때만 실제 AP SSH 테스트
#    script          SSH 불가 시 AP 콘솔/시리얼용 스크립트 생성
#    ssh [명령...]   AP로 SSH 접속(무인자=대화형 셸, 인자=원격 명령 1회 실행)
#    credential      모델 비밀번호 해석 가능 여부 확인(값 출력 안 함)
#    login-file      콘솔/시리얼 붙여넣기용 로그인 시퀀스 파일 생성
#    suite list      suite 목록
#    version         버전 출력
# ============================================================================

APTEST_VERSION='1.4.0'

_AT_RED='\033[1;31m'; _AT_GREEN='\033[1;32m'; _AT_YELLOW='\033[1;33m'
_AT_CYAN='\033[1;36m'; _AT_WHITE='\033[1;37m'; _AT_DIM='\033[0;90m'
_AT_RST='\033[0m'; _AT_BOLD='\033[1m'
_AT_OK="${_AT_GREEN}OK${_AT_RST}"; _AT_FAIL="${_AT_RED}FAIL${_AT_RST}"
_AT_RUN="${_AT_CYAN}RUN${_AT_RST}"; _AT_WARN="${_AT_YELLOW}WARN${_AT_RST}"

APTEST_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
APTEST_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APTEST_CONF_DIR="${APTEST_CONF_DIR:-$HOME/.devtools/aptest}"
APTEST_CONF="${APTEST_CONF:-$APTEST_CONF_DIR/config}"
APTEST_LOG="${APTEST_LOG:-$APTEST_CONF_DIR/history.log}"
APTEST_RUNNER="$APTEST_HOME/runner.py"

APTEST_HOST='172.30.1.254'
APTEST_USER='root'
APTEST_PORT='6022'
APTEST_CONNECT_TIMEOUT='5'
APTEST_COMMAND_TIMEOUT='20'
# 개발 AP는 재플래시로 호스트키가 상시 변경 → known_hosts 검사 무의미(매번 충돌). 키 인증만 사용.
APTEST_SSH_OPTIONS='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o GlobalKnownHostsFile=/dev/null -o LogLevel=ERROR'
APTEST_DEFAULT_SUITE="$APTEST_HOME/suites/smoke.json"
APTEST_ARTIFACT_DIR="$APTEST_CONF_DIR/artifacts"
APTEST_MODEL='DV03-609H'
APTEST_PASSWORD_FILE="$HOME/memo/personal/pswd/ap_pw.txt"
APTEST_PASSWORD_SECTION='KT'
APTEST_PASSWORD_INDEX='1'
APTEST_SSH_PASSWORD='auto'
APTEST_CONSOLE_WAKE_ENTER='on'
APTEST_CONSOLE_LOGIN_OUTPUT="$APTEST_CONF_DIR/console_login.txt"

_aptest_load_conf() {
    [ -f "$APTEST_CONF" ] && source "$APTEST_CONF" 2>/dev/null
}
_aptest_load_conf

_aptest_ln() { echo -e "${_AT_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_AT_RST}"; }
_aptest_hd() { _aptest_ln; echo -e "  ${_AT_BOLD}${_AT_WHITE}$*${_AT_RST}"; _aptest_ln; }

_aptest_help() {
    cat <<'EOF'
aptest — AP 실기 디버그 테스트 하네스

사용:
  aptest init [--force] [--host IP] [--user USER] [--port PORT]
  aptest status
  aptest smoke [--live] [--suite PATH] [--keep-going]
  aptest ssh [원격명령...]
  aptest script [--suite PATH] [--output /tmp/aptest_smoke.sh]
  aptest credential
  aptest login-file [--output PATH] [--enable-ssh]
  aptest suite list
  aptest version

원칙:
  - 기본 smoke는 dry-run이다.
  - 사용자가 "테스트까지 직접해봐"처럼 명시했을 때만 --live를 붙인다.
  - 비밀번호 원문은 출력하지 않고, 개인 password file에서 실행 시점에만 읽는다.
  - AP 콘솔 입력 전 깨우기 Enter가 필요하면 login-file에 빈 줄을 먼저 넣는다.
  - SSH가 막힌 이미지는 script 생성 후 AP 콘솔/시리얼에서 실행하고 fwdg/fwd get으로 회수한다.
  - login-file --enable-ssh: 로그인 시퀀스 뒤에 dropbear enable+start uci 명령을 덧붙인다.
    KT 팩토리 기본값(davo/files/etc/ori.config,fac.config/dropbear)이 SSH를 꺼놓으므로,
    재플래시/팩토리리셋마다 다시 꺼진다. SVN 소스는 절대 건드리지 않고 콘솔/시리얼 붙여넣기로만 해결한다.
EOF
}

_aptest_write_config() {
    mkdir -p "$APTEST_CONF_DIR"
    if [ -f "$APTEST_CONF" ] && [ "${force:-0}" != "1" ]; then
        echo -e "${_AT_WARN} config already exists: ${APTEST_CONF}"
        return 0
    fi
    cat > "$APTEST_CONF" <<EOF
# ~/.devtools/aptest/config
APTEST_HOST='${host:-$APTEST_HOST}'
APTEST_USER='${user:-$APTEST_USER}'
APTEST_PORT='${port:-$APTEST_PORT}'
APTEST_CONNECT_TIMEOUT='${APTEST_CONNECT_TIMEOUT}'
APTEST_COMMAND_TIMEOUT='${APTEST_COMMAND_TIMEOUT}'
APTEST_SSH_OPTIONS='${APTEST_SSH_OPTIONS}'
APTEST_DEFAULT_SUITE='${APTEST_DEFAULT_SUITE}'
APTEST_ARTIFACT_DIR='${APTEST_ARTIFACT_DIR}'
APTEST_MODEL='${APTEST_MODEL}'
APTEST_PASSWORD_FILE='${APTEST_PASSWORD_FILE}'
APTEST_PASSWORD_SECTION='${APTEST_PASSWORD_SECTION}'
APTEST_PASSWORD_INDEX='${APTEST_PASSWORD_INDEX}'
APTEST_SSH_PASSWORD='${APTEST_SSH_PASSWORD}'
APTEST_CONSOLE_WAKE_ENTER='${APTEST_CONSOLE_WAKE_ENTER}'
APTEST_CONSOLE_LOGIN_OUTPUT='${APTEST_CONSOLE_LOGIN_OUTPUT}'
EOF
    chmod 600 "$APTEST_CONF"
    [ -f "$APTEST_LOG" ] || echo "# datetime | command | result" > "$APTEST_LOG"
    echo -e "${_AT_OK} wrote ${APTEST_CONF}"
}

_aptest_init() {
    local force=0 host="" user="" port=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --force) force=1 ;;
            --host) host="$2"; shift ;;
            --user) user="$2"; shift ;;
            --port) port="$2"; shift ;;
            -h|--help) _aptest_help; return 0 ;;
            *) echo -e "${_AT_WARN} unknown option: $1"; return 1 ;;
        esac
        shift
    done

    _aptest_write_config

    local bf="$HOME/.bash_functions"
    local ba="$HOME/.bash_aliases"
    local source_line="[ -f \"$APTEST_SELF\" ] && source \"$APTEST_SELF\""

    touch "$bf" "$ba"
    if grep -qF "$APTEST_SELF" "$bf" 2>/dev/null; then
        echo -e "${_AT_DIM}source already registered${_AT_RST}"
    else
        {
            echo ""
            echo "# aptest — AP 실기 디버그 테스트 하네스"
            echo "$source_line"
        } >> "$bf"
        echo -e "${_AT_OK} source registered: ${bf}"
    fi

    if grep -qE "alias aptest=|_aptest_main" "$ba" 2>/dev/null; then
        echo -e "${_AT_DIM}alias already registered${_AT_RST}"
    else
        {
            echo ""
            echo "# aptest — AP 실기 디버그 테스트 하네스"
            echo "alias aptest='_aptest_main'"
        } >> "$ba"
        echo -e "${_AT_OK} alias registered: ${ba}"
    fi

    echo -e "${_AT_DIM}적용: source ~/.bash_functions && source ~/.bash_aliases${_AT_RST}"
}

_aptest_status() {
    _aptest_load_conf
    _aptest_hd "aptest status"
    echo -e "  target: ${_AT_WHITE}${APTEST_USER}@${APTEST_HOST}:${APTEST_PORT}${_AT_RST}"
    echo -e "  model : ${APTEST_MODEL}"
    echo -e "  suite : ${APTEST_DEFAULT_SUITE}"
    echo -e "  config: ${APTEST_CONF}"
    echo -e "  output: ${APTEST_ARTIFACT_DIR}"
    echo -e "  pwsrc : ${APTEST_PASSWORD_FILE} [${APTEST_PASSWORD_SECTION}] #${APTEST_PASSWORD_INDEX}"
    echo -e "  wake  : ${APTEST_CONSOLE_WAKE_ENTER}"
    echo ""
    echo -e "  ${_AT_WARN} live AP test requires: aptest smoke --live"
    echo -e "  ${_AT_DIM}Codex/Claude는 사용자가 직접 테스트 실행을 지시한 경우에만 --live 사용${_AT_RST}"
}

_aptest_trim() {
    local s="$*"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

_aptest_password_candidates() {
    local section="${1:-$APTEST_PASSWORD_SECTION}"
    local in_section=0 line candidate
    [ -f "$APTEST_PASSWORD_FILE" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        case "$line" in
            "["*"]")
                if [ "$line" = "[$section]" ]; then
                    in_section=1
                    continue
                fi
                [ "$in_section" = "1" ] && break
                ;;
        esac
        [ "$in_section" = "1" ] || continue
        candidate="$(_aptest_trim "$line")"
        [ -z "$candidate" ] && continue
        case "$candidate" in \#*) continue ;; esac
        candidate="${candidate%%\\r*}"
        candidate="${candidate%%\\p*}"
        if [[ "$candidate" == *:* ]]; then
            candidate="${candidate#*:}"
        elif [[ "$candidate" == */* ]]; then
            candidate="${candidate##*/}"
        fi
        candidate="$(_aptest_trim "$candidate")"
        [ -n "$candidate" ] && printf '%s\n' "$candidate"
    done < "$APTEST_PASSWORD_FILE"
}

_aptest_resolve_password() {
    local idx="${1:-$APTEST_PASSWORD_INDEX}"
    local -a candidates=()
    mapfile -t candidates < <(_aptest_password_candidates "$APTEST_PASSWORD_SECTION")
    if [ "$idx" -ge 1 ] && [ "$idx" -le "${#candidates[@]}" ]; then
        printf '%s' "${candidates[$((idx - 1))]}"
        return 0
    fi
    return 1
}

_aptest_credential() {
    _aptest_load_conf
    local pw
    if pw="$(_aptest_resolve_password)"; then
        echo -e "${_AT_OK} credential resolved"
        echo -e "  model  : ${APTEST_MODEL}"
        echo -e "  source : ${APTEST_PASSWORD_FILE} [${APTEST_PASSWORD_SECTION}] #${APTEST_PASSWORD_INDEX}"
        echo -e "  value  : ${_AT_DIM}(hidden)${_AT_RST}"
        return 0
    fi
    echo -e "${_AT_FAIL} credential not resolved"
    echo -e "  check: ${APTEST_PASSWORD_FILE} [${APTEST_PASSWORD_SECTION}] #${APTEST_PASSWORD_INDEX}"
    return 1
}

_aptest_suite_list() {
    find "$APTEST_HOME/suites" -maxdepth 1 -type f -name '*.json' -printf '%f\n' | sort
}

_aptest_runner_base() {
    local password="${APTEST_PASSWORD:-}"
    local want_password=1 arg
    for arg in "$@"; do
        case "$arg" in
            --dry-run|--emit-ap-script) want_password=0 ;;
        esac
    done
    if [ "$want_password" = "1" ]; then
        if [ "${APTEST_SSH_PASSWORD:-auto}" = "auto" ]; then
            password="$(_aptest_resolve_password 2>/dev/null || true)"
        elif [ "${APTEST_SSH_PASSWORD:-}" != "off" ]; then
            password="${APTEST_SSH_PASSWORD}"
        fi
    fi
    if [ -n "$password" ] && ! command -v sshpass >/dev/null 2>&1; then
        echo -e "${_AT_WARN} sshpass 없음 — password SSH 자동 로그인은 건너뜀. key 인증 또는 apt install sshpass 필요"
        password=""
    fi
    APTEST_SSH_PASSWORD_VALUE="$password" python3 "$APTEST_RUNNER" \
        --host "$APTEST_HOST" \
        --user "$APTEST_USER" \
        --port "$APTEST_PORT" \
        --connect-timeout "$APTEST_CONNECT_TIMEOUT" \
        --command-timeout "$APTEST_COMMAND_TIMEOUT" \
        --ssh-options "$APTEST_SSH_OPTIONS" \
        --artifacts-dir "$APTEST_ARTIFACT_DIR" \
        "$@"
}

_aptest_smoke() {
    _aptest_load_conf
    local live=0 suite="$APTEST_DEFAULT_SUITE" keep_going=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --live) live=1 ;;
            --suite) suite="$2"; shift ;;
            --keep-going) keep_going=1 ;;
            -h|--help) _aptest_help; return 0 ;;
            *) echo -e "${_AT_WARN} unknown option: $1"; return 1 ;;
        esac
        shift
    done

    local -a opts=(--suite "$suite")
    [ "$keep_going" = "1" ] && opts+=(--keep-going)
    if [ "$live" != "1" ]; then
        echo -e "${_AT_WARN} dry-run only. 사용자가 직접 실기 테스트를 요청했을 때만 --live 사용"
        opts+=(--dry-run)
    fi
    _aptest_runner_base "${opts[@]}"
}

_aptest_script() {
    _aptest_load_conf
    local suite="$APTEST_DEFAULT_SUITE" output="/tmp/aptest_smoke.sh"
    while [ $# -gt 0 ]; do
        case "$1" in
            --suite) suite="$2"; shift ;;
            --output) output="$2"; shift ;;
            -h|--help) _aptest_help; return 0 ;;
            *) echo -e "${_AT_WARN} unknown option: $1"; return 1 ;;
        esac
        shift
    done
    _aptest_runner_base --suite "$suite" --emit-ap-script "$output"
}

_aptest_login_file() {
    _aptest_load_conf
    local output="$APTEST_CONSOLE_LOGIN_OUTPUT" enable_ssh=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --output) output="$2"; shift ;;
            --enable-ssh) enable_ssh=1 ;;
            -h|--help) _aptest_help; return 0 ;;
            *) echo -e "${_AT_WARN} unknown option: $1"; return 1 ;;
        esac
        shift
    done
    local pw
    pw="$(_aptest_resolve_password)" || {
        echo -e "${_AT_FAIL} credential not resolved"
        return 1
    }
    mkdir -p "$(dirname "$output")"
    : > "$output"
    if [ "${APTEST_CONSOLE_WAKE_ENTER:-on}" = "on" ]; then
        printf '\n' >> "$output"
    fi
    printf '%s\n%s\n' "$APTEST_USER" "$pw" >> "$output"
    if [ "$enable_ssh" = "1" ]; then
        {
            printf "uci set dropbear.@dropbear[0].enable='1'\n"
            printf 'uci commit dropbear\n'
            printf '/etc/init.d/dropbear enable\n'
            printf '/etc/init.d/dropbear start\n'
        } >> "$output"
    fi
    chmod 600 "$output"
    echo -e "${_AT_OK} wrote console login sequence: ${output}"
    if [ "$enable_ssh" = "1" ]; then
        echo -e "  ${_AT_DIM}dropbear enable+start 시퀀스 포함 (KT 팩토리 기본값은 SSH off, SVN 원본은 미변경)${_AT_RST}"
    fi
    echo -e "  ${_AT_DIM}비밀번호는 출력하지 않음. 첫 줄 빈 Enter 포함 여부: ${APTEST_CONSOLE_WAKE_ENTER}${_AT_RST}"
}

_aptest_ssh() {
    _aptest_load_conf
    local pw=""
    if [ "${APTEST_SSH_PASSWORD:-auto}" = "auto" ]; then
        pw="$(_aptest_resolve_password 2>/dev/null || true)"
    elif [ "${APTEST_SSH_PASSWORD:-}" != "off" ]; then
        pw="${APTEST_SSH_PASSWORD}"
    fi
    # APTEST_SSH_OPTIONS는 의도적으로 워드 스플릿 (runner.py와 동일 옵션 문자열 공유)
    local -a cmd=(ssh $APTEST_SSH_OPTIONS -p "$APTEST_PORT" "${APTEST_USER}@${APTEST_HOST}")
    if [ -n "$pw" ] && command -v sshpass >/dev/null 2>&1; then
        SSHPASS="$pw" sshpass -e "${cmd[@]}" "$@"
    else
        [ -n "$pw" ] && echo -e "${_AT_WARN} sshpass 없음 — 비밀번호를 직접 입력해야 함 (apt install sshpass)"
        "${cmd[@]}" "$@"
    fi
}

_aptest_register() {
    _aptest_load_conf
    alias aptest='_aptest_main'
}

_aptest_main() {
    case "${1:-help}" in
        init) shift; _aptest_init "$@" ;;
        status) _aptest_status ;;
        smoke) shift; _aptest_smoke "$@" ;;
        ssh) shift; _aptest_ssh "$@" ;;
        script) shift; _aptest_script "$@" ;;
        credential) _aptest_credential ;;
        login-file) shift; _aptest_login_file "$@" ;;
        suite)
            case "${2:-list}" in
                list) _aptest_suite_list ;;
                *) echo -e "${_AT_WARN} unknown suite command: $2"; return 1 ;;
            esac
            ;;
        version|-V) echo "aptest v${APTEST_VERSION}" ;;
        help|-h|--help) _aptest_help ;;
        *) echo -e "${_AT_WARN} unknown command: $1"; _aptest_help; return 1 ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _aptest_register
else
    _aptest_main "$@"
fi
