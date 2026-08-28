#!/usr/bin/env bash
# backup_dotfiles.sh — 매일 dotfiles를 ~/dotfiles/ 에 모아 GitHub private repo에 push
# cron: 0 2 * * * /home/ksc/KscTool/scripts/backup_dotfiles.sh >> /home/ksc/.dotfiles_backup.log 2>&1
#       (2026-08-28 주1회 → 매일. 스킬·규칙이 자주 바뀌는데 최대 7일치가 날아갈 수 있었다)

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
[ -f "$CLAUDE_SRC/COMMON.md" ]     && cp -f "$CLAUDE_SRC/COMMON.md" "$DEST/claude/COMMON.md"
[ -f "$CLAUDE_SRC/keybindings.json" ] && cp -f "$CLAUDE_SRC/keybindings.json" "$DEST/claude/keybindings.json"

# hooks 폴더 동기화
rsync -a --delete "$CLAUDE_SRC/hooks/" "$DEST/claude/hooks/"

# skills 폴더 동기화 — 여기가 빠져 있어서 스킬 18개가 백업 밖에 있었다 (2026-08-28)
mkdir -p "$DEST/claude/skills"
rsync -a --delete "$CLAUDE_SRC/skills/" "$DEST/claude/skills/"

# ── 도구 설정 (~/.devtools) ───────────────────────────────
# 사용자 결정(2026-08-28): 비공개 저장소이므로 토큰·접속정보까지 통째로 백업한다.
# 이게 없으면 디스크가 죽었을 때 웹훅·봇토큰 재발급부터 다시 해야 한다.
# 로그·산출물은 매일 바뀌기만 하고 복구 가치가 없어 뺀다.
mkdir -p "$DEST/devtools"
rsync -a --delete \
  --exclude='*.log' --exclude='logs/' --exclude='runs/' \
  --exclude='artifacts/' --exclude='*.pid' --exclude='*.lock' \
  "$HOME/.devtools/" "$DEST/devtools/"

# ── Codex ─────────────────────────────────────────────────
# 규칙·설정만. auth.json(자격증명)·sessions·skills(=Claude 쪽 심볼릭 링크)는 제외한다.
CODEX_SRC="$HOME/.codex"
mkdir -p "$DEST/codex"
for f in AGENTS.md config.toml hooks.json; do
    [ -f "$CODEX_SRC/$f" ] && cp -f "$CODEX_SRC/$f" "$DEST/codex/$f"
done

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
