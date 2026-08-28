#!/bin/bash
# noti — 휴대폰 알림 전송 (Discord / ntfy / Telegram)
# 규칙: ~/KscTool/RULES.md   설정: ~/.devtools/noti/config
# 레벨별 라우팅 + 디스코드 메시지ID↔세션ID 기록(답장 라우팅용)

_NOTI_VER="1.1.0"
_NOTI_SELF="$HOME/KscTool/noti/noti.sh"
_NOTI_CONF_DIR="$HOME/.devtools/noti"
_NOTI_CONF="${_NOTI_CONF_DIR}/config"
_NOTI_LOG="${_NOTI_CONF_DIR}/history.log"
_NOTI_THREADS="${_NOTI_CONF_DIR}/threads.tsv"
_NOTI_THREADS_KEEP=500

if [ -t 1 ]; then
    _N_RST=$'\e[0m';        _N_B=$'\e[1m'
    _N_RED=$'\e[1;31m';     _N_GRN=$'\e[1;32m';   _N_YEL=$'\e[1;33m'
    _N_SKY=$'\e[38;5;153m'; _N_VIO=$'\e[38;5;183m'
    _N_LIM=$'\e[38;5;120m'; _N_GRY=$'\e[38;5;245m'
else
    _N_RST=; _N_B=; _N_RED=; _N_GRN=; _N_YEL=; _N_SKY=; _N_VIO=; _N_LIM=; _N_GRY=
fi

_noti_ln()  { printf '%s%s%s\n' "$_N_SKY" "────────────────────────────────────────────────────────" "$_N_RST"; }
_noti_hd()  { _noti_ln; printf '%s %s%s\n' "$_N_VIO$_N_B" "$*" "$_N_RST"; _noti_ln; }
_noti_sec() { printf '\n%s▸ %s%s\n' "$_N_LIM" "$*" "$_N_RST"; }

_noti_load_conf() {
    NOTI_CHANNELS="discord"
    NOTI_ROUTE_INFO=""; NOTI_ROUTE_WARN=""; NOTI_ROUTE_URGENT=""
    NOTI_DISCORD_WEBHOOK=""; NOTI_DISCORD_MENTION=""
    NOTI_DISCORD_BOT_TOKEN=""; NOTI_DISCORD_CHANNEL_ID=""; NOTI_DISCORD_ALLOW_USER=""
    NOTI_NTFY_SERVER="https://ntfy.sh"; NOTI_NTFY_TOPIC=""
    NOTI_TELEGRAM_TOKEN=""; NOTI_TELEGRAM_CHAT=""
    NOTI_PREFIX="ksc-pc"
    [ -f "$_NOTI_CONF" ] && . "$_NOTI_CONF"
}

