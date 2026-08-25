#!/bin/bash
# ============================================================================
#  ttyusb.sh — ttyUSB 를 어느 USB 구멍에 꽂아도 바로 쓰게 만든다 v1.0.0
# ============================================================================
#
#   ttyusb.sh                    포트 목록 (고정이름 / 칩 / 권한 / 점유 프로세스)
#   ttyusb.sh setup              udev 규칙 설치 — 권한 개방 + 탐색 데몬 차단
#   ttyusb.sh name <포트> <이름> 그 어댑터에 고정 이름을 붙인다 (예: name /dev/ttyUSB1 ttyAP2)
#   ttyusb.sh free [포트..]      포트를 물고 있는 프로세스 정리 (기본 전체, -y 면 확인 생략)
#
# setup 은 한 번만 하면 끝. 그 뒤 "포트가 안 열린다"는 대개 권한이 아니라
# SecureCRT/minicom 이 아직 물고 있는 것이다 → ttyusb.sh free
#
# 이름 고정이 핵심이다. /dev/ttyUSB0,1,2 번호는 꽂는 순서·USB 포트마다 바뀌지만
# /dev/ttyAP0 같은 고정 이름은 어느 구멍에 꽂아도 같은 어댑터를 가리킨다.
# ============================================================================
set -u
TTYUSB_VERSION='1.1.0'

_T_RULE=/etc/udev/rules.d/99-ttyusb.rules
# 이름표는 따로 둔다. setup 이 기본 규칙을 덮어써도 붙여둔 이름이 날아가지 않는다.
_T_NAMES=/etc/udev/rules.d/99-ttyusb-names.rules
_T_SKY='\e[38;5;153m'; _T_GRAY='\e[38;5;245m'
_T_RED='\e[1;31m'; _T_GRN='\e[1;32m'; _T_YEL='\e[1;33m'; _T_RST='\e[0m'

# sudo — ROOT_PW 가 있으면 안 물어보고, 없으면 평소처럼 물어본다.
# `sudo -S` 는 비밀번호를 stdin 에서 읽는다. 그래서 `내용 | _t_sudo tee -a 파일` 처럼
# 쓰면 sudo 가 그 내용을 비밀번호로 삼켜버리고(파일에 비번이 써질 수도 있다) 만다.
# askpass 로 넘겨서 stdin 을 아예 건드리지 않는다.
_t_sudo() {
	[ -f "$HOME/.private/secrets.sh" ] && . "$HOME/.private/secrets.sh"
	[ -n "${ROOT_PW:-}" ] || { sudo "$@"; return $?; }
	local ap rc
	ap=$(mktemp); chmod 700 "$ap"
	printf '#!/bin/sh\nprintf "%%s\\n" "$_TTYUSB_PW"\n' > "$ap"
	_TTYUSB_PW="$ROOT_PW" SUDO_ASKPASS="$ap" sudo -A "$@"; rc=$?
	rm -f "$ap"
	return $rc
}

_t_prop() { udevadm info -q property -n "$1" 2>/dev/null | sed -n "s/^$2=//p"; }

# by-id/by-path 를 뺀 고정 심볼릭 이름 (udev SYMLINK 로 만든 것)
_t_names() {
	udevadm info -q symlink -n "$1" 2>/dev/null | tr ' ' '\n' |
		grep -v '^serial/' | grep -v '^$' | sed 's|^|/dev/|' | tr '\n' ',' | sed 's/,$//'
}

