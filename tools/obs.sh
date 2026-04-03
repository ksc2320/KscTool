#!/bin/bash
# obs - Obsidian에서 파일/폴더 열기
# Usage: obs [파일경로]
#   인자 없으면 vault(~/memo) 열기
#   파일 경로 지정 시 해당 파일을 Obsidian에서 열기

VAULT_NAME="memo"
VAULT_PATH="$HOME/memo"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

open_uri() {
    nohup obsidian "$1" >/dev/null 2>&1 &
    disown
}

# 인자 없으면 vault만 열기
if [ $# -eq 0 ]; then
    echo -e "${CYAN}[obs]${NC} Opening vault: ${GREEN}${VAULT_NAME}${NC}"
    open_uri "obsidian://open?vault=${VAULT_NAME}"
    exit 0
fi

TARGET="$1"

# 절대경로로 변환
if [[ "$TARGET" != /* ]]; then
    TARGET="$(cd "$(dirname "$TARGET")" 2>/dev/null && pwd)/$(basename "$TARGET")"
fi

# 파일 존재 확인
if [ ! -e "$TARGET" ]; then
    echo -e "${RED}[obs] 파일 없음:${NC} $TARGET"
    exit 1
fi

# vault 경로 기준 상대경로 추출
REL_PATH="${TARGET#$VAULT_PATH/}"
if [ "$REL_PATH" = "$TARGET" ]; then
    echo -e "${RED}[obs] vault(${VAULT_PATH}) 밖의 파일입니다:${NC} $TARGET"
    exit 1
fi

# URI 인코딩 (공백, 한글 등)
ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$REL_PATH', safe='/'))")

echo -e "${CYAN}[obs]${NC} Opening: ${GREEN}${REL_PATH}${NC}"
open_uri "obsidian://open?vault=${VAULT_NAME}&file=${ENCODED}"