_noti_mask() {
    local s="$1"
    [ -z "$s" ] && { printf '%s(미설정)%s' "$_N_GRY" "$_N_RST"; return; }
    if [ ${#s} -le 12 ]; then printf '****'; else printf '%s...%s' "${s:0:8}" "${s: -4}"; fi
}

_noti_log() {
    mkdir -p "$_NOTI_CONF_DIR"
    local msg
    msg=$(printf '%s' "$4" | tr '\n\t' '  ')   # 여러 줄이면 이력이 깨진다
    printf '%s | %-8s | %-6s | %-4s | %s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" "$3" "${msg:0:70}" >> "$_NOTI_LOG"
}

# 디스코드 메시지ID ↔ 세션ID 기록. 사용자가 그 알림에 "답장" 하면 어느 세션·어느 질문인지 찾는다.
_noti_thread_add() {
    local msg_id="$1" sess="$2" level="$3" title="$4" agent="${5:-}"
    [ -z "$msg_id" ] && return 0
    mkdir -p "$_NOTI_CONF_DIR"
    # 6열 = 세션 이름(memo-6b 같은 것). 세션 UUID 로는 다른 세션을 부를 수 없어서 따로 적는다.
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$msg_id" "${sess:-unknown}" "$level" \
        "$(printf '%s' "$title" | tr '\t\n' '  ')" "$(date -Iseconds)" "$agent" >> "$_NOTI_THREADS"
    if [ "$(wc -l < "$_NOTI_THREADS")" -gt $((_NOTI_THREADS_KEEP * 2)) ]; then
        tail -n "$_NOTI_THREADS_KEEP" "$_NOTI_THREADS" > "${_NOTI_THREADS}.tmp" \
            && mv "${_NOTI_THREADS}.tmp" "$_NOTI_THREADS"
    fi
}

# ── 채널별 전송 ($1=제목 $2=본문 $3=레벨 $4=세션ID) ──────────────
_noti_send_discord() {
    local title="$1" body="$2" level="$3" sess="$4" agent="${5:-}" icon head payload resp code msg_id
    [ -z "$NOTI_DISCORD_WEBHOOK" ] && { echo "discord: 웹훅 미설정" >&2; return 1; }
    case "$level" in
        urgent) icon="🚨" ;;
        warn)   icon="⚠️"  ;;
        *)      icon="🔔" ;;
    esac
    head="${icon} **[${NOTI_PREFIX}] ${title}**"
    [ "$level" = "urgent" ] && [ -n "$NOTI_DISCORD_MENTION" ] && head="${NOTI_DISCORD_MENTION} ${head}"
    payload=$(jq -n --arg c "$(printf '%s\n%s' "$head" "$body" | cut -c1-1900)" \
        '{content:$c, username:"claude-code", allowed_mentions:{parse:["users"]}}')
    # wait=true 를 붙이면 방금 보낸 메시지 객체가 돌아온다 → 메시지ID 확보
    resp=$(curl -s -m 15 -w '\n%{http_code}' \
        -H 'Content-Type: application/json' -d "$payload" "${NOTI_DISCORD_WEBHOOK}?wait=true")
    code=$(printf '%s' "$resp" | tail -n1)
    case "$code" in
        20*) msg_id=$(printf '%s' "$resp" | sed '$d' | jq -r '.id // empty' 2>/dev/null)
             _noti_thread_add "$msg_id" "$sess" "$level" "$title" "$agent"
             return 0 ;;
        *)   echo "discord: HTTP $code" >&2; return 1 ;;
    esac
}

_noti_send_ntfy() {
    local title="$1" body="$2" level="$3" prio tag payload code
    [ -z "$NOTI_NTFY_TOPIC" ] && { echo "ntfy: 토픽 미설정" >&2; return 1; }
    case "$level" in
        urgent) prio=5; tag="rotating_light" ;;
        warn)   prio=4; tag="warning" ;;
        *)      prio=3; tag="bell" ;;
    esac
    # 헤더로는 한글이 깨진다. JSON 발행 엔드포인트를 쓴다.
    payload=$(jq -n --arg t "$NOTI_NTFY_TOPIC" --arg ti "[${NOTI_PREFIX}] ${title}" \
        --arg m "$body" --argjson p "$prio" --arg tag "$tag" \
        '{topic:$t, title:$ti, message:$m, priority:$p, tags:[$tag]}')
    code=$(curl -s -o /dev/null -m 15 -w '%{http_code}' \
        -H 'Content-Type: application/json' -d "$payload" "${NOTI_NTFY_SERVER%/}/")
    case "$code" in
        20*) return 0 ;;
        *)   echo "ntfy: HTTP $code" >&2; return 1 ;;
    esac
}

_noti_send_telegram() {
    local title="$1" body="$2" level="$3" icon text code
    [ -z "$NOTI_TELEGRAM_TOKEN" ] || [ -z "$NOTI_TELEGRAM_CHAT" ] && \
        { echo "telegram: 토큰/chat_id 미설정" >&2; return 1; }
    case "$level" in
        urgent) icon="🚨" ;;
        warn)   icon="⚠️"  ;;
        *)      icon="🔔" ;;
    esac
    text=$(printf '%s [%s] %s\n%s' "$icon" "$NOTI_PREFIX" "$title" "$body")
    code=$(curl -s -o /dev/null -m 15 -w '%{http_code}' \
        --data-urlencode "chat_id=${NOTI_TELEGRAM_CHAT}" \
        --data-urlencode "text=${text}" \
        "https://api.telegram.org/bot${NOTI_TELEGRAM_TOKEN}/sendMessage")
    case "$code" in
        20*) return 0 ;;
        *)   echo "telegram: HTTP $code" >&2; return 1 ;;
    esac
}

