#!/bin/bash
# ============================================================================
#  dvbuild.sh — 프로젝트별 빌드를 도커 안에서 실행
# ============================================================================
#  프로젝트마다 컨테이너·작업경로·빌드명령이 달라서 매번 헷갈린다. 표로 박아둔다.
#  호스트에서 make 돌리면 host/target 툴체인이 섞여 트리가 깨지므로 항상 컨테이너 안.
# ============================================================================
DVBUILD_VERSION='1.0.0'
set -u

DVB_CONF_DIR="$HOME/.devtools/dvbuild"
DVB_LOGDIR="$DVB_CONF_DIR/logs"
DVB_HISTORY="$DVB_CONF_DIR/history.log"
DVB_SELF="$(readlink -f "${BASH_SOURCE[0]}")"

usage() {
    cat <<'U'
dvbuild — 프로젝트별 도커 빌드

  dvbuild 609h                                   전체 빌드 (bear + make -j6)
  dvbuild 609h package/feeds/davo/dvmgmt/compile 부분 빌드
  dvbuild 754                                    dvbuild_mode.sh 3 (ab)
  dvbuild 754 1                                  dvbuild_mode.sh 1 (fastboot)
                                                 0 flat / 1 fastboot / 2 fota / 3 ab
  옵션
    -n         새 터미널 창 없이 현재 셸에서 실행
    log        마지막 빌드 로그 따라가기 (tail -f)
    init       alias 등록
    version    버전
U
}

do_init() {
    mkdir -p "$DVB_LOGDIR"
    if grep -qF "dvbuild.sh" "$HOME/.bash_aliases" 2>/dev/null; then
        echo "alias 이미 등록됨 (skip)"
    else
        printf "alias dvbuild='%s'\nalias dvb='%s'\n" "$DVB_SELF" "$DVB_SELF" >> "$HOME/.bash_aliases"
        echo "alias 등록: dvbuild, dvb"
    fi
    echo "완료. source ~/.bash_aliases"
}

case "${1:-}" in
    ''|-h|--help|help) usage; exit 0 ;;
    version|-V)        echo "dvbuild v${DVBUILD_VERSION}"; exit 0 ;;
    init)              do_init; exit 0 ;;
    log)               exec tail -f "$DVB_LOGDIR/latest" ;;
esac

NEWWIN=1
[ "${1:-}" = "-n" ] && { NEWWIN=0; shift; }
PROJ="$1"; shift

# ── 프로젝트 표 ──────────────────────────────────────────────────────────────
case "$PROJ" in
  609h|13_1)
    CT=ksc-609h_13_1; WD=/home/workspace; UOPT=""
    if [ $# -gt 0 ]; then CMD="make $* V=s"; else CMD="bear --append -- make -j6 V=s"; fi
    ;;
  754|dvf754|turbox)
    CT=davo_sdx_dock; WD=/home/turbox/workspace; UOPT="-u $(id -u):$(id -g)"
    CMD="./dvbuild_mode.sh ${1:-3}"
    ;;
  *)
    echo "모르는 프로젝트: $PROJ"; usage; exit 1 ;;
esac

mkdir -p "$DVB_LOGDIR"

# ── 이미 빌드 중이면 손대지 않는다 ───────────────────────────────────────────
if docker top "$CT" 2>/dev/null | grep -qE 'turbox_build|bear|[m]ake( |$)'; then
    echo "이미 빌드 중이다 — 중단한다. ($CT)"
    docker top "$CT" | grep -E 'turbox_build|bear|[m]ake( |$)'
    exit 3
fi

# ── 꺼져 있으면 켠다. 끄지는 않는다 (나중에 터미널 붙일 수 있으니) ───────────
STARTED=""
if [ "$(docker inspect -f '{{.State.Running}}' "$CT" 2>/dev/null)" != "true" ]; then
    echo "컨테이너가 꺼져 있어 시작한다: $CT (빌드 후에도 켜둔다)"
    docker start "$CT" >/dev/null || { echo "docker start 실패: $CT"; exit 1; }
    STARTED=" (내가 켬)"
fi

LOG="$DVB_LOGDIR/${PROJ}_$(date +%m%d_%H%M%S).log"
ln -sfn "$LOG" "$DVB_LOGDIR/latest"

# -t 필수: dvbuild_mode.sh 가 tee /dev/tty 를 쓴다. 없으면 성공을 FAIL로 오판한다
RUN="docker exec -t $UOPT -w $WD $CT bash -lc \"$CMD\""
INNER="set -o pipefail; echo '\$ $CMD'; $RUN 2>&1 | tee '$LOG'; rc=\$?; echo \"=== exit \$rc ===\" | tee -a '$LOG'"

echo "컨테이너 : $CT${STARTED}"
echo "작업경로 : $WD"
echo "명령     : $CMD"
echo "로그     : $LOG"
echo "            따라보기 → dvbuild log"
echo "$(date '+%F %T') | $PROJ | $CMD | $LOG" >> "$DVB_HISTORY"

if [ "$NEWWIN" = 1 ] && [ -n "${DISPLAY:-}" ] && command -v gnome-terminal >/dev/null; then
    if gnome-terminal --title="build $PROJ" -- bash -c "$INNER; exec bash"; then
        echo "새 터미널 창에서 빌드 중."
        exit 0
    fi
    echo "새 창 실패 — 현재 셸에서 실행한다"
fi
bash -c "$INNER"
