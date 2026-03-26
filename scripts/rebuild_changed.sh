#!/bin/bash
# ============================================================================
#  rebuild_changed.sh — SVN 변경 파일 → 해당 패키지만 재빌드
# ============================================================================
#  SVN diff로 변경된 파일을 분석하여 해당 패키지만 clean+compile
#
#  사용법:
#    ./rebuild_changed.sh          # 변경된 패키지 자동 감지+빌드
#    ./rebuild_changed.sh -d       # dry-run (빌드 안하고 목록만 표시)
#    ./rebuild_changed.sh -j4      # 병렬 빌드
# ============================================================================

# ── 컬러 ──
readonly C_RED='\033[1;31m'
readonly C_GREEN='\033[1;32m'
readonly C_YELLOW='\033[1;33m'
readonly C_CYAN='\033[1;36m'
readonly C_MAGENTA='\033[1;35m'
readonly C_WHITE='\033[1;37m'
readonly C_DIM='\033[0;90m'
readonly C_BG_GREEN='\033[42;1;37m'
readonly C_BG_RED='\033[41;1;37m'
readonly C_BG_CYAN='\033[46;1;37m'
readonly C_RESET='\033[0m'

readonly ICON_OK="${C_GREEN}✔${C_RESET}"
readonly ICON_FAIL="${C_RED}✘${C_RESET}"
readonly ICON_RUN="${C_CYAN}▶${C_RESET}"
readonly ICON_PKG="${C_MAGENTA}◆${C_RESET}"

# ── 설정 ──
DRY_RUN=0
JOBS="-j1"
VERBOSE="V=s"
PROJECT_ROOT=""

# ── 인자 파싱 ──
for arg in "$@"; do
    case "$arg" in
        -d|--dry-run) DRY_RUN=1 ;;
        -j*) JOBS="$arg" ;;
        -q|--quiet) VERBOSE="" ;;
        -h|--help)
            echo -e "${C_CYAN}rebuild_changed.sh${C_RESET} — SVN 변경분 자동 재빌드"
            echo ""
            echo "  사용법:"
            echo "    ./rebuild_changed.sh          # 변경 패키지 빌드"
            echo "    ./rebuild_changed.sh -d       # dry-run"
            echo "    ./rebuild_changed.sh -j4      # 병렬 빌드"
            exit 0
            ;;
    esac
done

# ── 프로젝트 루트 찾기 ──
# SOURCE_DIR 환경변수 또는 스크립트 위치 기준
if [ -n "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/Makefile" ]; then
    PROJECT_ROOT="$SOURCE_DIR"
elif [ -f "$(dirname "$0")/../Makefile" ]; then
    PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
else
    echo -e "${ICON_FAIL} ${C_RED}프로젝트 루트를 찾을 수 없음${C_RESET}"
    echo -e "${C_DIM}   SOURCE_DIR 환경변수 설정 필요${C_RESET}"
    exit 1
fi

cd "$PROJECT_ROOT" || exit 1

# ── 헤더 ──
echo ""
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "  ${C_WHITE}SVN Changed → Rebuild${C_RESET}"
echo -e "  Root: ${C_DIM}${PROJECT_ROOT}${C_RESET}"
[ $DRY_RUN -eq 1 ] && echo -e "  Mode: ${C_YELLOW}DRY RUN${C_RESET}"
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo ""

# ── SVN 변경 파일 수집 ──
echo -e "${ICON_RUN} SVN 변경 파일 분석..."

SVN_CHANGES=$(svn status -q 2>/dev/null)
if [ -z "$SVN_CHANGES" ]; then
    echo -e "${ICON_OK} ${C_GREEN}변경 사항 없음${C_RESET}"
    exit 0
fi

echo -e "${C_DIM}${SVN_CHANGES}${C_RESET}"
echo ""

# ── 변경 파일 → 패키지 매핑 ──
declare -A PKG_MAP  # 패키지명 → 변경파일 목록
declare -A PKG_TYPE # 패키지명 → 빌드 경로 타입

