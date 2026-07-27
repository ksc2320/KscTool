#!/bin/bash
# ftd AP IP 감지 자체 검증 — ping 을 스텁으로 갈아 실기 없이 판정
source /home/ksc/KscTool/ftd/file_to_dev.sh 2>/dev/null

# 스텁: 살아있는 IP 목록만 응답
ALIVE="192.168.1.1 172.30.1.254"
ping() { local ip="${@: -1}"; [[ " $ALIVE " == *" $ip "* ]]; }

# 스텁: 호스트 enx 2장 (실제 현재 상태와 동일)
_ftd_enx_list() { echo "enxb0386cf16748 192.168.1.4"; echo "enx88366cfae4f4 172.30.1.3"; }

chk() { # 설명 기대AP 기대서버 실제AP 실제서버
    if [ "$2" = "$4" ] && [ "$3" = "$5" ]; then echo "  PASS  $1 → $4 / server $5"
    else echo "  FAIL  $1 → got $4 / server $5 (want $2 / server $3)"; FAILED=1; fi
}

# 1) 754 FW(.zip) → 192.168.1.1, 서버는 같은 서브넷
_ftd_detect_network "$(_ftd_ap_octet_for_fw update_full_ext4.zip)"
chk ".zip (DVF-754)" 192.168.1.1 192.168.1.4 "$(_ftd_ap_ip)" "$(_ftd_server_ip)"

# 2) 그 외 FW(.img) → 172.30.1.254, 서버는 같은 서브넷
_ftd_detect_network "$(_ftd_ap_octet_for_fw fw_609h.img)"
chk ".img (609H)" 172.30.1.254 172.30.1.3 "$(_ftd_ap_ip)" "$(_ftd_server_ip)"

# 3) FW 없는 명령(cmd/ssh/reboot) → 254 우선
_ftd_detect_network
chk "FW 없음 (254 우선)" 172.30.1.254 172.30.1.3 "$(_ftd_ap_ip)" "$(_ftd_server_ip)"

# 4) 754만 꽂힌 상태에서 FW 없는 명령 → .1 로 폴백 탐색
ALIVE="192.168.1.1"
_ftd_detect_network
chk "754만 연결" 192.168.1.1 192.168.1.4 "$(_ftd_ap_ip)" "$(_ftd_server_ip)"

# 5) 전부 죽음 → 첫 enx 기준 폴백 (기존 동작 유지, 크래시 없음)
ALIVE=""
_ftd_detect_network 254
chk "AP 없음 폴백" 192.168.1.254 192.168.1.4 "$(_ftd_ap_ip)" "$(_ftd_server_ip)"

# 6) 옥텟 분류기
[ "$(_ftd_ap_octet_for_fw x.zip)" = 1 ] && [ "$(_ftd_ap_octet_for_fw x.img)" = 254 ] &&
    [ "$(_ftd_ap_octet_for_fw)" = 254 ] && echo "  PASS  octet 분류기" || { echo "  FAIL  octet 분류기"; FAILED=1; }

[ -z "$FAILED" ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