_t_list() {
	local devs=(/dev/ttyUSB*) d chip ser name perm pids who
	if [ ! -e "${devs[0]}" ]; then
		echo -e "${_T_YEL}ttyUSB 장치 없음${_T_RST} — 케이블/전원부터: lsusb ; dmesg | tail"
		return 1
	fi
	echo -e "${_T_SKY}포트          칩                시리얼     고정이름       권한 점유${_T_RST}"
	for d in "${devs[@]}"; do
		chip=$(_t_prop "$d" ID_MODEL); [ -n "$chip" ] || \
			chip="$(_t_prop "$d" ID_VENDOR_ID):$(_t_prop "$d" ID_MODEL_ID)"
		ser=$(_t_prop "$d" ID_SERIAL_SHORT); ser=${ser:--}
		name=$(_t_names "$d"); name=${name:--}
		if [ -r "$d" ] && [ -w "$d" ]; then perm="${_T_GRN}OK${_T_RST}"; else perm="${_T_RED}NO${_T_RST}"; fi
		pids=$(fuser "$d" 2>/dev/null)
		who='-'
		[ -n "$pids" ] && who=$(for p in $pids; do echo -n "$(ps -o comm= -p "$p" 2>/dev/null)($p) "; done)
		printf "%-13s %-17s %-10s %-14s %-14b %s\n" "$d" "${chip:0:17}" "$ser" "$name" "$perm" "$who"
	done
	grep -q ID_MM_PORT_IGNORE "$_T_RULE" 2>/dev/null || \
		echo -e "\n${_T_YEL}udev 규칙 미설치${_T_RST} — ${_T_SKY}ttyusb.sh setup${_T_RST} 한 번 실행하면 권한·이름 고정이 끝난다"
	echo -e "${_T_GRAY}고정이름이 '-' 인 어댑터: ttyusb name <포트> <이름>  (예: ttyusb name /dev/ttyUSB1 ttyAP2)${_T_RST}"
}

_t_setup() {
	local tmp; tmp=$(mktemp)
	cat > "$tmp" <<'EOF'
# ttyUSB 공통 규칙 — KscTool tools/ttyusb.sh setup 이 만든 파일
#
# 1) 권한: 누가 어디에 꽂아도 바로 열린다 (dialout 그룹 + 0666)
# 2) ModemManager / brltty 가 새로 꽂힌 포트를 "모뎀인가?" 하고 몇 초간
#    붙잡으며 AT 명령을 흘려보내는 것을 막는다. 부팅 직후·재연결 직후
#    포트가 안 열리거나 콘솔에 쓰레기 문자가 찍히는 원인이 이것이다.
SUBSYSTEM=="tty", KERNEL=="ttyUSB*", GROUP="dialout", MODE="0666", \
	ENV{ID_MM_PORT_IGNORE}="1", ENV{ID_MM_DEVICE_IGNORE}="1", ENV{BRLTTY_DEVICE_IGNORE}="1"

# 3) 이름 고정은 별도 파일(99-ttyusb-names.rules)에서 한다 — `ttyusb name` 참고
EOF
	echo -e "${_T_SKY}[1/4]${_T_RST} udev 규칙 설치 → $_T_RULE"
	if [ -f "$_T_RULE" ] && [ ! -f "$_T_RULE.bak" ]; then
		_t_sudo cp "$_T_RULE" "$_T_RULE.bak" && echo "      기존 파일 백업: $_T_RULE.bak"
	fi
	_t_sudo install -m 644 -o root -g root "$tmp" "$_T_RULE" || { rm -f "$tmp"; return 1; }
	rm -f "$tmp"

	if [ ! -f "$_T_NAMES" ]; then
		tmp=$(mktemp)
		cat > "$tmp" <<'EOF'
# ttyUSB 이름표 — `ttyusb name <포트> <이름>` 이 여기에 한 줄씩 추가한다.
# 어댑터의 시리얼번호로 잡으므로 USB 구멍을 바꿔 꽂아도 경로가 같다.
# SecureCRT 세션도 /dev/ttyUSB1 대신 여기서 정한 이름을 쓰면 다시 꽂을 때마다
# 세션 설정을 고칠 일이 없다. 지우려면 해당 줄만 삭제 후 `ttyusb setup`.
EOF
		_t_sudo install -m 644 -o root -g root "$tmp" "$_T_NAMES"
		rm -f "$tmp"
		echo "      이름표 파일 생성: $_T_NAMES"
	fi

	echo -e "${_T_SKY}[2/4]${_T_RST} 규칙 다시 읽기 + 이미 꽂혀 있는 포트에 적용"
	_t_sudo udevadm control --reload
	_t_sudo udevadm trigger --subsystem-match=tty --action=add
	udevadm settle

	echo -e "${_T_SKY}[3/4]${_T_RST} dialout 그룹 / 별칭 등록"
	if id -nG | grep -qw dialout; then
		echo "      dialout 그룹: 이미 소속"
	else
		_t_sudo usermod -aG dialout "$USER" && \
			echo -e "      dialout 그룹 추가 — ${_T_YEL}다시 로그인해야 적용${_T_RST}"
	fi
	if grep -q "alias ttyusb=" "$HOME/.bash_aliases" 2>/dev/null; then
		echo "      alias ttyusb: 이미 등록"
	else
		# ##tools 섹션 안에 넣는다. 섹션이 없으면 파일 끝에 붙인다.
		if grep -q '^##tools' "$HOME/.bash_aliases" 2>/dev/null; then
			awk -v line="alias ttyusb=\"\$HOME/KscTool/tools/ttyusb.sh\"" \
				'{print} /^##tools/{print line}' "$HOME/.bash_aliases" > "$HOME/.bash_aliases.new" &&
				mv "$HOME/.bash_aliases.new" "$HOME/.bash_aliases"
		else
			echo "alias ttyusb=\"\$HOME/KscTool/tools/ttyusb.sh\"" >> "$HOME/.bash_aliases"
		fi
		echo -e "      alias ttyusb 등록 — ${_T_SKY}source ~/.bash_aliases${_T_RST} 후 사용"
	fi

	# 검증: 규칙이 실제로 먹었는지 본다. 여기서 FAIL 이면 설치가 안 된 것이다.
	echo -e "${_T_SKY}[4/4]${_T_RST} 검증"
	local d fail=0
	for d in /dev/ttyUSB*; do
		[ -e "$d" ] || { echo "      (꽂힌 포트 없음 — 꽂은 뒤 ttyusb.sh 로 확인)"; break; }
		if [ -w "$d" ] && [ "$(_t_prop "$d" ID_MM_PORT_IGNORE)" = 1 ]; then
			echo -e "      ${_T_GRN}PASS${_T_RST} $d  $(_t_names "$d")"
		else
			echo -e "      ${_T_RED}FAIL${_T_RST} $d  쓰기=$([ -w "$d" ] && echo o || echo x) MM무시=$(_t_prop "$d" ID_MM_PORT_IGNORE)"
			fail=1
		fi
	done
	[ $fail -eq 0 ] && echo -e "\n${_T_GRN}완료${_T_RST} — 이제 어느 USB 포트에 꽂아도 바로 열린다" || \
		echo -e "\n${_T_RED}일부 실패${_T_RST} — udevadm test /sys/class/tty/ttyUSB0 로 규칙 적용 로그 확인"
	return $fail
}

