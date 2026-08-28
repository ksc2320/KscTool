#!/bin/bash
# dcsession — 알림을 보낸 그 세션의 대화를 읽는다.
#
# 디스코드 답장이 "세션 3f2a1b8c" 로 들어왔을 때, 그 세션에서 무슨 얘기가 오갔는지
# 읽어야 답을 이어갈 수 있다. Claude Code 대화 기록(JSONL)에서 사람이 읽을 수 있는
# 부분만 뽑아낸다. (생각·도구호출·도구결과는 뺀다)
#
#   dcsession.sh list [N]              최근 세션 N개 (기본 10)
#   dcsession.sh ctx <세션ID> [턴수]   그 세션 최근 대화 (기본 8턴)
#   dcsession.sh ctx <세션ID> 8 full   자르지 않고 전문
#   dcsession.sh path <세션ID>         기록 파일 경로만
#   dcsession.sh cwd <세션ID>          그 세션의 작업 폴더
#   dcsession.sh last [턴수]           지금 이 세션(CLAUDE_CODE_SESSION_ID)

set -uo pipefail
_DS_ROOT="$HOME/.claude/projects"
_DS_CUT=400

_ds_path() {
    local sid="$1"
    [ -z "$sid" ] && return 1
    find "$_DS_ROOT" -maxdepth 2 -name "${sid}.jsonl" -print -quit 2>/dev/null | grep . || return 1
}

# 세션ID 앞자리만 줘도 찾아준다
_ds_resolve() {
    local key="$1" hit
    hit=$(_ds_path "$key") && { printf '%s' "$hit"; return 0; }
    hit=$(find "$_DS_ROOT" -maxdepth 2 -name "${key}*.jsonl" -print 2>/dev/null | head -1)
    [ -n "$hit" ] && { printf '%s' "$hit"; return 0; }
    return 1
}

_ds_first_text() {
    jq -r 'select(.type=="user")
           | (.message.content | if type=="array"
                then (map(select(.type=="text").text) | join(" "))
                else . end)' "$1" 2>/dev/null \
    | grep -v '^[[:space:]]*$' | grep -v '^<system-reminder>' | grep -v '^Caveat:' | head -1 | cut -c1-40
}

_ds_cmd_list() {
    local n="${1:-10}" f sid cwd when first
    printf '%-10s %-14s %-16s %s\n' "세션" "마지막 활동" "작업 폴더" "첫 마디"
    printf '%s\n' "──────────────────────────────────────────────────────────────────────"
    while read -r _ f; do
        sid=$(basename "$f" .jsonl)
        cwd=$(jq -r 'select(.cwd) | .cwd' "$f" 2>/dev/null | head -1)
        when=$(date -d "@$(stat -c %Y "$f")" '+%m-%d %H:%M' 2>/dev/null)
        first=$(_ds_first_text "$f")
        printf '%-10s %-14s %-16s %s\n' "${sid:0:8}" "$when" "$(basename "${cwd:-?}")" "$first"
    done < <(find "$_DS_ROOT" -maxdepth 2 -name '*.jsonl' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n "$n")
}

_ds_cmd_ctx() {
    local sid="${1:-}" turns="${2:-8}" mode="${3:-cut}" f cwd cut
    [ -z "$sid" ] && { echo "세션ID가 필요하다." >&2; return 1; }
    f=$(_ds_resolve "$sid") || { echo "그 세션 기록을 못 찾겠다: $sid" >&2; return 1; }
    cwd=$(jq -r 'select(.cwd) | .cwd' "$f" 2>/dev/null | head -1)
    cut=$_DS_CUT; [ "$mode" = "full" ] && cut=100000
    printf '── 세션 %s (%s) 최근 %s턴 ──\n' "${sid:0:8}" "${cwd:-?}" "$turns"

    # 탭 구분: 시각 <TAB> 화자 <TAB> 본문 (본문 내 탭·개행은 미리 없앤다)
    # 사용자가 작업 도중 보낸 말은 type=user 가 아니라 queue-operation(enqueue) 로 남는다
    jq -r --argjson cut "$cut" '
        select(.type=="user" or .type=="assistant"
               or (.type=="queue-operation" and .operation=="enqueue"))
        | . as $e
        | ( if $e.type=="queue-operation" then $e.content
            else ( $e.message.content
                   | if type=="array" then (map(select(.type=="text") | .text) | join("\n")) else . end )
            end ) as $t
        | select(($t|type)=="string")
        | ($t | gsub("<system-reminder>[\\s\\S]*?</system-reminder>";"")
              | gsub("[\\t\\n\\r]+";" ")
              | sub("^ +";"") ) as $c
        | select(($c|length) > 0)
        | select($c | startswith("Caveat:") | not)
        | [ ($e.timestamp // ""),
            (if $e.type=="assistant" then "Claude" else "나" end),
            (if ($c|length) > $cut then ($c[0:$cut] + " …") else $c end)
          ] | @tsv
    ' "$f" 2>/dev/null \
    | tail -n "$turns" \
    | while IFS=$'\t' read -r ts who text; do
        printf '\n[%s %s]\n%s\n' "$(date -d "$ts" '+%m-%d %H:%M' 2>/dev/null || echo "$ts")" "$who" "$text"
      done
    echo
}

case "${1:-help}" in
    list) shift; _ds_cmd_list "$@" ;;
    ctx)  shift; _ds_cmd_ctx  "$@" ;;
    path) shift; _ds_resolve "${1:-}" && echo ;;
    cwd)  shift; f=$(_ds_resolve "${1:-}") && jq -r 'select(.cwd) | .cwd' "$f" 2>/dev/null | head -1 ;;
    last) shift; _ds_cmd_ctx "${CLAUDE_CODE_SESSION_ID:-}" "${1:-8}" ;;
    *) awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0" ;;
esac