# 레벨에 맞는 채널 목록. -c 로 준 값이 최우선, 없으면 NOTI_ROUTE_<레벨>, 그것도 없으면 NOTI_CHANNELS
_noti_route() {
    case "$1" in
        info)   printf '%s' "${NOTI_ROUTE_INFO:-$NOTI_CHANNELS}" ;;
        warn)   printf '%s' "${NOTI_ROUTE_WARN:-$NOTI_CHANNELS}" ;;
        urgent) printf '%s' "${NOTI_ROUTE_URGENT:-$NOTI_CHANNELS}" ;;
    esac
}

_noti_cmd_send() {
    local title="알림" level="info" chans="" quiet=0 body="" agent="" sess="${CLAUDE_CODE_SESSION_ID:-}"
    while [ $# -gt 0 ]; do
        case "$1" in
            -t|--title)   title="$2"; shift 2 ;;
            -l|--level)   level="$2"; shift 2 ;;
            -c|--channel) chans="$2"; shift 2 ;;
            -s|--session) sess="$2";  shift 2 ;;
            -n|--agent)   agent="$2"; shift 2 ;;
            -q|--quiet)   quiet=1; shift ;;
            --) shift; break ;;
            -*) echo "알 수 없는 옵션: $1" >&2; return 1 ;;
            *)  break ;;
        esac
    done
    body="$*"
    [ -z "$body" ] && [ ! -t 0 ] && body="$(cat)"
    [ -z "$body" ] && { echo "보낼 메시지가 없다." >&2; return 1; }

    case "$level" in info|warn|urgent) ;; *) echo "레벨은 info|warn|urgent" >&2; return 1 ;; esac
    [ -z "$chans" ] && chans="$(_noti_route "$level")"
    [ -z "$chans" ] && { echo "채널이 없다. 'noti init' 후 설정 파일을 채워라." >&2; return 1; }

    local ok=0 fail=0 c
    for c in ${chans//,/ }; do
        case "$c" in
            discord)  _noti_send_discord  "$title" "$body" "$level" "$sess" "$agent" ;;
            ntfy)     _noti_send_ntfy     "$title" "$body" "$level" ;;
            telegram) _noti_send_telegram "$title" "$body" "$level" ;;
            *) echo "알 수 없는 채널: $c" >&2; false ;;
        esac
        if [ $? -eq 0 ]; then
            ok=$((ok+1));   _noti_log "$c" "$level" "OK"   "$title / $body"
            [ $quiet -eq 0 ] && printf '%s✓%s %s 전송\n' "$_N_GRN" "$_N_RST" "$c"
        else
            fail=$((fail+1)); _noti_log "$c" "$level" "FAIL" "$title / $body"
            printf '%s✗%s %s 실패\n' "$_N_RED" "$_N_RST" "$c" >&2
        fi
    done
    [ $ok -gt 0 ] && return 0
    return 2
}

_noti_cmd_test() {
    _noti_hd "noti 연결 시험"
    _noti_sec "info (기록만)"
    _noti_cmd_send -t "연결 시험 info" -l info "평소 완료 알림. 디스코드에만 남는다."
    _noti_sec "urgent (폰 울림)"
    _noti_cmd_send -t "연결 시험 urgent" -l urgent "막혔을 때. 디스코드 + ntfy 로 간다."
    echo
}

_noti_cmd_conf() {
    _noti_hd "noti 설정 (v${_NOTI_VER})"
    printf '  설정 파일 : %s\n' "$_NOTI_CONF"
    printf '  이력 로그 : %s\n' "$_NOTI_LOG"
    printf '  답장 매핑 : %s (%s줄)\n' "$_NOTI_THREADS" "$( [ -f "$_NOTI_THREADS" ] && wc -l < "$_NOTI_THREADS" || echo 0 )"
    _noti_sec "레벨별 라우팅"
    printf '  info   → %s\n' "$(_noti_route info)"
    printf '  warn   → %s\n' "$(_noti_route warn)"
    printf '  urgent → %s%s%s\n' "$_N_B" "$(_noti_route urgent)" "$_N_RST"
    printf '  발신지 표시 : %s\n' "$NOTI_PREFIX"
    _noti_sec "Discord (보내기)"
    printf '  웹훅 URL       : %s\n' "$(_noti_mask "$NOTI_DISCORD_WEBHOOK")"
    printf '  urgent 멘션    : %s\n' "${NOTI_DISCORD_MENTION:-$_N_GRY(미설정)$_N_RST}"
    _noti_sec "Discord (받기 — dclisten)"
    printf '  봇 토큰        : %s\n' "$(_noti_mask "$NOTI_DISCORD_BOT_TOKEN")"
    printf '  채널 ID        : %s\n' "${NOTI_DISCORD_CHANNEL_ID:-$_N_GRY(미설정)$_N_RST}"
    printf '  허용 사용자ID  : %s\n' "${NOTI_DISCORD_ALLOW_USER:-$_N_RED(미설정 — 누구나 지시 가능!)$_N_RST}"
    _noti_sec "ntfy"
    printf '  서버 / 토픽    : %s / %s\n' "$NOTI_NTFY_SERVER" "$(_noti_mask "$NOTI_NTFY_TOPIC")"
    _noti_sec "Telegram"
    printf '  토큰 / chat_id : %s / %s\n' "$(_noti_mask "$NOTI_TELEGRAM_TOKEN")" "$(_noti_mask "$NOTI_TELEGRAM_CHAT")"
    echo
}

