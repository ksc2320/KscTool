#!/bin/bash
# 부팅마다 장비에 스레드 대기지점 샘플러를 다시 걸어준다.
#
# DVF-754 는 시험 중 10분마다 재부팅되고 /tmp 가 날아가므로, 샘플러도 매번 사라진다.
# 이 스크립트는 릴레이 제어 로그에서 "전원 ON" 을 감지해 CWMP 기동을 기다린 뒤
# 시리얼 콘솔로 샘플러를 재설치한다.
#
# 사용: rearm_wchan.sh <릴레이_로그>
set -u

RELAY_LOG="${1:?릴레이 로그 경로}"
CRT=/tmp/claude-1000/-home-ksc-proj-turbox-Pinnacles-apps-apps-proc-owrt/5a2756b8-86e2-499a-ae56-d2b5ce195cad/scratchpad/crtcmd.sh
# CWMP 는 부팅 후 약 176초에 기동하고 33초 boot delay 를 거친다. 넉넉히 기다린다.
WAIT_AFTER_BOOT=${WAIT_AFTER_BOOT:-230}

arm() {
	bash "$CRT" RARM <<'EOF' 2>&1 | tail -3
cat >/tmp/w.sh <<'X'
while :; do
S=
for t in /proc/$1/task/*; do
W=$(cat $t/wchan)
Y=$(cut -d" " -f1-2 $t/syscall)
S="$S$W/$Y,"
done
echo "WCH $S" >/dev/kmsg
sleep 1
done
X
sh /tmp/w.sh $(pidof cwmpsslClient_lgnms) &
echo armed
EOF
}

echo "$(date '+%T') 재장착 감시 시작 (부팅 후 ${WAIT_AFTER_BOOT}초 대기)"
tail -n 0 -F "$RELAY_LOG" 2>/dev/null | while read -r line; do
	case "$line" in
		*"전원 ON"*) ;;
		*) continue;;
	esac
	echo "$(date '+%T') 전원 ON 감지 — ${WAIT_AFTER_BOOT}초 후 재장착"
	sleep "$WAIT_AFTER_BOOT"
	out=$(arm)
	echo "$(date '+%T') 재장착 결과: ${out//$'\n'/ | }"
done
