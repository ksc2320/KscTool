#!/usr/bin/env bash
# backup_dotfiles.sh — 주 1회 dotfiles를 ~/dotfiles/ 에 모아 GitHub private repo에 push
# cron: 0 2 * * 0 /home/ksc/KscTool/scripts/backup_dotfiles.sh >> /home/ksc/.dotfiles_backup.log 2>&1

set -euo pipefail

DEST="$HOME/dotfiles"
LOG_PREFIX="[dotfiles-backup]"

echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') 시작"

# ── bash ──────────────────────────────────────────────────
cp -f "$HOME/.bashrc"           "$DEST/bash/.bashrc"
cp -f "$HOME/.bash_aliases"     "$DEST/bash/.bash_aliases"
cp -f "$HOME/.bash_functions"   "$DEST/bash/.bash_functions"
cp -f "$HOME/.bash_profile"     "$DEST/bash/.bash_profile"
cp -f "$HOME/.profile"          "$DEST/bash/.profile"

# ── vim ───────────────────────────────────────────────────
cp -f "$HOME/.vimrc"         "$DEST/vim/.vimrc"

# ── git ───────────────────────────────────────────────────
cp -f "$HOME/.gitconfig"     "$DEST/git/.gitconfig"
[ -f "$HOME/.gitignore_global" ] && cp -f "$HOME/.gitignore_global" "$DEST/git/.gitignore_global"

# ── VSCode ────────────────────────────────────────────────
VSCODE_SRC="$HOME/.config/Code/User"
cp -f "$VSCODE_SRC/settings.json"    "$DEST/vscode/settings.json"
cp -f "$VSCODE_SRC/keybindings.json" "$DEST/vscode/keybindings.json"

# ── Claude Code ───────────────────────────────────────────
CLAUDE_SRC="$HOME/.claude"
cp -f "$CLAUDE_SRC/CLAUDE.md"      "$DEST/claude/CLAUDE.md"
cp -f "$CLAUDE_SRC/settings.json"  "$DEST/claude/settings.json"
[ -f "$CLAUDE_SRC/keybindings.json" ] && cp -f "$CLAUDE_SRC/keybindings.json" "$DEST/claude/keybindings.json"

# hooks 폴더 동기화
rsync -a --delete "$CLAUDE_SRC/hooks/" "$DEST/claude/hooks/"

# projects 폴더 — memory/, plans/ 만 백업 (.jsonl 대화록 제외)
rsync -a --delete --delete-excluded --prune-empty-dirs \
  --include='*/' \
  --include='*/memory/***' \
  --include='*/plans/***' \
  --exclude='*' \
  "$CLAUDE_SRC/projects/" "$DEST/claude/projects/"

# ── git commit & push ─────────────────────────────────────
cd "$DEST"

git add -A

if git diff --cached --quiet; then
    echo "$LOG_PREFIX 변경 없음 — push 생략"
else
    COMMIT_MSG="chore: auto backup $(date '+%Y-%m-%d')"
    git commit -m "$COMMIT_MSG"
    git push origin main
    echo "$LOG_PREFIX push 완료: $COMMIT_MSG"
fi

echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') 완료"