while IFS= read -r line; do
    status="${line:0:1}"
    filepath="${line:8}"

    # 삭제된 파일 무시
    [ "$status" == "D" ] && continue

    pkg_name=""
    build_path=""

    # feeds/davo/ 하위 → feeds 패키지
    if echo "$filepath" | grep -qE '^feeds/davo/'; then
        pkg_name=$(echo "$filepath" | sed -E 's|feeds/davo/([^/]+)/.*|\1|')
        build_path="package/feeds/davo/${pkg_name}"

    # davo/feeds/ 하위 (webui 등)
    elif echo "$filepath" | grep -qE '^davo/feeds/'; then
        pkg_name=$(echo "$filepath" | sed -E 's|davo/feeds/([^/]+/[^/]+)/.*|\1|' | tr '/' '_')
        # webui 패키지는 경로가 다름
        if echo "$filepath" | grep -qE 'webui'; then
            web_pkg=$(echo "$filepath" | sed -E 's|davo/feeds/webui/([^/]+)/.*|\1|')
            pkg_name="$web_pkg"
            build_path="package/feeds/davo/${web_pkg}"
        fi

    # package/ 하위
    elif echo "$filepath" | grep -qE '^package/'; then
        pkg_name=$(echo "$filepath" | sed -E 's|package/([^/]+/[^/]+)/.*|\2|')
        build_path=$(echo "$filepath" | sed -E 's|(package/[^/]+/[^/]+)/.*|\1|')

    # build_dir 직접 수정 (경고)
    elif echo "$filepath" | grep -qE '^build_dir/'; then
        pkg_name=$(echo "$filepath" | sed -E 's|build_dir/[^/]+/([^/]+)/.*|\1|')
        echo -e "  ${C_YELLOW}⚠ build_dir 직접 수정:${C_RESET} ${C_DIM}${filepath}${C_RESET}"
        echo -e "    ${C_YELLOW}→ 원본(feeds/davo 등) 수정 여부 확인 필요${C_RESET}"
        continue

    # davo/files 등은 빌드 불필요
    elif echo "$filepath" | grep -qE '^davo/files'; then
        echo -e "  ${C_DIM}  skip: ${filepath} (overlay 파일, 패키지 빌드 불필요)${C_RESET}"
        continue
    fi

    if [ -n "$pkg_name" ] && [ -n "$build_path" ]; then
        PKG_MAP["$pkg_name"]="${PKG_MAP[$pkg_name]:+${PKG_MAP[$pkg_name]}\n}    ${filepath}"
        PKG_TYPE["$pkg_name"]="$build_path"
    fi

done <<< "$SVN_CHANGES"

# ── 빌드 대상 표시 ──
PKG_COUNT=${#PKG_MAP[@]}

if [ $PKG_COUNT -eq 0 ]; then
    echo -e "${ICON_OK} ${C_GREEN}빌드 필요 패키지 없음${C_RESET} (overlay 파일만 변경됨)"
    exit 0
fi

echo -e "${ICON_RUN} 빌드 대상 패키지: ${C_WHITE}${PKG_COUNT}개${C_RESET}"
echo ""

for pkg in "${!PKG_MAP[@]}"; do
    echo -e "  ${ICON_PKG} ${C_WHITE}${pkg}${C_RESET}"
    echo -e "    ${C_DIM}path: ${PKG_TYPE[$pkg]}${C_RESET}"
    echo -e "${C_DIM}$(echo -e "${PKG_MAP[$pkg]}")${C_RESET}"
done

echo ""

# ── Dry Run이면 여기서 종료 ──
if [ $DRY_RUN -eq 1 ]; then
    echo -e "${C_BG_CYAN} DRY RUN ${C_RESET} 빌드 명령어:"
    for pkg in "${!PKG_TYPE[@]}"; do
        echo -e "  ${C_CYAN}make ${PKG_TYPE[$pkg]}/{clean,compile} ${JOBS} ${VERBOSE}${C_RESET}"
    done
    exit 0
fi

# ── 빌드 실행 ──
echo -e "${ICON_RUN} 빌드 시작..."
echo ""

BUILD_OK=0
BUILD_FAIL=0
START_TIME=$(date +%s)

for pkg in "${!PKG_TYPE[@]}"; do
    build_target="${PKG_TYPE[$pkg]}"
    echo -e "  ${ICON_RUN} ${C_WHITE}${pkg}${C_RESET} — clean+compile..."

    make "${build_target}/clean" ${JOBS} ${VERBOSE} 2>&1 | tail -3
    make "${build_target}/compile" ${JOBS} ${VERBOSE} 2>&1 | tail -20

    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo -e "  ${ICON_OK} ${C_GREEN}${pkg} 빌드 성공${C_RESET}"
        BUILD_OK=$((BUILD_OK + 1))
    else
        echo -e "  ${ICON_FAIL} ${C_RED}${pkg} 빌드 실패${C_RESET}"
        BUILD_FAIL=$((BUILD_FAIL + 1))
    fi
    echo ""
done

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# ── 결과 ──
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
if [ $BUILD_FAIL -eq 0 ]; then
    echo -e "  ${C_BG_GREEN}  DONE  ${C_RESET}  ${C_GREEN}${BUILD_OK}개 패키지 빌드 성공${C_RESET} (${ELAPSED}초)"
else
    echo -e "  ${C_BG_RED}  DONE  ${C_RESET}  ${C_RED}${BUILD_FAIL}개 실패${C_RESET} / ${C_GREEN}${BUILD_OK}개 성공${C_RESET} (${ELAPSED}초)"
fi
echo -e "${C_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo ""

[ $BUILD_FAIL -gt 0 ] && exit 1
exit 0
