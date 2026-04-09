#!/usr/bin/env bash
# push_ksctool.sh — 매일 02시 KscTool 변경사항 자동 push
# cron: 30 2 * * * /home/ksc/KscTool/scripts/push_ksctool.sh >> /home/ksc/KscTool/scripts/push_ksctool.log 2>&1

set -euo pipefail

REPO="$HOME/KscTool"
LOG_PREFIX="[ksctool-push]"

echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') 시작"

cd "$REPO"

git add -A

if git diff --cached --quiet; then
    echo "$LOG_PREFIX 변경 없음 — push 생략"
else
    COMMIT_MSG="chore: auto push $(date '+%Y-%m-%d')"
    git commit -m "$COMMIT_MSG"
    git push origin main
    echo "$LOG_PREFIX push 완료: $COMMIT_MSG"
fi

echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') 완료"
