#!/bin/bash
# gen_index.sh — bear(Docker) + compile_commands 리매핑 + ctags/cscope 생성
# Usage:
#   gen_index.sh [옵션]
#
# 옵션:
#   -c CONTAINER   Docker 컨테이너명 (기본: 자동 감지)
#   -p PROJECT_DIR 호스트 프로젝트 경로 (기본: 현재 디렉토리)
#   -t TARGET      빌드 타겟 (기본: 없음, 전체 빌드)
#   -j JOBS        병렬 빌드 수 (기본: nproc)
#   -s             ctags/cscope만 재생성 (bear 스킵)
#   -b             bear만 실행 (ctags/cscope 스킵)
#   -h             도움말
#
# 예시:
#   gen_index.sh                          # 전체 (bear + ctags + cscope)
#   gen_index.sh -t package/feeds/davo/dvmgmt/compile  # 특정 패키지만 bear
#   gen_index.sh -s                       # ctags/cscope만 재생성
#   gen_index.sh -c ksc-609h_13_1 -j 8   # 컨테이너/쓰레드 지정

set -euo pipefail

# ── 색상 ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[gen_index]${NC} $*"; }
ok()    { echo -e "${GREEN}[gen_index]${NC} $*"; }
warn()  { echo -e "${YELLOW}[gen_index]${NC} $*"; }
err()   { echo -e "${RED}[gen_index]${NC} $*" >&2; }

# ── 기본값 ──
CONTAINER=""
PROJECT_DIR="$(pwd)"
TARGET=""
JOBS="6"
SKIP_BEAR=false
SKIP_TAGS=false
DOCKER_WORKDIR="/home/workspace"

# ── 옵션 파싱 ──
while getopts "c:p:t:j:sbh" opt; do
    case $opt in
        c) CONTAINER="$OPTARG" ;;
        p) PROJECT_DIR="$OPTARG" ;;
        t) TARGET="$OPTARG" ;;
        j) JOBS="$OPTARG" ;;
        s) SKIP_BEAR=true ;;
        b) SKIP_TAGS=true ;;
        h)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) exit 1 ;;
    esac
done

PROJECT_DIR="$(realpath "$PROJECT_DIR")"

# ── 컨테이너 자동 감지 ──
if [[ -z "$CONTAINER" ]]; then
    CONTAINER=$(docker ps --format '{{.Names}}' | head -1)
    if [[ -z "$CONTAINER" ]]; then
        err "실행 중인 Docker 컨테이너가 없습니다. -c 옵션으로 지정하세요."
        exit 1
    fi
    info "컨테이너 자동 감지: ${YELLOW}${CONTAINER}${NC}"
fi

# ── Docker 마운트 경로 감지 ──
DOCKER_MOUNT=$(docker inspect "$CONTAINER" --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Destination}}{{"\n"}}{{end}}{{end}}' | grep -m1 workspace || true)
if [[ -n "$DOCKER_MOUNT" ]]; then
    DOCKER_WORKDIR="$DOCKER_MOUNT"
fi

# ════════════════════════════════════════════
# Phase 1: bear (Docker)
# ════════════════════════════════════════════
if [[ "$SKIP_BEAR" == false ]]; then
    info "Phase 1: bear 실행 (컨테이너: ${YELLOW}${CONTAINER}${NC})"

    BUILD_CMD="make -j${JOBS} ${TARGET}"
    BEAR_CMD="cd ${DOCKER_WORKDIR} && bear --append -- ${BUILD_CMD}"

    info "명령: ${CYAN}${BEAR_CMD}${NC}"
    echo ""

    # bear 실행 (기존 compile_commands.json에 append)
    docker exec -w "$DOCKER_WORKDIR" "$CONTAINER" \
        bash -c "$BEAR_CMD" 2>&1 | tail -5

    if [[ $? -ne 0 ]]; then
        warn "bear 빌드 중 오류 발생 (compile_commands.json은 부분 생성될 수 있음)"
    fi

    # ── compile_commands.json 복사 + 경로 리매핑 ──
    CC_JSON="${PROJECT_DIR}/compile_commands.json"
    DOCKER_CC="${DOCKER_WORKDIR}/compile_commands.json"

    if docker exec "$CONTAINER" test -f "$DOCKER_CC"; then
        info "compile_commands.json 복사 + 경로 리매핑"

        # Docker → 호스트 경로 변환
        docker exec "$CONTAINER" cat "$DOCKER_CC" | \
            python3 -c "
