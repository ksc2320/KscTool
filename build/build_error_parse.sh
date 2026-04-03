#!/bin/bash
# ============================================================================
#  build_error_parse.sh — 빌드 로그에서 에러/경고 추출 (컬러)
# ============================================================================
#  사용법:
#    make V=s 2>&1 | ./build_error_parse.sh          # 파이프로 실시간
#    ./build_error_parse.sh build.log                  # 로그 파일 분석
#    make V=s 2>&1 | tee build.log | ./build_error_parse.sh  # 동시 저장+파싱
# ============================================================================

# ── 컬러 ──
readonly C_RED='\033[1;31m'
readonly C_YELLOW='\033[1;33m'
readonly C_CYAN='\033[1;36m'
readonly C_GREEN='\033[1;32m'
readonly C_MAGENTA='\033[1;35m'
readonly C_WHITE='\033[1;37m'
readonly C_DIM='\033[0;90m'
readonly C_BG_RED='\033[41;1;37m'
readonly C_BG_YELLOW='\033[43;1;30m'
readonly C_BG_GREEN='\033[42;1;37m'
readonly C_RESET='\033[0m'

# ── 카운터 ──
ERRORS=0
WARNINGS=0
NOTES=0
LINES_READ=0
LAST_PKG=""

# ── 파일 vs stdin ──
INPUT="${1:-/dev/stdin}"

echo ""
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  ${C_WHITE}Build Error Parser${C_RESET}  $(date '+%H:%M:%S')"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo ""

while IFS= read -r line; do
    LINES_READ=$((LINES_READ + 1))

    # ── 현재 빌드 중인 패키지 감지 ──
    if echo "$line" | grep -qE 'make\[[0-9]+\].*package/.*/compile'; then
        pkg=$(echo "$line" | sed -E 's|.*package/([^/]+)/.*|\1|')
        if [ "$pkg" != "$LAST_PKG" ] && [ -n "$pkg" ]; then
            LAST_PKG="$pkg"
            echo -e "${C_DIM}── 패키지: ${C_CYAN}${pkg}${C_RESET} ${C_DIM}──${C_RESET}"
        fi
    fi

    # ── error: (빨강, 굵게) ──
    if echo "$line" | grep -qiE ':\s*error:|^error:|fatal error|undefined reference|ld returned'; then
        ERRORS=$((ERRORS + 1))
        # 파일:라인 추출
        file_info=$(echo "$line" | grep -oE '[^ ]+\.[ch](pp)?:[0-9]+' | head -1)
        echo -e "${C_BG_RED} ERR ${C_RESET} ${C_RED}${line}${C_RESET}"
        continue
    fi

    # ── warning: (노랑) ──
    if echo "$line" | grep -qiE ':\s*warning:|^warning:'; then
        WARNINGS=$((WARNINGS + 1))
        # 너무 많으면 요약만
        if [ $WARNINGS -le 20 ]; then
            echo -e "${C_BG_YELLOW} WRN ${C_RESET} ${C_YELLOW}${line}${C_RESET}"
        elif [ $WARNINGS -eq 21 ]; then
            echo -e "${C_DIM}   ... 이후 warning 생략 (최종 카운트에 반영)${C_RESET}"
        fi
        continue
    fi

    # ── note: / In file included from (회색) ──
    if echo "$line" | grep -qiE ':\s*note:|In file included from'; then
        NOTES=$((NOTES + 1))
        [ $ERRORS -gt 0 ] && echo -e "${C_DIM}      ${line}${C_RESET}"
        continue
    fi

    # ── make error (빨강) ──
    if echo "$line" | grep -qiE 'make.*Error [0-9]|make.*Stop'; then
        ERRORS=$((ERRORS + 1))
        echo -e "${C_BG_RED} ERR ${C_RESET} ${C_MAGENTA}${line}${C_RESET}"
        continue
    fi

    # 진행 표시 (10000줄마다)
    if [ $((LINES_READ % 10000)) -eq 0 ]; then
        echo -ne "\r${C_DIM}  ... ${LINES_READ} lines processed${C_RESET}\033[K"
    fi

done < "$INPUT"

# ── 결과 요약 ──
echo ""
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "  ${C_BG_GREEN}  BUILD  ${C_RESET}  ${C_GREEN}CLEAN — 에러/경고 없음${C_RESET}"
elif [ $ERRORS -eq 0 ]; then
    echo -e "  ${C_BG_YELLOW}  BUILD  ${C_RESET}  ${C_YELLOW}경고 ${WARNINGS}개${C_RESET} (에러 없음)"
else
    echo -e "  ${C_BG_RED}  BUILD  ${C_RESET}  ${C_RED}에러 ${ERRORS}개${C_RESET} / ${C_YELLOW}경고 ${WARNINGS}개${C_RESET}"
fi

echo -e "  ${C_DIM}총 ${LINES_READ}줄 분석${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo ""

[ $ERRORS -gt 0 ] && exit 1
exit 0
