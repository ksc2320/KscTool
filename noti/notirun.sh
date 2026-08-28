#!/bin/bash
# notirun — 오래 걸리는 명령을 감싸서, 끝나면 휴대폰으로 알린다. (짧게: ntr)
#
#   notirun make -j8                        빌드 걸어놓고 자리 뜨기
#   notirun -t "609H 전체빌드" make -j8     제목 붙이기
#   notirun -f aptest smoke --live          실패했을 때만 알림
#   ntr make -j8                            ntr 은 notirun 의 짧은 별칭
#
# 성공하면 info(디스코드 기록만), 실패하면 urgent(폰이 울린다).
# 화면 출력은 그대로 보이고, 종료코드도 원래 명령 것을 그대로 돌려준다.
# 로그는 ~/.devtools/noti/runs/ 에 남는다.

set -uo pipefail

_NOTIRUN_NOTI="$HOME/KscTool/noti/noti.sh"
_NOTIRUN_RUNS="$HOME/.devtools/noti/runs"
_NOTIRUN_KEEP=50

_notirun_help() {
    awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0"
    exit 0
}

_notirun_hms() {   # 초 → "1시간 2분 3초"
    local s=$1 h m
    h=$((s/3600)); m=$(((s%3600)/60)); s=$((s%60))
    [ $h -gt 0 ] && printf '%d시간 ' "$h"
    [ $m -gt 0 ] && printf '%d분 ' "$m"
    printf '%d초' "$s"
}

# 실패 로그에서 사람이 볼 만한 줄만 뽑는다. 없으면 그냥 끝부분.
_notirun_errlines() {
    local f="$1" hit
    # 첫 두 줄은 실행한 명령 자체라 건너뛴다 (거기 error 가 들어있으면 헛것을 잡는다)
    hit=$(tail -n +3 "$f" | grep -iE 'error|failed|failure|undefined reference|no such file|cannot find|Segmentation|Traceback|assert' 2>/dev/null | tail -8)
    [ -n "$hit" ] && { printf '%s' "$hit"; return; }
    tail -8 "$f"
}

title=""; failonly=0
while [ $# -gt 0 ]; do
    case "$1" in
        -t|--title) title="$2"; shift 2 ;;
        -f|--fail-only) failonly=1; shift ;;
        -h|--help) _notirun_help ;;
        --) shift; break ;;
        -*) echo "알 수 없는 옵션: $1 (도움말: notirun -h)" >&2; exit 1 ;;
        *) break ;;
    esac
done
[ $# -eq 0 ] && _notirun_help

[ -z "$title" ] && title="$*"
[ ${#title} -gt 60 ] && title="${title:0:57}..."

mkdir -p "$_NOTIRUN_RUNS"
slug=$(printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '_' | cut -c1-20)
log="${_NOTIRUN_RUNS}/$(date +%Y%m%d_%H%M%S)_${slug}.log"

start=$(date +%s)
printf '$ %s\n\n' "$*" > "$log"
# 화면에도 보이고 로그에도 남는다. 종료코드는 원래 명령 것으로.
"$@" 2>&1 | tee -a "$log"
rc=${PIPESTATUS[0]}
elapsed=$(( $(date +%s) - start ))
took=$(_notirun_hms "$elapsed")

if [ "$rc" -eq 0 ]; then
    if [ "$failonly" -eq 0 ]; then
        printf '소요 %s\n%s\n\n로그: %s' "$took" "$(tail -3 "$log")" "$log" \
            | "$_NOTIRUN_NOTI" -t "${title} 성공" -l info -q
    fi
else
    printf '종료코드 %s · 소요 %s\n\n%s\n\n로그: %s' "$rc" "$took" "$(_notirun_errlines "$log")" "$log" \
        | "$_NOTIRUN_NOTI" -t "${title} 실패" -l urgent -q
fi

# 오래된 로그 정리
ls -1t "$_NOTIRUN_RUNS"/*.log 2>/dev/null | tail -n +$((_NOTIRUN_KEEP + 1)) | xargs -r rm -f

printf '\n[notirun] %s — %s (%s)\n' "$title" "$([ $rc -eq 0 ] && echo 성공 || echo "실패 rc=$rc")" "$took"
exit "$rc"
