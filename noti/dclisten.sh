#!/bin/bash
# dclisten — 디스코드 채널을 폴링해 새 메시지를 한 줄씩 stdout 으로 흘린다.
# Claude Code 의 Monitor 도구가 이 출력을 이벤트로 받아 작업 중에 지시를 전달한다.
#
#   ~/KscTool/noti/dclisten.sh check     설정·토큰·권한 점검
#   ~/KscTool/noti/dclisten.sh users     채널에 글 쓴 사람들의 숫자 ID
#   ~/KscTool/noti/dclisten.sh once      한 번만 확인하고 종료
#   ~/KscTool/noti/dclisten.sh watch     계속 폴링 (Monitor 용)
#   ~/KscTool/noti/dclisten.sh reset     "읽은 위치"를 지금으로 리셋
#
# 답장 라우팅: noti 가 보낸 알림에 디스코드에서 "답장" 하면
# threads.tsv 에서 원본 제목·세션ID를 찾아 함께 출력한다.

set -uo pipefail

_DC_CONF_DIR="$HOME/.devtools/noti"
_DC_CONF="${_DC_CONF_DIR}/config"
_DC_THREADS="${_DC_CONF_DIR}/threads.tsv"
_DC_LAST="${_DC_CONF_DIR}/listen_last_id"
_DC_API="https://discord.com/api/v10"
_DC_INTERVAL="${DCLISTEN_INTERVAL:-15}"

[ -f "$_DC_CONF" ] || { echo "설정이 없다: $_DC_CONF (noti init 먼저)" >&2; exit 1; }
# shellcheck disable=SC1090
. "$_DC_CONF"

TOKEN="${NOTI_DISCORD_BOT_TOKEN:-}"
CHAN="${NOTI_DISCORD_CHANNEL_ID:-}"
ALLOW="${NOTI_DISCORD_ALLOW_USER:-}"

# 토큰을 ps 목록에 노출하지 않으려고 curl --config 로 헤더를 넘긴다
_dc_curl() {
    curl -s -m 20 --config <(printf 'header = "Authorization: Bot %s"\n' "$TOKEN") "$@"
}

# 연결에 꼭 필요한 것 (토큰·채널)
_dc_require_conn() {
    local bad=0
    [ -z "$TOKEN" ] && { echo "봇 토큰이 없다 → noti setkey bot-token" >&2; bad=1; }
    [ -z "$CHAN" ]  && { echo "채널 ID가 없다 → 설정 NOTI_DISCORD_CHANNEL_ID" >&2; bad=1; }
    return $bad
}

# 실제 지시를 받으려면 화이트리스트까지 있어야 한다
_dc_require() {
    _dc_require_conn || return 1
    if [ -z "$ALLOW" ]; then
        echo "허용 사용자ID가 없다 → 설정 NOTI_DISCORD_ALLOW_USER" >&2
        echo "  이 값이 없으면 채널에 들어온 누구의 메시지든 지시로 읽는다. 반드시 지정할 것." >&2
        echo "  숫자 ID 확인: ~/KscTool/noti/dclisten.sh users" >&2
        return 1
    fi
    return 0
}

