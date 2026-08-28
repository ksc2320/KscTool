#!/bin/bash
# dcbot — 디스코드로 들어온 말에 Claude 가 답하는 상주 봇
#
# 세션이 안 떠 있어도, 회사 밖에서도 디스코드로 물어보면 이 봇이 PC 에서 claude 를
# 돌려 답을 채널에 되돌려준다. 살아있는 세션이 채널을 보고 있으면(dclisten watch)
# 그쪽에 양보하고 손대지 않는다 — 한 메시지에 두 번 답하지 않기 위해서.
#
#   dcbot.sh run            포그라운드 실행 (시험용)
#   dcbot.sh start|stop     백그라운드 실행/중지
#   dcbot.sh status         상태
#   dcbot.sh logs [N]       최근 로그
#   dcbot.sh install        부팅 시 자동 실행 등록 (systemd 사용자 서비스)
#   dcbot.sh uninstall      자동 실행 해제
#
# 규칙
# - 화이트리스트(NOTI_DISCORD_ALLOW_USER) 사용자의 말만 처리한다.
# - 기본은 읽기 전용(Read/Grep/Glob). Bash·수정 도구는 주지 않는다.
#   COMMON.md 14: 명령 이름만 보는 allowlist 는 만들지 않는다.
# - 알림에 답장하면 그 세션 대화를 읽어 맥락으로 넣는다(원본 세션은 건드리지 않는다).
# - 봇 답변에 답장하면 그 봇 세션을 이어간다.
# - 앞에 ! 를 붙이면 살아있는 세션이 보고 있어도 봇이 처리한다.

set -uo pipefail

_B_CONF_DIR="$HOME/.devtools/noti"
_B_CONF="${_B_CONF_DIR}/config"
_B_THREADS="${_B_CONF_DIR}/threads.tsv"
_B_LAST="${_B_CONF_DIR}/bot_last_id"
_B_CUR="${_B_CONF_DIR}/bot_current_session"
_B_HB="${_B_CONF_DIR}/watcher.heartbeat"
_B_LOG="${_B_CONF_DIR}/bot.log"
_B_PID="${_B_CONF_DIR}/bot.pid"
_B_LOCK="${_B_CONF_DIR}/bot.lock"
_B_API="https://discord.com/api/v10"
_B_UNIT="$HOME/.config/systemd/user/noti-dcbot.service"
_B_SELF="$HOME/KscTool/noti/dcbot.sh"
_B_NOTI="$HOME/KscTool/noti/noti.sh"
_B_SESSREAD="$HOME/KscTool/noti/dcsession.sh"

[ -f "$_B_CONF" ] || { echo "설정이 없다: $_B_CONF" >&2; exit 1; }
# shellcheck disable=SC1090
. "$_B_CONF"

TOKEN="${NOTI_DISCORD_BOT_TOKEN:-}"
CHAN="${NOTI_DISCORD_CHANNEL_ID:-}"
ALLOW="${NOTI_DISCORD_ALLOW_USER:-}"
INTERVAL="${NOTI_BOT_INTERVAL:-20}"
MODE="${NOTI_BOT_MODE:-read}"            # read | full
CWD="${NOTI_BOT_CWD:-$HOME/memo}"
TIMEOUT="${NOTI_BOT_TIMEOUT:-600}"
IDLE="${NOTI_BOT_SESSION_IDLE:-1800}"    # 이 시간 안이면 같은 봇 세션을 이어간다
CTXTURNS="${NOTI_BOT_CTX_TURNS:-12}"

_b_log() { printf '%s | %s\n' "$(date '+%m-%d %H:%M:%S')" "$*" >> "$_B_LOG"; }
_b_curl() { curl -s -m 25 --config <(printf 'header = "Authorization: Bot %s"\n' "$TOKEN") "$@"; }

_b_require() {
    local bad=0
    [ -z "$TOKEN" ] && { echo "봇 토큰 없음 → noti setkey bot-token" >&2; bad=1; }
    [ -z "$CHAN" ]  && { echo "채널 ID 없음" >&2; bad=1; }
    [ -z "$ALLOW" ] && { echo "허용 사용자ID 없음 — 이게 없으면 아무나 PC에 명령한다" >&2; bad=1; }
    command -v claude >/dev/null || { echo "claude 명령을 못 찾겠다" >&2; bad=1; }
    return $bad
}