_t_name() {
	local dev=${1:-} nm=${2:-} ser vid pid line
	if [ -z "$dev" ] || [ -z "$nm" ]; then
		echo "사용법: ttyusb name <포트|시리얼번호> <이름>   예) ttyusb name /dev/ttyUSB1 ttyAP2"
		return 1
	fi
	case "$nm" in
		*[!A-Za-z0-9_-]*) echo -e "${_T_RED}이름에 쓸 수 없는 문자${_T_RST} — 영문/숫자/_/- 만"; return 1 ;;
	esac
	[ -e "/dev/$nm" ] && [ ! -L "/dev/$nm" ] && { echo -e "${_T_RED}/dev/$nm 은 이미 실제 장치${_T_RST}"; return 1; }

	case "$dev" in /dev/*) ;; *) dev="/dev/$dev" ;; esac
	if [ -e "$dev" ]; then
		ser=$(_t_prop "$dev" ID_SERIAL_SHORT)
		vid=$(_t_prop "$dev" ID_VENDOR_ID); pid=$(_t_prop "$dev" ID_MODEL_ID)
	else
		echo -e "${_T_RED}$dev 없음${_T_RST} — ttyusb 목록에서 포트 이름을 확인하세요"; return 1
	fi

	if [ -n "$ser" ]; then
		line="SUBSYSTEM==\"tty\", KERNEL==\"ttyUSB*\", ATTRS{serial}==\"$ser\", SYMLINK+=\"$nm\""
	else
		# 시리얼번호가 없는 어댑터(CH340 등)는 칩 종류로만 잡을 수 있다.
		# 같은 칩을 두 개 꽂으면 둘이 같은 이름을 다투므로 그때는 by-path 로 구분해야 한다.
		line="SUBSYSTEM==\"tty\", KERNEL==\"ttyUSB*\", ATTRS{idVendor}==\"$vid\", ATTRS{idProduct}==\"$pid\", SYMLINK+=\"$nm\""
		echo -e "${_T_YEL}주의${_T_RST} 이 어댑터는 시리얼번호가 없어 칩($vid:$pid) 종류로만 잡습니다 — 같은 칩 2개를 함께 꽂으면 겹칩니다"
	fi

	[ -f "$_T_NAMES" ] || _t_setup >/dev/null || return 1
	if grep -qF "SYMLINK+=\"$nm\"" "$_T_NAMES" 2>/dev/null; then
		echo -e "${_T_YEL}이름 $nm 은 이미 쓰는 중${_T_RST} — 바꾸려면 $_T_NAMES 에서 그 줄을 지우고 다시 실행"
		return 1
	fi
	grep -qF "\"${ser:-$vid}\"" "$_T_NAMES" 2>/dev/null &&
		echo -e "${_T_YEL}주의${_T_RST} 이 어댑터에 이름이 이미 있습니다 — 이름이 두 개 붙습니다(둘 다 동작)"

	local tmp; tmp=$(mktemp)
	cat "$_T_NAMES" > "$tmp" && printf '%s\n' "$line" >> "$tmp" &&
		_t_sudo install -m 644 -o root -g root "$tmp" "$_T_NAMES" || { rm -f "$tmp"; return 1; }
	rm -f "$tmp"
	_t_sudo udevadm control --reload
	_t_sudo udevadm trigger --subsystem-match=tty --action=add
	udevadm settle
	if [ -e "/dev/$nm" ]; then
		echo -e "${_T_GRN}완료${_T_RST} /dev/$nm → $(basename "$(readlink -f "/dev/$nm")")  (시리얼 ${ser:-없음})"
	else
		echo -e "${_T_RED}실패${_T_RST} /dev/$nm 이 안 생겼습니다 — $_T_NAMES 확인"
		return 1
	fi
}

_t_free() {
	local yes=0
	[ "${1:-}" = -y ] && { yes=1; shift; }
	local targets=("$@") dev pids lock p still a
	[ ${#targets[@]} -eq 0 ] && targets=(/dev/ttyUSB*)
	for dev in "${targets[@]}"; do
		[ -e "$dev" ] || { echo "$dev: 없음"; continue; }
		lock="/var/lock/LCK..$(basename "$dev")"
		pids=$(fuser "$dev" 2>/dev/null)
		if [ -z "$pids" ]; then
			if [ -e "$lock" ]; then
				_t_sudo rm -f "$lock" && echo -e "$dev: ${_T_GRN}묵은 락파일 제거${_T_RST} ($lock)"
			else
				echo "$dev: 점유 없음 — 바로 쓸 수 있다"
			fi
			continue
		fi
		echo -e "$dev ${_T_YEL}점유 중${_T_RST}:"
		for p in $pids; do printf "    PID %-7s %s\n" "$p" "$(ps -o args= -p "$p" 2>/dev/null | cut -c1-70)"; done
		if [ $yes -eq 0 ]; then
			# SecureCRT 는 프로세스 하나가 모든 탭을 들고 있다. 죽이면 다른 세션의
			# 진행 중인 시험 로그까지 함께 끊긴다 — 그래서 기본은 물어본다.
			read -r -p "    종료할까요? SecureCRT 면 다른 탭·기록 중인 로그도 함께 끊긴다 [y/N] " a
			[ "$a" = y ] || [ "$a" = Y ] || { echo "    건너뜀"; continue; }
		fi
		kill $pids 2>/dev/null
		sleep 1
		still=$(fuser "$dev" 2>/dev/null)
		[ -n "$still" ] && { echo "    안 죽음 → kill -9"; kill -9 $still 2>/dev/null; sleep 1; }
		[ -e "$lock" ] && _t_sudo rm -f "$lock"
		if [ -z "$(fuser "$dev" 2>/dev/null)" ]; then
			echo -e "    ${_T_GRN}해제 완료${_T_RST}"
		else
			echo -e "    ${_T_RED}해제 실패${_T_RST} — 남은 PID: $(fuser "$dev" 2>&1)"
		fi
	done
}

case "${1:-list}" in
	setup)          _t_setup ;;
	name)           shift; _t_name "$@" ;;
	free)           shift; _t_free "$@" ;;
	list)           _t_list ;;
	version|-V)     echo "ttyusb v${TTYUSB_VERSION}" ;;
	-h|--help|help) awk 'NR>1 && /^# ?=+$/ {next} NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0" ;;
	*)              echo "알 수 없는 명령: $1  (list | setup | free | help)"; exit 1 ;;
esac
