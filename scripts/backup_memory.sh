#!/usr/bin/env bash
# backup_memory.sh — Claude/Codex 공용 메모리 저장소 자동 백업
#
# 메모리는 여러 경로에서 심볼릭 링크로 보이지만 실체는 한 폴더다.
# ~/memo 의 .auto_sync.sh 는 심볼릭 링크를 따라가지 않아 메모리를 백업하지 못한다.
# 그래서 별도로 돈다.
#
# cron: 17 */4 * * * /home/ksc/KscTool/scripts/backup_memory.sh >> /home/ksc/KscTool/scripts/backup_memory.log 2>&1
#
# 원격(origin)이 있으면 push 까지, 없으면 로컬 커밋만 한다.
# 메모리에는 사내 이슈·규격 내용이 들어있으므로 **공개 저장소에 붙이지 말 것.**

set -uo pipefail

REPO="$(readlink -f "$HOME/.codex/memories")"
LOG_PREFIX="[memory-backup]"

echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') 시작"

if [ ! -d "$REPO/.git" ]; then
    echo "$LOG_PREFIX git 저장소가 아니다: $REPO" >&2
    exit 1
fi

cd "$REPO" || exit 1

git add -A

if git diff --cached --quiet; then
    echo "$LOG_PREFIX 변경 없음 — 생략"
    echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') 완료"
    exit 0
fi

# 무엇이 바뀌었는지 커밋 메시지에 남긴다 (파일명만, 내용은 아님)
CHANGED=$(git diff --cached --name-only | head -5 | xargs -r -n1 basename | paste -sd, -)
COUNT=$(git diff --cached --name-only | wc -l)
[ "$COUNT" -gt 5 ] && CHANGED="${CHANGED} 외 $((COUNT - 5))건"

git commit -q -m "memory auto-backup: $(date '+%Y-%m-%d %H:%M') | ${CHANGED}"
echo "$LOG_PREFIX 커밋: ${CHANGED}"

if git remote get-url origin >/dev/null 2>&1; then
    if git push origin HEAD 2>&1; then
        echo "$LOG_PREFIX push 완료"
    else
        echo "$LOG_PREFIX push 실패 — 로컬 커밋은 남아있다" >&2
    fi
else
    echo "$LOG_PREFIX 원격 없음 — 로컬 커밋만 (다른 디스크 백업은 아직 없음)"
fi

echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') 완료"