# 살아있는 세션이 채널을 보고 있나 (60초 안에 심장박동이 있으면 그렇다)
_b_watcher_alive() {
    [ -f "$_B_HB" ] || return 1
    local t now
    t=$(awk '{print $1}' "$_B_HB" 2>/dev/null)
    [ -z "$t" ] && return 1
    now=$(date +%s)
    [ $((now - t)) -lt 60 ]
}

_b_thread_lookup() {   # 메시지ID → "제목|세션ID"
    local ref="$1"
    [ -z "$ref" ] || [ ! -f "$_B_THREADS" ] && return 1
    awk -F'\t' -v id="$ref" '$1==id {hit=$4 "|" $2} END{if(hit){print hit; exit 0} exit 1}' "$_B_THREADS"
}

_b_uuid() { cat /proc/sys/kernel/random/uuid; }

# 봇이 직접 만든 세션인지 (안전하게 --resume 해도 되는 세션)
_b_is_bot_session() {
    grep -qxF "$1" "${_B_CONF_DIR}/bot_sessions" 2>/dev/null
}
_b_mark_bot_session() { echo "$1" >> "${_B_CONF_DIR}/bot_sessions"; }

# 답을 채널에 되돌린다. 1800자씩 잘라 보내고, 세션ID를 매핑에 남겨
# 그 답변에 답장하면 대화가 이어지게 한다.
_b_post() {
    local sess="$1" text="$2" first=1 chunk
    while [ -n "$text" ]; do
        chunk=$(printf '%s' "$text" | head -c 1800)
        text=$(printf '%s' "$text" | tail -c +1801)
        if [ $first -eq 1 ]; then
            printf '%s' "$chunk" | "$_B_NOTI" -t "봇 답변" -l info -s "$sess" -q
            first=0
        else
            printf '%s' "$chunk" | "$_B_NOTI" -t "봇 답변 (계속)" -l info -s "$sess" -q
        fi
    done
}

_b_claude_args() {
    if [ "$MODE" = "full" ]; then
        printf '%s' "--permission-mode bypassPermissions"
    else
        # 쉼표로 붙여야 한 덩어리로 들어간다 (아래 프롬프트 전달 주석 참고)
        printf '%s' "--allowedTools Read,Grep,Glob"
    fi
}

