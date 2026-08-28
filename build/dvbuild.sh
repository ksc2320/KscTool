#!/bin/bash
# ============================================================================
#  dvbuild.sh — 프로젝트별 빌드를 도커 안에서 실행
# ============================================================================
#  프로젝트마다 컨테이너·작업경로·빌드명령이 달라서 매번 헷갈린다. 표로 박아둔다.
#  호스트에서 make 돌리면 host/target 툴체인이 섞여 트리가 깨지므로 항상 컨테이너 안.
# ============================================================================
DVBUILD_VERSION='1.4.0'
set -u

DVB_CONF_DIR="$HOME/.devtools/dvbuild"
DVB_LOGDIR="$DVB_CONF_DIR/logs"
DVB_HISTORY="$DVB_CONF_DIR/history.log"
DVB_RUNDIR="$DVB_CONF_DIR/running"
DVB_SELF="$(readlink -f "${BASH_SOURCE[0]}")"

usage() {
    cat <<'U'
dvbuild — 프로젝트별 도커 빌드

  dvbuild 609h                                   전체 빌드 (bear + make -j6)
  dvbuild 609h dvmgmt                            부분 빌드 (패키지 이름만)
  dvbuild 754                                    dvbuild_mode.sh 3 (ab)
  dvbuild 754 1                                  dvbuild_mode.sh 1 (fastboot)
                                                 0 flat / 1 fastboot / 2 fota / 3 ab
  dvbuild 754 dvmgmt                             754 owrt 서브트리 부분 빌드
                                                 (피드 경로는 tmp/.packageinfo 에서 찾는다.
                                                  609H=davo, 754=tcatctl 등 트리마다 다르다)
  옵션
    (기본)     새 터미널 창을 띄워서 실행
    -b         창 없이 백그라운드 (`dvbuild log` 로 본다)
    -n         현재 셸에서 붙잡고 실행 (출력이 그대로 나온다)
    log [proj] 빌드 로그 따라가기 (tail -f). proj 주면 그 프로젝트 것
    stop [proj] dvbuild 로 건 빌드만 중단. 직접 건 빌드는 안 건드린다
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

# 패키지 이름 → make 타겟. 피드 디렉터리가 트리마다 달라서 .packageinfo 를 정본으로 쓴다
#   609H: package/feeds/davo/dvmgmt   754: package/feeds/tcatctl/dvmgmt
mktarget() {   # $1=트리 호스트경로  $2=패키지명 또는 make 타겟
    case "$2" in */*) echo "$2"; return 0 ;; esac
    local sm
    sm=$(awk -v p="$2" '/^Source-Makefile:/{sm=$2} $0=="Package: "p{print sm; exit}' \
         "$1/tmp/.packageinfo" 2>/dev/null)
    # kmod-* 처럼 Package 이름과 디렉터리명이 다른 경우: 디렉터리명으로 재시도
    [ -n "$sm" ] || sm=$(awk -v d="$2" '/^Source-Makefile:/{n=split($2,a,"/"); if(a[n-1]==d){print $2; exit}}' \
         "$1/tmp/.packageinfo" 2>/dev/null)
    [ -n "$sm" ] || { echo "패키지를 못 찾았다: $2 ($1/tmp/.packageinfo)" >&2; return 1; }
    echo "${sm%/Makefile}/compile"
}

# dvbuild 가 건 빌드에는 DVBUILD_ID 환경변수를 심는다. 자식까지 물려받으므로
# 이 표식으로 "내가 건 것"만 정확히 골라낼 수 있다.
# 이름(make/turbox_build)으로 pkill 하면 사용자가 직접 건 빌드까지 죽는다 — 실제로 겪었다.
find_pids() {   # $1=컨테이너  $2=DVBUILD_ID
    docker exec "$1" sh -c "grep -lz DVBUILD_ID=$2 /proc/[0-9]*/environ 2>/dev/null" 2>/dev/null \
        | sed 's|/proc/||; s|/environ||'
}

do_stop() {     # $1=프로젝트(생략하면 전부)
    local want="${1:-}" found=0 f id proj ct log pids left
    mkdir -p "$DVB_RUNDIR"
    for f in "$DVB_RUNDIR"/*; do
        [ -e "$f" ] || continue
        id=$(basename "$f")
        read -r proj ct log < "$f"
        [ -n "$want" ] && [ "$proj" != "$want" ] && continue
        pids=$(find_pids "$ct" "$id")
        [ -z "$pids" ] && { rm -f "$f"; continue; }   # 이미 끝난 것 정리
        found=1
        echo "중단: $proj ($ct)  pid: $(echo $pids | tr '\n' ' ')"
        docker exec "$ct" kill -INT $pids 2>/dev/null
        sleep 5
        left=$(find_pids "$ct" "$id")
        if [ -n "$left" ]; then
            echo "  SIGINT 후에도 남아서 강제 종료: $(echo $left | tr '\n' ' ')"
            docker exec "$ct" kill -KILL $left 2>/dev/null
        fi
        rm -f "$f"
        echo "  로그: $log"
    done
    [ "$found" = 0 ] && echo "dvbuild 가 건 빌드가 없다. (직접 건 빌드는 건드리지 않는다)"
    return 0
}

case "${1:-}" in
    ''|-h|--help|help) usage; exit 0 ;;
    version|-V)        echo "dvbuild v${DVBUILD_VERSION}"; exit 0 ;;
    init)              do_init; exit 0 ;;
    log)               exec tail -f "$DVB_LOGDIR/latest${2:+_$2}" ;;
    stop)              do_stop "${2:-}"; exit 0 ;;
esac

# 기본은 새 터미널 창. gnome-terminal 3.x 는 밖에서 기존 창에 탭을 못 붙인다
# (--tab 은 한 명령줄 안에서만 묶인다). 창이 싫으면 -b.
MODE=win
case "${1:-}" in
    -b) MODE=bg; shift ;;
    -n) MODE=fg; shift ;;
esac
PROJ="$1"; shift

# ── 프로젝트 표 ──────────────────────────────────────────────────────────────
case "$PROJ" in
  609h|13_1)
    CT=ksc-609h_13_1; WD=/home/workspace; UOPT=""
    if [ $# -eq 0 ]; then
        CMD="bear --append -- make -j6 V=s"
    else
        T=$(mktarget /home/workspace "$1") || exit 1
        CMD="make $T V=s"
    fi
    ;;
  754|dvf754|turbox)
    CT=davo_sdx_dock; UOPT="-u $(id -u):$(id -g)"
    if [ $# -eq 0 ] || [[ "$1" =~ ^[0-3]$ ]]; then
        WD=/home/turbox/workspace
        CMD="./dvbuild_mode.sh ${1:-3}"
    else
        # 부분 빌드는 owrt 서브트리에서. turbox_build.sh 엔 패키지 단위 옵션이 없다
        # (--ap-i 는 bootimg/sysimg/usrimg 이미지 단위)
        OWRT=Pinnacles_apps/apps_proc/owrt
        WD=/home/turbox/workspace/$OWRT
        T=$(mktarget /home/ksc/proj/turbox/$OWRT "$1") || exit 1
        CMD="make $T V=s"
    fi
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
ln -sfn "$LOG" "$DVB_LOGDIR/latest_$PROJ"   # 609h/754 동시 빌드 때 섞이지 않게

DVB_ID="dvb_$(date +%s)_$$"
mkdir -p "$DVB_RUNDIR"
echo "$PROJ $CT $LOG" > "$DVB_RUNDIR/$DVB_ID"

# -t 필수: dvbuild_mode.sh 가 tee /dev/tty 를 쓴다. 없으면 성공을 FAIL로 오판한다
# -e DVBUILD_ID: dvbuild stop 이 내가 건 빌드만 골라 죽이기 위한 표식
RUN="docker exec -t -e DVBUILD_ID=$DVB_ID $UOPT -w $WD $CT bash -lc \"$CMD\""
INNER="set -o pipefail; echo '\$ $CMD'; $RUN 2>&1 | tee '$LOG'; rc=\$?; echo \"=== exit \$rc ===\" | tee -a '$LOG'; rm -f '$DVB_RUNDIR/$DVB_ID'"

echo "컨테이너 : $CT${STARTED}"
echo "작업경로 : $WD"
echo "명령     : $CMD"
echo "로그     : $LOG"
echo "            따라보기 → dvbuild log $PROJ"
echo "$(date '+%F %T') | $PROJ | $CMD | $LOG" >> "$DVB_HISTORY"

case "$MODE" in
  win)
    if [ -n "${DISPLAY:-}" ] && command -v gnome-terminal >/dev/null \
       && gnome-terminal --title="build $PROJ" -- bash -c "$INNER; exec bash"; then
        echo "새 터미널 창에서 빌드 중."
        exit 0
    fi
    echo "새 창 실패 — 현재 셸에서 실행한다"
    bash -c "$INNER"
    ;;
  bg)
    setsid nohup bash -c "$INNER" >/dev/null 2>&1 &
    echo "백그라운드에서 빌드 중 (pid $!). 보려면: dvbuild log"
    ;;
  fg)
    bash -c "$INNER"
    ;;
esac
