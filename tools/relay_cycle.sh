#!/bin/bash
# LCUS USB 릴레이 전원 사이클 시험 — 기본 9분 ON / 1분 OFF
#
# 사용법: relay_cycle.sh [사이클수]        (생략/0 = 무한)
#   DEV=/dev/ttyUSBn   릴레이 포트 (기본: CH340 by-id 경로)
#   ON_SEC / OFF_SEC   지속시간 초 (기본 540 / 60)
#   ON_JITTER=300      ON 시간에 0~N초를 매 사이클 무작위로 더한다 (기본 0 = 고정)
#   INVERT=0           NO 배선(코일 ON=전원 ON)일 때. 기본 1 = 현재 랙 배선(COM+NC, 코일 ON=전원 OFF)
#
# 예) 짧게 동작 확인:  ON_SEC=3 OFF_SEC=3 ./relay_cycle.sh 2
# 예) 야간 100회:      nohup ./relay_cycle.sh 100 > ~/test/relay_$(date +%m%d_%H%M).log 2>&1 &
#
# ON 을 고정하면 차단 시각이 매번 같은 업타임에 떨어진다(2026-08-13 실측: 535.59초 ±3ms).
# 장비 안에서 주기적으로 도는 일과 위상이 겹치면 그 지점만 반복 시험하게 되므로,
# 실패율을 재려면 ON_JITTER 로 위상을 흩어야 한다.
set -u

DEV=${DEV:-/dev/serial/by-id/usb-1a86_USB_Serial-if00-port0}
ON_SEC=${ON_SEC:-540}
ON_JITTER=${ON_JITTER:-0}
OFF_SEC=${OFF_SEC:-60}
INVERT=${INVERT:-1}   # 2026-08-13 실측: 코일 ON = 전원 OFF (COM+NC 배선)
CYCLES=${1:-0}

log() { echo "$(date '+%F %T') $*"; }

relay() { # relay on|off
	local on='\xA0\x01\x01\xA2' off='\xA0\x01\x00\xA1' tmp
	if [ "$INVERT" = 1 ]; then tmp=$on; on=$off; off=$tmp; fi
	if [ "$1" = on ]; then printf "$on" > "$DEV"; else printf "$off" > "$DEV"; fi
}

[ -w "$DEV" ] || { log "릴레이 포트에 쓸 수 없음: $DEV"; exit 1; }
stty -F "$DEV" 9600 raw -echo -hupcl || exit 1

# sleep 을 백그라운드로 돌리고 wait 로 기다린다. 그냥 `sleep`을 쓰면 bash 가
# sleep 이 끝날 때까지 트랩을 미뤄서, kill 해도 최대 9분 뒤에야 멈춘다.
nap() { sleep "$1" & nap_pid=$!; wait "$nap_pid"; }

# 중단(Ctrl-C/kill) 시 장비를 전원 OFF 상태로 방치하지 않는다
trap 'echo; log "중단 — 전원 ON 복구"
      [ -n "${nap_pid:-}" ] && kill "$nap_pid" 2>/dev/null
      relay on; exit 0' INT TERM

log "시작: dev=$DEV ON=${ON_SEC}s(+0~${ON_JITTER}s) OFF=${OFF_SEC}s 사이클=${CYCLES:-무한}"
n=0
while :; do
	n=$((n + 1))
	on_sec=$ON_SEC
	[ "$ON_JITTER" -gt 0 ] && on_sec=$((ON_SEC + RANDOM % (ON_JITTER + 1)))
	log "cycle $n : 전원 ON  (${on_sec}s)"
	relay on
	nap "$on_sec"
	log "cycle $n : 전원 OFF (${OFF_SEC}s)"
	relay off
	nap "$OFF_SEC"
	if [ "$CYCLES" -gt 0 ] && [ "$n" -ge "$CYCLES" ]; then break; fi
done
relay on
log "완료: $n 사이클, 전원 ON 상태로 종료"
