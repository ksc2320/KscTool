# ~/.bashrc: executed by bash(1) for non-login shells.
# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# Set environment variables
export PATH=/usr/bin:/usr/local/bin:$PATH
export EDITOR="vim"

# History settings
HISTCONTROL=ignoreboth # Ignore duplicate commands in history
HISTSIZE=1000          # Number of commands in history
HISTFILESIZE=2000      # Max number of history file lines

# Improve terminal behavior
shopt -s histappend   # Append history instead of overwriting
shopt -s checkwinsize # Adjust window size automatically

# Improve less command support
# 성능 최적화: lesspipe는 필요할 때만 로드
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)" 2>/dev/null

# Detect chroot environment (for prompt)
if [ -z "$debian_chroot" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

if [ -t 0 ]; then
    stty sane
    stty -ixon
    stty erase ^?
fi

# Set terminal prompt (PS1)
PS1='[\u@\h \w]\$ '

# Remove unnecessary variables
unset color_prompt force_color_prompt

# Enable color support for commands
# 성능 최적화: dircolors는 한 번만 실행하고 결과를 캐시
if [ -x /usr/bin/dircolors ]; then
    DIRCOLORS_CACHE="$HOME/.dircolors_cache"
    if [ ! -f "$DIRCOLORS_CACHE" ] || [ "$DIRCOLORS_CACHE" -ot ~/.dircolors ] 2>/dev/null || [ ! -s "$DIRCOLORS_CACHE" ]; then
        dircolors -b ~/.dircolors 2>/dev/null || dircolors -b > "$DIRCOLORS_CACHE" 2>/dev/null
    fi
    [ -f "$DIRCOLORS_CACHE" ] && eval "$(cat "$DIRCOLORS_CACHE")" 2>/dev/null
    alias ls='ls --color=auto'
    alias vi='vim'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# some more ls aliases
alias ll='ls -alrtF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

#change
NOW_PROJECT=609

# 개인정보/민감 정보 로드 (~/.private/ 폴더 — 공유 제외)
for _pvf in ~/.private/*.sh; do [[ -f "$_pvf" ]] && source "$_pvf"; done; unset _pvf

[ -f ~/.bash_aliases ] && source ~/.bash_aliases
[ -f ~/.bash_completion ] && source ~/.bash_completion
[ -f ~/.bash_functions ] && source ~/.bash_functions
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

export PS1="\[${cBold}${cWhite}\][ \[\$(echo -e \$(get_prompt_color))\]\$(shorten_path)\[\] \[${cWhite}\]]\[${cReset}\] \[${cWhite}\]> \[${cReset}\]"

# 우 ALT 비활성화 및 한/영 키로 동작 ( RALT+한/영 -> 한/영 )
# 성능 최적화: X11 세션이 있을 때만 실행하고, 캐시 사용
if [ -n "$DISPLAY" ] && command -v xmodmap >/dev/null 2>&1; then
    # 캐시 파일을 사용하여 이미 설정되었는지 확인
    XMODMAP_CACHE="$HOME/.xmodmap_cache"
    if [ ! -f "$XMODMAP_CACHE" ] || [ "$XMODMAP_CACHE" -ot ~/.bashrc ]; then
        if ! xmodmap -pke 2>/dev/null | grep -q "keycode 108 = Hangul"; then
            setxkbmap -layout us,kr -option grp:ralt_toggle 2>/dev/null
            xmodmap -e "clear mod1" 2>/dev/null           # mod1 초기화
            xmodmap -e "add mod1 = Alt_L" 2>/dev/null     # 좌측 Alt를 mod1에 추가
            xmodmap -e "keycode 108 = Hangul" 2>/dev/null # 우측 Alt를 Hangul 전환으로 설정
        fi
        touch "$XMODMAP_CACHE" 2>/dev/null
    fi
fi

# davolink coding aliase
# 성능 최적화: NVM 지연 로딩 (필요할 때만 로드)
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
    _load_nvm() {
        unset -f nvm node npm npx _load_nvm
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    }
    nvm()  { _load_nvm; nvm "$@"; }
    node() { _load_nvm; node "$@"; }
    npm()  { _load_nvm; npm "$@"; }
    npx()  { _load_nvm; npx "$@"; }
fi
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion" 2>/dev/null

export CC="ccache gcc"
export CXX="ccache g++"

#personal
export USER="ksc"      #user name
export USER_NAME="KSC" #for UI

#davo
# 성능 최적화: DOCKER_CONTAINER가 설정된 후에 DOCKER_EXEC 설정
export TFTP_PATH="/tftpboot"
export HTTP_PATH="$HOME/server_ksc"
# DOCKER_EXEC는 case 문 이후에 설정됨 (아래 참조)

declare -A PROJECT_DIRS=(
    [609]="$HOME/proj/13_1"
    [609_test]="$HOME/proj/dv03_609h_test"
    [13_1]="$HOME/proj/13_1"
    [13_0]="$HOME/proj/13_0"
    [12_5]="$HOME/proj/12_5"
    [12_4]="$HOME/proj/12_4"
    [901]="$HOME/proj/dv01-901h"
    [012]="$HOME/proj/dv02-012h"
    [501]="$HOME/proj/dv03-501h"
    [704]="$HOME/proj/dvw704"
    [usen]="$HOME/proj/usen"
    [turbo]="$HOME/proj/turbo"
)

get_proj_dir() {
    echo "${PROJECT_DIRS[$1]}"
}

# ================================================================= #
#                          DAVO Project                             #
# ================================================================= #
PROJECT_DIR=$(get_proj_dir $NOW_PROJECT)
WORKSPACE_DIR="/home/workspace"
#SOURCE_DIR=$PROJECT_DIR
SOURCE_DIR=$WORKSPACE_DIR

# dv cp 우선 검색
FW_PRIORITY_SEARCH=""

# davolink PROJECT
case $NOW_PROJECT in
901)
    #not tested
    ;;
012)
    DOCKER_CONTAINER="ksc-012h"
    # FW_PATH="$(ls -t $PROJECT_DIR/bin/ipq/ | grep DVW-602X | grep .img | head -n 1 | xargs)"
    FW_DIR="$PROJECT_DIR/bin/ipq/"
    FW_NAME="fw_012h.img"
	TARGET_DIR="$SOURCE_DIR/build_dir/target-aarch64_cortex-a53_musl-1.1.16/"
    ;;
12_4|12_5)
    DOCKER_CONTAINER="ksc-410h"
    # FW_PATH="$(ls -t $PROJECT_DIR/bin/targets/ipq53xx/ipq53xx_32 | grep DVW-712X | grep .img | head -n 1 | xargs)"
    FW_DIR="$PROJECT_DIR/bin/targets/ipq53xx/ipq53xx_32/"
    FW_NAME="fw_410h.img"
	TARGET_DIR="$SOURCE_DIR/build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi/"
    ;;
609|13_0|13_1)
    DOCKER_CONTAINER="ksc-609h"
    # FW_PATH="$(ls -t $PROJECT_DIR/bin/targets/ipq53xx/ipq53xx_32 | grep DVW-732X | grep .img | head -n 1 | xargs)"
    FW_DIR="$PROJECT_DIR/bin/targets/ipq53xx/ipq53xx_32/"
    FW_NAME="fw_609h.img"
	TARGET_DIR="$SOURCE_DIR/build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi"
    ;;
501)
    DOCKER_CONTAINER="ksc-501h"
    # FW_PATH="$(ls -t $PROJECT_DIR/images | grep DV03-501H | grep .img | head -n 1 | xargs)"
    FW_DIR="$PROJECT_DIR/images/"
    FW_NAME="fw_012hr.img"
    ;;
704)
    DOCKER_CONTAINER="ksc_704"
    # FW_PATH="$PROJECT_DIR/bin/targets/ipq95xx/ipq95xx_32/$(ls -t $PROJECT_DIR/bin/targets/ipq95xx/ipq95xx_32/ | grep DVW-704X | grep 4k | grep .img | head -n 1 | xargs)"
    FW_DIR="$PROJECT_DIR/bin/targets/ipq95xx/ipq95xx_32/"
    FW_NAME="fw_704.img"
	TARGET_DIR="$SOURCE_DIR/build_dir/target-arm"
    ;;
usen)
    #not tested
    ;;
turbo)
    #need fix
    # DOCKER_CONTAINER="davo_sdx_test_dock"
    # FW_PATH="$(ls -t $PROJECT_DIR/turbox/output/ | grep .zip | head -n 1 | xargs)"
    # FW_PATH="$(ls -t $PROJECT_DIR/turbox/output/ | grep DVF-754 | grep FlatBuild*.zip | grep ext4 | grep .zip | head -n 1 | xargs)"
    FW_DIR="$PROJECT_DIR/turbox/output/"
#    FW_NAME="update_full_ext4.zip"
    FW_NAME=""
    FW_PRIORITY_SEARCH="full"
	SOURCE_DIR="$PROJECT_DIR/Pinnacles_apps/apps_proc/owrt"
	TARGET_DIR="$SOURCE_DIR/build_dir/target-aarch64_cortex-a53_musl"
    ;;
*)
    DOCKER_CONTAINER="'$USER'-'$NOW_PROJECT'h"
    # FW_PATH="$(ls -t $PROJECT_DIR/bin/ipq/ | grep DVW-'$NOW_PROJECT'X | grep .img | head -n 1 | xargs)"
    FW_DIR="$PROJECT_DIR/bin/ipq/"
    FW_NAME="fw_'$NOW_PROJECT'h.img"
    TARGET_DIR=$SOURCE_DIR/build_dir/target-arm
    ;;
esac
# 성능 최적화: DOCKER_CONTAINER가 설정된 후에 DOCKER_EXEC 설정
export DOCKER_EXEC="docker exec $DOCKER_CONTAINER"
export DEFAULT_EDITOR=vim

#Thundercomm TurboSDK
export PF_OTA=true

# (민감 정보는 위의 ~/.private/*.sh 에서 이미 로드됨)