# 비밀값을 화면·기록에 남기지 않고 설정에 넣는다
_noti_cmd_setkey() {
    local key="$1" val
    case "$key" in
        bot-token) key="NOTI_DISCORD_BOT_TOKEN" ;;
        webhook)   key="NOTI_DISCORD_WEBHOOK" ;;
        ntfy-topic) key="NOTI_NTFY_TOPIC" ;;
        tg-token)  key="NOTI_TELEGRAM_TOKEN" ;;
        NOTI_*)    ;;
        *) echo "사용법: noti setkey <bot-token|webhook|ntfy-topic|tg-token>" >&2; return 1 ;;
    esac
    printf '%s 값을 붙여넣고 Enter (화면에 안 보임): ' "$key"
    read -rs val; echo
    [ -z "$val" ] && { echo "입력이 없다. 취소." >&2; return 1; }
    python3 - "$key" "$val" <<'PY'
import io, re, sys
key, val = sys.argv[1], sys.argv[2]
p = "%s/.devtools/noti/config" % __import__("os").path.expanduser("~")
s = io.open(p, encoding="utf-8").read()
line = '%s="%s"' % (key, val)
if re.search(r'^%s=' % re.escape(key), s, re.M):
    s = re.sub(r'^%s=.*$' % re.escape(key), line, s, count=1, flags=re.M)
else:
    s = s.rstrip("\n") + "\n" + line + "\n"
io.open(p, "w", encoding="utf-8").write(s)
print("  저장 완료 (%d자)" % len(val))
PY
    chmod 600 "$_NOTI_CONF"
}

_noti_cmd_init() {
    _noti_hd "noti 설치 (v${_NOTI_VER})"
    _noti_sec "1. 설정 디렉토리"
    mkdir -p "$_NOTI_CONF_DIR"
    if [ -f "$_NOTI_CONF" ]; then
        printf '  %s이미 있음(보존)%s %s\n' "$_N_YEL" "$_N_RST" "$_NOTI_CONF"
    else
        _noti_write_conf; printf '  %s생성%s %s (권한 600)\n' "$_N_GRN" "$_N_RST" "$_NOTI_CONF"
    fi
    _noti_sec "2. ~/.bash_functions 등록"
    touch "$HOME/.bash_functions"
    if grep -qF "noti/noti.sh" "$HOME/.bash_functions" 2>/dev/null; then
        printf '  %s이미 등록됨 (skip)%s\n' "$_N_GRY" "$_N_RST"
    else
        echo "[ -f \"${_NOTI_SELF}\" ] && source \"${_NOTI_SELF}\"" >> "$HOME/.bash_functions"
        printf '  %s추가%s\n' "$_N_GRN" "$_N_RST"
    fi
    _noti_sec "3. ~/.bash_aliases 등록"
    touch "$HOME/.bash_aliases"
    if grep -qE "alias noti=|_noti_main" "$HOME/.bash_aliases" 2>/dev/null; then
        printf '  %s이미 등록됨 (skip)%s\n' "$_N_GRY" "$_N_RST"
    else
        echo "alias noti='_noti_main'" >> "$HOME/.bash_aliases"
        printf '  %s추가%s alias noti\n' "$_N_GRN" "$_N_RST"
    fi
    _noti_sec "다음 할 일"
    echo "  noti setkey webhook    → 디스코드 웹훅 URL 입력"
    echo "  noti test              → 시험 발송"
    echo
}