# 최근에 이 채널에 글을 쓴 사람들의 숫자 ID (화이트리스트에 넣을 값 찾기용)
_dc_cmd_users() {
    _dc_require_conn || return 1
    local resp code
    resp=$(_dc_curl -w '\n%{http_code}' "${_DC_API}/channels/${CHAN}/messages?limit=100")
    code=$(printf '%s' "$resp" | tail -n1)
    [ "$code" != "200" ] && { echo "채널 읽기 실패 (HTTP $code)" >&2; return 1; }
    echo "── 최근 이 채널에 글을 쓴 사람 (봇·웹훅 제외) ──"
    printf '%s' "$resp" | sed '$d' | jq -r '
        [ .[] | select(.webhook_id == null) | select(.author.bot != true)
              | {id: .author.id, name: (.author.global_name // .author.username), un: .author.username} ]
        | group_by(.id) | map({id: .[0].id, name: .[0].name, un: .[0].un, n: length})
        | sort_by(-.n)[]
        | "  \(.id)   \(.un)  (\(.name))  글 \(.n)건"'
    echo
    echo "  설정에 넣기: noti setkey NOTI_DISCORD_ALLOW_USER   (또는 config 직접 편집)"
}

# 답장 대상 조회: 메시지ID → "제목|세션ID"
_dc_thread_lookup() {
    local ref="$1"
    [ -z "$ref" ] || [ ! -f "$_DC_THREADS" ] && return 1
    # 같은 ID가 여러 줄이면 가장 최근 것을 쓴다
    awk -F'\t' -v id="$ref" '$1==id {hit=$4 "|" $2} END{if(hit){print hit; exit 0} exit 1}' "$_DC_THREADS"
}

_dc_cmd_check() {
    echo "── dclisten 점검 ──"
    _dc_require_conn || return 1
    local me code
    me=$(_dc_curl -w '\n%{http_code}' "${_DC_API}/users/@me")
    code=$(printf '%s' "$me" | tail -n1)
    if [ "$code" != "200" ]; then
        echo "✗ 봇 인증 실패 (HTTP $code) — 토큰을 다시 확인해라" >&2
        printf '%s\n' "$me" | sed '$d' | head -3 >&2
        return 1
    fi
    printf '✓ 봇 인증 OK — %s\n' "$(printf '%s' "$me" | sed '$d' | jq -r '.username')"

    local msgs
    msgs=$(_dc_curl -w '\n%{http_code}' "${_DC_API}/channels/${CHAN}/messages?limit=5")
    code=$(printf '%s' "$msgs" | tail -n1)
    if [ "$code" != "200" ]; then
        echo "✗ 채널 읽기 실패 (HTTP $code)" >&2
        echo "  봇을 서버에 초대했는지, 그 채널의 '메시지 읽기'·'메시지 기록 보기' 권한이 있는지 확인해라." >&2
        printf '%s\n' "$msgs" | sed '$d' | head -3 >&2
        return 1
    fi
    echo "✓ 채널 읽기 OK"

    local body n empty
    body=$(printf '%s' "$msgs" | sed '$d')
    n=$(printf '%s' "$body" | jq 'length')
    empty=$(printf '%s' "$body" | jq '[.[] | select((.content // "") == "" and (.attachments|length)==0 and (.embeds|length)==0)] | length')
    printf '  최근 메시지 %s건 중 본문이 빈 것 %s건\n' "$n" "$empty"
    if [ "$n" -gt 0 ] && [ "$empty" = "$n" ]; then
        echo "✗ 본문이 전부 비어 있다 — 개발자 포털에서 MESSAGE CONTENT INTENT 를 켜야 한다" >&2
        return 1
    fi
    echo "✓ 본문 읽기 OK"
    if [ -z "$ALLOW" ]; then
        echo "✗ 허용 사용자ID 미설정 — 지금 상태로는 감시를 시작할 수 없다"
        echo "  → ~/KscTool/noti/dclisten.sh users 로 숫자 ID를 확인해 넣어라"
        return 1
    fi
    printf '  허용 사용자ID : %s\n' "$ALLOW"
    printf '  폴링 간격     : %s초\n' "$_DC_INTERVAL"
    printf '  읽은 위치     : %s\n' "$( [ -f "$_DC_LAST" ] && cat "$_DC_LAST" || echo '(없음 — 첫 실행은 현재 시점부터)' )"
    echo "── 준비 완료 ──"
}

# 최신 메시지 ID 를 읽은 위치로 저장 (과거 메시지를 지시로 오인하지 않도록)
_dc_cmd_reset() {
    _dc_require || return 1
    local latest
    latest=$(_dc_curl "${_DC_API}/channels/${CHAN}/messages?limit=1" | jq -r '.[0].id // empty')
    if [ -n "$latest" ]; then
        printf '%s' "$latest" > "$_DC_LAST"
        echo "읽은 위치를 현재로 맞췄다: $latest"
    else
        : > "$_DC_LAST"; echo "채널이 비어 있다. 위치 초기화."
    fi
}

_dc_poll_once() {
    local last url resp msgs newest
    last=$( [ -f "$_DC_LAST" ] && cat "$_DC_LAST" || echo "" )
    if [ -z "$last" ]; then
        # 첫 실행: 과거를 훑지 않고 현재 시점부터 본다
        newest=$(_dc_curl "${_DC_API}/channels/${CHAN}/messages?limit=1" | jq -r '.[0].id // empty') || true
        [ -n "$newest" ] && printf '%s' "$newest" > "$_DC_LAST"
        return 0
    fi
    url="${_DC_API}/channels/${CHAN}/messages?after=${last}&limit=50"
    resp=$(_dc_curl "$url") || return 0
    printf '%s' "$resp" | jq -e 'type=="array"' >/dev/null 2>&1 || return 0

    # 오래된 것부터 처리
    msgs=$(printf '%s' "$resp" | jq -c 'reverse | .[] | select(.webhook_id == null) | select(.author.bot != true) | {id, uid: .author.id, uname: .author.username, content, ref: (.message_reference.message_id // ""), att: (.attachments | length)}')
    [ -z "$msgs" ] && {
        newest=$(printf '%s' "$resp" | jq -r 'if length>0 then (max_by(.id|tonumber).id) else empty end')
        [ -n "$newest" ] && printf '%s' "$newest" > "$_DC_LAST"
        return 0
    }

    local line id uid uname content ref att label look title sess
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        id=$(printf '%s' "$line" | jq -r '.id')
        uid=$(printf '%s' "$line" | jq -r '.uid')
        uname=$(printf '%s' "$line" | jq -r '.uname')
        content=$(printf '%s' "$line" | jq -r '.content')
        ref=$(printf '%s' "$line" | jq -r '.ref')
        att=$(printf '%s' "$line" | jq -r '.att')

        printf '%s' "$id" > "$_DC_LAST"

        if [ -n "$ALLOW" ] && [ "$uid" != "$ALLOW" ]; then
            echo "⛔ 허용되지 않은 사용자(${uname}/${uid})의 메시지 무시" 
            continue
        fi

        label="새메시지"
        # ! 로 시작하면 상주 봇(dcbot)이 처리한다. 세션은 알고만 있고 손대지 않는다.
        case "$content" in "!"*) label="봇담당(dcbot)" ;; esac
        if [ -n "$ref" ] && look=$(_dc_thread_lookup "$ref"); then
            title="${look%%|*}"; sess="${look##*|}"
            if [ "$sess" = "${CLAUDE_CODE_SESSION_ID:-}" ]; then
                label="답장[\"${title}\" · 이 세션]"
            else
                label="답장[\"${title}\" · 세션 ${sess:0:8}]"
            fi
        elif [ -n "$ref" ]; then
            label="답장[원본 불명 ${ref}]"
        fi

        # 개행은 한 줄로 눌러야 Monitor 이벤트 하나가 된다
        content=$(printf '%s' "$content" | tr '\n' '\036' | sed 's/\o036/ ⏎ /g')
        [ "$att" != "0" ] && content="${content} (첨부 ${att}건)"
        [ -z "$content" ] && content="(본문 없음 — MESSAGE CONTENT INTENT 확인 필요)"

        printf '📩 %s %s\n' "$label" "$content"
    done <<< "$msgs"
}

_dc_cmd_watch() {
    _dc_require || return 1
    echo "📡 디스코드 채널 감시 시작 (${_DC_INTERVAL}초 간격). 답장하면 원본 질문을 찾아 함께 알려준다."
    # 살아있는 세션이 보고 있다는 표시. dcbot 은 이게 최근이면 손대지 않고 양보한다.
    local hb="${_DC_CONF_DIR}/watcher.heartbeat"
    trap 'rm -f "$hb"; exit 0' TERM INT
    while true; do
        printf '%s %s\n' "$(date +%s)" "${CLAUDE_CODE_SESSION_ID:-unknown}" > "$hb"
        _dc_poll_once || true
        sleep "$_DC_INTERVAL"
    done
}

case "${1:-help}" in
    check) _dc_cmd_check ;;
    users) _dc_cmd_users ;;
    once)  _dc_require && _dc_poll_once ;;
    watch) _dc_cmd_watch ;;
    reset) _dc_cmd_reset ;;
    *) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0" ;;
esac