# 메시지 한 건 처리
_b_handle() {
    local content="$1" ref="$2" mid="$3"
    local look title src_sess sess resume=0 ctx="" prompt cwd out rc

    # ! 로 시작하면 강제 처리 표시만 떼고 진행
    case "$content" in "!"*) content="${content#!}" ;; esac

    if [ -n "$ref" ] && look=$(_b_thread_lookup "$ref"); then
        title="${look%%|*}"; src_sess="${look##*|}"
        if _b_is_bot_session "$src_sess"; then
            sess="$src_sess"; resume=1
            _b_log "답장→봇세션 이어감 ${sess:0:8} (원본: $title)"
        else
            # 살아있을 수 있는 세션은 건드리지 않는다. 대화만 읽어 맥락으로 넣는다.
            ctx=$("$_B_SESSREAD" ctx "$src_sess" "$CTXTURNS" 2>/dev/null)
            cwd=$("$_B_SESSREAD" cwd "$src_sess" 2>/dev/null)
            sess=$(_b_uuid); _b_mark_bot_session "$sess"
            _b_log "답장→세션 ${src_sess:0:8} 맥락 주입, 새 봇세션 ${sess:0:8} (원본: $title)"
        fi
    else
        # 일반 메시지: 최근에 쓰던 봇 세션이 있으면 이어간다
        local cur curt now
        if [ -f "$_B_CUR" ]; then
            curt=$(awk '{print $1}' "$_B_CUR"); cur=$(awk '{print $2}' "$_B_CUR")
            now=$(date +%s)
            if [ -n "$cur" ] && [ $((now - curt)) -lt "$IDLE" ]; then
                sess="$cur"; resume=1
                _b_log "일반→봇세션 이어감 ${sess:0:8}"
            fi
        fi
        if [ -z "${sess:-}" ]; then
            sess=$(_b_uuid); _b_mark_bot_session "$sess"
            _b_log "일반→새 봇세션 ${sess:0:8}"
        fi
    fi

    printf '%s %s\n' "$(date +%s)" "$sess" > "$_B_CUR"

    if [ -n "$ctx" ]; then
        prompt=$(printf '아래는 다른 Claude Code 세션(%s)의 최근 대화다. 사용자가 그 세션이 보낸 알림에 답장했다.\n\n%s\n\n---\n사용자의 답장: %s\n\n답은 휴대폰에서 읽는다. 3~5줄로 짧게, 결론부터.' \
                 "${src_sess:0:8}" "$ctx" "$content")
    else
        prompt=$(printf '%s\n\n(휴대폰에서 읽는 답이다. 3~5줄로 짧게, 결론부터.)' "$content")
    fi

    [ -z "${cwd:-}" ] && cwd="$CWD"
    [ -d "$cwd" ] || cwd="$HOME"

    local args; args=$(_b_claude_args)
    _b_log "실행: cwd=$cwd mode=$MODE resume=$resume sess=${sess:0:8}"
    # 프롬프트는 표준입력으로 넘긴다. --allowedTools 는 값을 여러 개 받는 옵션이라
    # 인자로 붙이면 질문까지 도구 이름으로 삼켜서 "Input must be provided" 로 죽는다.
    if [ "$resume" = "1" ]; then
        out=$(cd "$cwd" && printf '%s' "$prompt" | timeout "$TIMEOUT" claude -p --resume "$sess" $args 2>&1); rc=$?
    else
        out=$(cd "$cwd" && printf '%s' "$prompt" | timeout "$TIMEOUT" claude -p --session-id "$sess" $args 2>&1); rc=$?
    fi

    if [ $rc -eq 124 ]; then
        out="(시간 초과 ${TIMEOUT}초 — 너무 오래 걸려 중단했습니다)"
    elif [ $rc -ne 0 ]; then
        _b_log "claude 실패 rc=$rc: $(printf '%s' "$out" | head -c 200)"
        out=$(printf '(실행 실패 rc=%s)\n%s' "$rc" "$(printf '%s' "$out" | tail -c 600)")
    fi
    [ -z "$out" ] && out="(빈 응답)"

    _b_post "$sess" "$out"
    _b_log "답변 전송 완료 (${#out}자)"
}