_noti_write_conf() {
    mkdir -p "$_NOTI_CONF_DIR"
    [ -f "$_NOTI_CONF" ] && return 0
    cat > "$_NOTI_CONF" <<'CONF_EOF'
# noti 설정 — 휴대폰 알림. 권한 600 유지, 커밋 금지.
NOTI_PREFIX="ksc-pc"
NOTI_CHANNELS="discord"
# 레벨별 라우팅 (비우면 NOTI_CHANNELS)
NOTI_ROUTE_INFO="discord"
NOTI_ROUTE_WARN="discord"
NOTI_ROUTE_URGENT="discord,ntfy"
# Discord 보내기
NOTI_DISCORD_WEBHOOK=""
NOTI_DISCORD_MENTION=""
# Discord 받기 (dclisten)
NOTI_DISCORD_BOT_TOKEN=""
NOTI_DISCORD_CHANNEL_ID=""
NOTI_DISCORD_ALLOW_USER=""
# ntfy
NOTI_NTFY_SERVER="https://ntfy.sh"
NOTI_NTFY_TOPIC=""
# Telegram
NOTI_TELEGRAM_TOKEN=""
NOTI_TELEGRAM_CHAT=""
CONF_EOF
    chmod 600 "$_NOTI_CONF"
}

_noti_cmd_log() {
    local n="${1:-20}"
    [ -f "$_NOTI_LOG" ] || { echo "이력이 없다."; return 0; }
    _noti_hd "최근 전송 이력 (${n}줄)"; tail -n "$n" "$_NOTI_LOG"; echo
}

_noti_cmd_help() {
    _noti_hd "noti — 휴대폰 알림 전송 (v${_NOTI_VER})"
    cat <<HELP_EOF
  ${_N_B}사용법${_N_RST}
    noti [옵션] "메시지"        알림 전송
    noti init                   최초 설치
    noti setkey <이름>          비밀값 입력 (화면에 안 보임)
                                bot-token | webhook | ntfy-topic | tg-token
    noti test                   info·urgent 각 1건 시험 발송
    noti conf                   현재 설정 (비밀값 마스킹)
    noti log [N]                최근 전송 이력
    noti help                   이 도움말

  ${_N_B}옵션${_N_RST}
    -t, --title   <제목>        기본 "알림"
    -l, --level   <레벨>        info(기본) | warn | urgent
    -c, --channel <채널>        라우팅 무시하고 직접 지정
    -s, --session <세션ID>      답장 매핑에 쓸 세션 (기본 \$CLAUDE_CODE_SESSION_ID)
    -n, --agent   <세션이름>    이 세션의 이름(예: memo-6b). ListAgents 로 확인한다.
                                넣어두면 사용자가 답장했을 때 dcbot 이 **이 세션으로 지시를
                                전달**한다. 없으면 봇이 대신 답한다(읽기 전용)
    -q, --quiet                 성공 출력 생략

  ${_N_B}레벨별 라우팅 (설정에서 변경)${_N_RST}
    info   → $(_noti_route info)
    warn   → $(_noti_route warn)
    urgent → $(_noti_route urgent)

  ${_N_B}답장 라우팅${_N_RST}
    디스코드로 보낸 알림은 메시지ID·세션ID를 threads.tsv 에 기록한다.
    그 알림에 디스코드에서 "답장" 하면 dclisten 이 어느 질문에 대한
    답인지 찾아낸다. → ~/KscTool/noti/dclisten.sh

  ${_N_B}예시${_N_RST}
    noti -t "빌드 완료" "609H 전체 빌드 성공"
    noti -t "시험 중단" -l urgent "AP SSH 응답 없음 — 판단 필요"
    tail -5 build.log | noti -t "빌드 실패" -l warn
HELP_EOF
    echo
}

_noti_main() {
    _noti_load_conf
    case "${1:-}" in
        init)          shift; _noti_cmd_init "$@" ;;
        setkey)        shift; _noti_cmd_setkey "$@" ;;
        test)          shift; _noti_cmd_test "$@" ;;
        conf|config)   shift; _noti_cmd_conf "$@" ;;
        log)           shift; _noti_cmd_log  "$@" ;;
        help|-h|--help|"") _noti_cmd_help ;;
        *)             _noti_cmd_send "$@" ;;
    esac
}

_noti_register() { _noti_load_conf; alias noti='_noti_main'; }

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _noti_register
else
    _noti_main "$@"
fi