import sys, json
data = json.load(sys.stdin)
for entry in data:
    for key in ('directory', 'file', 'command'):
        if key in entry:
            entry[key] = entry[key].replace('${DOCKER_WORKDIR}', '${PROJECT_DIR}')
    if 'arguments' in entry:
        entry['arguments'] = [a.replace('${DOCKER_WORKDIR}', '${PROJECT_DIR}') for a in entry['arguments']]
json.dump(data, sys.stdout, indent=2)
" > "$CC_JSON"

        ENTRY_COUNT=$(python3 -c "import json; print(len(json.load(open('${CC_JSON}'))))")
        ok "compile_commands.json 생성 완료 (${ENTRY_COUNT} entries)"
    else
        warn "compile_commands.json이 Docker 내에 없습니다. 빌드가 정상인지 확인하세요."
    fi
else
    info "Phase 1 스킵 (bear)"
fi

# ════════════════════════════════════════════
# Phase 2: ctags + cscope (호스트)
# ════════════════════════════════════════════
if [[ "$SKIP_TAGS" == false ]]; then
    info "Phase 2: ctags + cscope 생성"

    cd "$PROJECT_DIR"

    # 인덱싱 대상 디렉토리 (davo 소스 + build_dir 내 dv_pkg)
    INDEX_DIRS=()
    [[ -d "davo" ]] && INDEX_DIRS+=("davo")
    DV_PKG="build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi/dv_pkg"
    [[ -d "$DV_PKG" ]] && INDEX_DIRS+=("$DV_PKG")

    if [[ ${#INDEX_DIRS[@]} -eq 0 ]]; then
        warn "인덱싱 대상 디렉토리를 찾을 수 없습니다."
        exit 1
    fi

    info "대상: ${YELLOW}${INDEX_DIRS[*]}${NC}"

    # ── ctags ──
    info "ctags 생성 중..."
    ctags -R --languages=C,C++ \
        --exclude='*.o' --exclude='*.ko' --exclude='ipkg-*' \
        --exclude='.svn' --exclude='node_modules' \
        -f "${PROJECT_DIR}/tags" \
        "${INDEX_DIRS[@]}"
    TAG_COUNT=$(wc -l < "${PROJECT_DIR}/tags")
    ok "tags 생성 완료 (${TAG_COUNT} lines)"

    # ── cscope ──
    info "cscope 파일 목록 생성 중..."
    find "${INDEX_DIRS[@]}" \
        \( -name '*.c' -o -name '*.h' -o -name '*.cpp' -o -name '*.hpp' \) \
        -not -path '*/ipkg-*' \
        -not -path '*/.svn/*' \
        -not -path '*/node_modules/*' \
        > "${PROJECT_DIR}/cscope.files"

    FILE_COUNT=$(wc -l < "${PROJECT_DIR}/cscope.files")
    info "cscope DB 생성 중 (${FILE_COUNT} files)..."
    cscope -bqR -i "${PROJECT_DIR}/cscope.files" -f "${PROJECT_DIR}/cscope.out"
    ok "cscope DB 생성 완료"
else
    info "Phase 2 스킵 (ctags/cscope)"
fi

# ── 요약 ──
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN} 인덱스 생성 완료${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
[[ -f "${PROJECT_DIR}/compile_commands.json" ]] && \
    echo -e "  compile_commands.json : $(du -h "${PROJECT_DIR}/compile_commands.json" | cut -f1)"
[[ -f "${PROJECT_DIR}/tags" ]] && \
    echo -e "  tags                  : $(du -h "${PROJECT_DIR}/tags" | cut -f1)"
[[ -f "${PROJECT_DIR}/cscope.out" ]] && \
    echo -e "  cscope.out            : $(du -h "${PROJECT_DIR}/cscope.out" | cut -f1)"
echo ""