_b_poll_once() {
    local last resp msgs line mid uid content ref newest
    last=$( [ -f "$_B_LAST" ] && cat "$_B_LAST" || echo "" )
    if [ -z "$last" ]; then
        last=$(_b_curl "${_B_API}/channels/${CHAN}/messages?limit=1" | jq -r '.[0].id // empty')
        [ -n "$last" ] && printf '%s' "$last" > "$_B_LAST"
        return 0
    fi
    resp=$(_b_curl "${_B_API}/channels/${CHAN}/messages?after=${last}&limit=25") || return 0
    printf '%s' "$resp" | jq -e 'type=="array"' >/dev/null 2>&1 || return 0
    msgs=$(printf '%s' "$resp" | jq -c 'reverse | .[]
        | select(.webhook_id == null) | select(.author.bot != true)
        | {id, uid: .author.id, content, ref: (.message_reference.message_id // "")}')
    if [ -z "$msgs" ]; then
        newest=$(printf '%s' "$resp" | jq -r 'if length>0 then (max_by(.id|tonumber).id) else empty end')
        [ -n "$newest" ] && printf '%s' "$newest" > "$_B_LAST"
        return 0
    fi

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        mid=$(printf '%s' "$line" | jq -r '.id')
        uid=$(printf '%s' "$line" | jq -r '.uid')
        content=$(printf '%s' "$line" | jq -r '.content')
        ref=$(printf '%s' "$line" | jq -r '.ref')
        printf '%s' "$mid" > "$_B_LAST"

        [ "$uid" != "$ALLOW" ] && { _b_log "무시: 허용 안 된 사용자 $uid"; continue; }
        [ -z "$content" ] && { _b_log "무시: 빈 본문 $mid"; continue; }

        # 살아있는 세션이 보고 있으면 양보한다 (! 로 시작하면 봇이 처리)
        case "$content" in
            "!"*) ;;
            *) if _b_watcher_alive; then
                   _b_log "양보: 살아있는 세션이 감시 중 — $(printf '%s' "$content" | head -c 40)"
                   continue
               fi ;;
        esac

        _b_log "처리 시작: $(printf '%s' "$content" | head -c 60)"
        _b_handle "$content" "$ref" "$mid"
    done <<< "$msgs"
}

_b_cmd_run() {
    _b_require || return 1
    mkdir -p "$_B_CONF_DIR"
    exec 9>"$_B_LOCK"
    flock -n 9 || { echo "이미 돌고 있다 (lock)" >&2; return 1; }
    _b_log "── dcbot 시작 (mode=$MODE, ${INTERVAL}초 간격, cwd=$CWD) ──"
    echo "dcbot 시작 — mode=$MODE, ${INTERVAL}초 간격. 로그: $_B_LOG"
    trap '_b_log "── dcbot 종료 ──"; exit 0' TERM INT
    while true; do
        _b_poll_once || true
        sleep "$INTERVAL"
    done
}

_b_cmd_start() {
    _b_require || return 1
    if _b_cmd_status >/dev/null 2>&1; then echo "이미 돌고 있다."; return 0; fi
    nohup "$_B_SELF" run >>"$_B_LOG" 2>&1 &
    echo $! > "$_B_PID"
    sleep 1
    _b_cmd_status
}

_b_cmd_stop() {
    local pid
    if systemctl --user is-active --quiet noti-dcbot 2>/dev/null; then
        systemctl --user stop noti-dcbot && echo "systemd 서비스 중지"
    fi
    [ -f "$_B_PID" ] && pid=$(cat "$_B_PID")
    if [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" && echo "중지 (pid $pid)"
    else
        pkill -f "dcbot.sh run" && echo "중지 (pkill)" || echo "돌고 있지 않다."
    fi
    rm -f "$_B_PID"
}

_b_cmd_status() {
    local ok=1
    if systemctl --user is-active --quiet noti-dcbot 2>/dev/null; then
        echo "● systemd 서비스로 실행 중 (noti-dcbot)"; ok=0
    elif pgrep -f "dcbot.sh run" >/dev/null; then
        echo "● 실행 중 (pid $(pgrep -f 'dcbot.sh run' | tr '\n' ' '))"; ok=0
    else
        echo "○ 실행 중 아님"
    fi
    printf '  모드      : %s%s\n' "$MODE" "$([ "$MODE" = full ] && echo '   전체 권한 주의')"
    printf '  기본 폴더 : %s\n' "$CWD"
    printf '  폴링 간격 : %s초 / 시간제한 %s초\n' "$INTERVAL" "$TIMEOUT"
    printf '  자동 실행 : %s\n' "$(systemctl --user is-enabled noti-dcbot 2>/dev/null || echo '미등록')"
    if _b_watcher_alive; then
        printf '  세션 감시 : 있음 (%s) — 일반 메시지는 그쪽이 처리, 봇은 양보\n' "$(awk '{print substr($2,1,8)}' "$_B_HB")"
    else
        printf '  세션 감시 : 없음 — 모든 메시지를 봇이 처리\n'
    fi
    return $ok
}

_b_cmd_install() {
    _b_require || return 1
    mkdir -p "$(dirname "$_B_UNIT")"
    cat > "$_B_UNIT" <<UNIT
[Unit]
Description=noti dcbot — 디스코드로 들어온 말에 Claude 가 답하는 상주 봇
After=network-online.target

[Service]
Type=simple
ExecStart=${_B_SELF} run
Restart=always
RestartSec=10
Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
UNIT
    systemctl --user daemon-reload
    systemctl --user enable --now noti-dcbot
    echo "등록 완료 — PC 를 켜면 자동으로 뜬다."
    echo "  상태: systemctl --user status noti-dcbot"
    echo "  중지: ~/KscTool/noti/dcbot.sh stop"
    _b_cmd_status
}

_b_cmd_uninstall() {
    systemctl --user disable --now noti-dcbot 2>/dev/null
    rm -f "$_B_UNIT"
    systemctl --user daemon-reload
    echo "자동 실행 해제 완료"
}

_b_cmd_logs() { tail -n "${1:-30}" "$_B_LOG" 2>/dev/null || echo "로그 없음"; }

case "${1:-help}" in
    run)       _b_cmd_run ;;
    start)     _b_cmd_start ;;
    stop)      _b_cmd_stop ;;
    status)    _b_cmd_status ;;
    logs)      shift; _b_cmd_logs "$@" ;;
    install)   _b_cmd_install ;;
    uninstall) _b_cmd_uninstall ;;
    once)      _b_require && _b_poll_once ;;
    *) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0" ;;
esac
