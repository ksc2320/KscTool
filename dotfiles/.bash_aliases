#!/bin/bash

#프로젝트별 단축키

# 전 프로젝트
alias 'davo'='cd $SOURCE_DIR/davo'
alias 'files'='cd $SOURCE_DIR/davo/files'
alias 'sbin'='cd $SOURCE_DIR/davo/files/usr/sbin'
alias 'files_kt'='cd $SOURCE_DIR/davo/files_kt'
alias 'davowebsrc'='cd $SOURCE_DIR/davo/feeds/webui/davo_webserver/files/web_src'
alias 'ktwebsrc'='cd $SOURCE_DIR/davo/feeds/webui/kt_web/files/web_src'
alias 'ktwebsrclight'='cd $SOURCE_DIR/davo/feeds/webui/kt_web_light/files/web_src'

alias 'views'='cd $SOURCE_DIR/davo/feeds/webui/kt_web_light/files/web_src/views'
alias 'wifi7'='cd $SOURCE_DIR/davo/feeds/webui/kt_web_light/files/web_src/wifi7'

alias 'package'='cd $SOURCE_DIR/package'

alias 'target'='cd $TARGET_DIR'
alias 'dvpkg'='cd $TARGET_DIR/dv_pkg'

## dv_pkg 주요 패키지
alias 'dvbox'='cd $TARGET_DIR/dv_pkg/dvbox'
alias 'dvcfg'='cd $TARGET_DIR/dv_pkg/dvcfg'
alias 'dvsnmp'='cd $TARGET_DIR/dv_pkg/dvsnmp'
alias 'dvstats'='cd $TARGET_DIR/dv_pkg/dv_statistics'
alias 'dvstamon'='cd $TARGET_DIR/dv_pkg/dv_sta_mon'
alias 'ktgsp'='cd $TARGET_DIR/dv_pkg/ktgsp'
alias 'ktqos'='cd $TARGET_DIR/dv_pkg/ktqos'
alias 'laborer'='cd $TARGET_DIR/dv_pkg/laborer'
alias 'cwmpcli'='cd $TARGET_DIR/dv_pkg/cwmp_cli'
alias 'ktwebsv'='cd $TARGET_DIR/dv_pkg/kt_webserver'

## dvmgmt + 하위 모듈
alias 'dvmgmt'='cd $TARGET_DIR/dv_pkg/dvmgmt'
alias 'cmdtbl'='cd $TARGET_DIR/dv_pkg/dvmgmt/cmdtbl'
alias 'dvnet'='cd $TARGET_DIR/dv_pkg/dvmgmt/network'
alias 'dvmain'='cd $TARGET_DIR/dv_pkg/dvmgmt/main'
alias 'dvwrdrt'='cd $TARGET_DIR/dv_pkg/dvmgmt/wrdrt'
alias 'dvap'='cd $TARGET_DIR/dv_pkg/dvmgmt/ap'
alias 'dvscan'='cd $TARGET_DIR/dv_pkg/dvmgmt/scan'
alias 'dvswitch'='cd $TARGET_DIR/dv_pkg/dvmgmt/switch'
alias 'dvdiag'='cd $TARGET_DIR/dv_pkg/dvmgmt/diagnostics'
alias 'dvupgrade'='cd $TARGET_DIR/dv_pkg/dvmgmt/upgrade'
alias 'dvmstats'='cd $TARGET_DIR/dv_pkg/dvmgmt/statistics'

## kernel + 하위 모듈
alias 'kernel'='cd $TARGET_DIR/dv_pkg/kernel'
alias 'dvkpoll'='cd $TARGET_DIR/dv_pkg/kernel/dvkpoll'
alias 'dualnat'='cd $TARGET_DIR/dv_pkg/kernel/dualnat'
alias 'dyngsp'='cd $TARGET_DIR/dv_pkg/kernel/dvdyngsp'
alias 'passthru'='cd $TARGET_DIR/dv_pkg/kernel/passthru'
alias 'dvflag'='cd $TARGET_DIR/dv_pkg/kernel/dvflag'
alias 'dvbrdio'='cd $TARGET_DIR/dv_pkg/kernel/dvbrdio'
alias 'dvktrace'='cd $TARGET_DIR/dv_pkg/kernel/dvktrace'
alias 'dvosutil'='cd $TARGET_DIR/dv_pkg/kernel/dvosutil'
alias 'nettweak'='cd $TARGET_DIR/dv_pkg/kernel/nettweak'
alias 'dvfwinfo'='cd $TARGET_DIR/dv_pkg/kernel/dvfwinfo'
alias 'dvpwdet'='cd $TARGET_DIR/dv_pkg/kernel/dvpwdet'
alias 'dvusb'='cd $TARGET_DIR/dv_pkg/kernel/dvusb'

alias 'netifd'='cd $TARGET_DIR/netifd*'
alias 'dnsmasq'='cd $TARGET_DIR/dnsmasq*/dnsmasq*/src'
alias 'busy'='cd $TARGET_DIR/busybox*'
alias 'dnsd'='cd $TARGET_DIR/busybox*/busybox*/networking/'
alias 'udhcp'='cd $TARGET_DIR/busybox*/*/networking/udhcp'
alias 'odhcp'='cd $TARGET_DIR/odhcp6c-*'

alias 'ipv4'='cd $TARGET_DIR/linux*/linux*/net/ipv4'

alias 'rtl8366'='cd $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt/src/kernel-5.15/kernel_platform/msm-kernel/drivers/net/ethernet/stmicro/stmmac/rtl8366u'
alias 'rtl'='rtl8366'
if [[ "$NOW_PROJECT" == "turbo" ]]; then

    alias 'dyngsp.pdf'='open $HOME/문서/Document/thundercomm/DVF-754_HW_description_0V2.pdf'
    alias 'hwd'='open $HOME/문서/Document/thundercomm/DVF-754_HW_description_0V2.pdf'

    alias 'wps'='cd $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt/owrt-qti-ipq-prop/qca/net/qca-hostap/files'
    alias 'cmdlist'='vim $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt/davo/feeds/webui/davo_web/files/web_src/cmd_list.json'
    alias 'web'='cd $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt/build_dir/target-aarch64_cortex-a53_musl/dv_pkg/davo_webserver'
    alias 'dts'='cd $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt/src/kernel-5.15/kernel_platform/qcom/proprietary/devicetree/qcom'
    alias 'driver'='cd $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt/src/kernel-5.15/kernel_platform/msm-kernel/drivers'
    alias 'serial'='cd $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt/src/kernel-5.15/kernel_platform/msm-kernel/drivers/tty/serial'
    alias 'portlink.ejs'='vi $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt/davo/feeds/webui/davo_web/files/web_src/views/setting/switch/port_link.ejs'
    alias 'portlink'='echo $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt/davo/feeds/webui/davo_web/files/web_src/views/setting/switch/port_link.ejs'
    alias 'nms'='cd $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt/build_dir/target-aarch64_cortex-a53_musl/dv_pkg/dv_test_kt_nms_cli'

elif [[ "$NOW_PROJECT" == "609" || "$NOW_PROJECT" == "13_0" || "$NOW_PROJECT" == "13_1" ]]; then
	alias 'dts'='cd $TARGET_DIR/linux-ipq53xx_ipq53xx_32/linux-6.6.88/arch/arm64/boot/dts/qcom'
    alias 'hostapd'='cd $TARGET_DIR/qca-hostap-qca-hapd-supp-full/qca-hostap-g/hostapd'
    alias 'qca'='cd $TARGET_DIR/linux-ipq53xx_ipq53xx_32/qca-ssdk-nohnat/qca-ssdk-g/src/adpt'
    alias 'adpt'='cd $TARGET_DIR/linux-ipq53xx_ipq53xx_32/qca-ssdk-nohnat/qca-ssdk-g/src/adpt'
    alias 'hostap'='cd $TARGET_DIR/qca-hostap-qca-hapd-supp-full/qca-hostap-g/src'

elif [[ "$NOW_PROJECT" == "12_4" || "$NOW_PROJECT" == "12_5" ]]; then

    alias 'qca'='cd $TARGET_DIR/linux-ipq53xx_ipq53xx_32/qca-ssdk-nohnat/qca-ssdk-g'

# elif [[ "$NOW_PROJECT" == "012" ]]; then

fi

#전역 경로 ( 하드 세팅 )
alias '012dualnat'='cd $(get_proj_dir 012)/build_dir/target-aarch64_cortex-a53_musl-1.1.16/dv_pkg/kernel/dualnat'
alias '012dnsmasq'='cd $(get_proj_dir 012)/build_dir/target-aarch64_cortex-a53_musl-1.1.16/dnsmasq-dhcpv6/dnsmasq-2.79/src'
alias '012target'='cd $(get_proj_dir 012)/build_dir/target-aarch64_cortex-a53_musl-1.1.16'
alias '012dvmgmt'='cd $(get_proj_dir 012)/build_dir/target-aarch64_cortex-a53_musl-1.1.16/dv_pkg/dvmgmt'
alias '012udhcp'='cd $(get_proj_dir 012)/build_dir/target-aarch64_cortex-a53_musl-1.1.16/busybox-1.28.3/networking/udhcp'
alias '012hostap'='cd $(get_proj_dir 012)/build_dir/target-aarch64_cortex-a53_musl-1.1.16/qca-hostap-supplicant-default/qca-hostap-g/src'

alias '13.0dualnat'='cd $(get_proj_dir 13_0)/build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi/dv_pkg/kernel/dualnat'
alias '13.0dnsmasq'='cd $(get_proj_dir 13_0)/build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi/dnsmasq-dhcpv6/dnsmasq-2.90/src'
alias '13.0target'='cd $(get_proj_dir 13_0)/build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi'
alias '13.0dvmgmt'='cd $(get_proj_dir 13_0)/build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi/dv_pkg/dvmgmt'
alias '13.0udhcp'='cd $(get_proj_dir 13_0)/build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi/busybox-default/busybox-1.36.1/networking/udhcp'
alias '13.0hostap'='cd $(get_proj_dir 13_0)/build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi/qca-hostap-qca-hapd-supp-full/qca-hostap-g/src'

#일시적 프로젝트 문서
alias '규격서'='standard_management'
alias '규격'='standard_management_open_file'
alias 'doc'='cd $HOME/문서/Document/.'
alias '망규격'="open $HOME/문서/Document/'250731_홈AP 규격 배포'/'KT 통합 단말 망접속 규격 그룹 WiFi 홈 AP 기능 규격 V2.1.0.pdf'"
alias 'kt규격'="cd $HOME/문서/Document/'250731_홈AP 규격 배포'"
alias '웹규격'="open $HOME/문서/Document/'250731_홈AP 규격 배포'/'KT 홈AP Web Manager UI 가이드 V3.0.3.pdf'"
alias '신규격'="open $HOME/문서/Document/'홈 AP 규격 배포(251205)'/'KT 통합 단말 망접속 규격 그룹 WiFi 홈 AP 기능 규격 V2.1.1.pdf'"
alias '최신망규격'="open $HOME/문서/Document/'홈 AP 규격 배포(251205)'/'KT 통합 단말 망접속 규격 그룹 WiFi 홈 AP 기능 규격 V2.1.1.pdf'"
alias '단말관리규격'="open $HOME/문서/Document/'250731_홈AP 규격 배포'/'KT 단말관리 홈허브(AP) 단말관리 규격 V1.3.9.pdf'"
alias '공통기능규격'="open $HOME/문서/Document/'250731_홈AP 규격 배포'/'KT 단말관리 TR-069 공통 기능 규격 V1.2.7.pdf'"
alias '로그규격'="open $HOME/문서/Document/'250731_홈AP 규격 배포'/'KT 단말관리 로그 공통 기능 규격 V1.3.2.pdf'"

#디렉토리
alias fw='cd "$FW_DIR"'
alias HD='cd $HOME/hdd'
alias hdd='cd $HOME/hdd'
alias '~'='cd ~/'
alias 'here'='pwd'
alias tftp='cd $TFTP_PATH'
alias proj='cd "$PROJECT_DIR"'
alias npj='cd "$PROJECT_DIR"'
alias now='cd "$PROJECT_DIR"'
alias src='cd "$SOURCE_DIR"'
alias hpj='cd $HOME/hdd/proj'
alias pj='cd $HOME/proj'
alias '..'='cd ..'
alias '...'='cd ../..'
alias '....'='cd ../../..'

# 4단 이상: up N 사용 (예: up 5 → cd ../../../../../)
up() { local d=""; for ((i=0; i<${1:-1}; i++)); do d="../$d"; done; cd "$d"; }

alias pj25='cd $HOME/memo/project_25'
alias pj26='cd $HOME/memo/project_26'
alias cmd='cd $HOME/memo/claude_md'

alias tr069win='cd $HOME/smb/TR069'
alias tr069='cd $HOME/smb/tr069-acs-v1.4.3'
alias tr069start='$HOME/smb/tr069-acs-v1.4.3/linux-start.sh'

alias '메모'='cd ~/memo'
alias 'memo'='cd ~/memo'
alias '문서'='cd ~/문서'
alias '카카오'='cd $HOME/문서/카카오톡 받은 파일'
alias 'kakao'='cd $HOME/문서/카카오톡 받은 파일'

alias '스크린샷'='cd $HOME/문서/screenshot'
alias '스샷'='cd $HOME/문서/screenshot'
alias 'ㅅㅅ'='스샷'
alias '보관'='cd $HOME/사진/스크린샷/보관'

#프로젝트
alias workspace='cd "$WORKSPACE_DIR"'
alias ws='workspace'
alias 704='cd $(get_proj_dir 704)'
alias 501='cd $(get_proj_dir 501)'
alias 13.0='cd $(get_proj_dir 13_0)'
alias 12.5='cd $(get_proj_dir 12_5)'
alias 12.4='cd $(get_proj_dir 12_4)'
alias 609='cd $(get_proj_dir 609)'
alias 609test='cd $(get_proj_dir 609_test)'
alias 13.1='cd $(get_proj_dir 13_1)'
alias 732='cd $(get_proj_dir 609)'
alias 012='cd $(get_proj_dir 012)'
alias 901='cd $(get_proj_dir 901)'
alias 604='cd $HOME/hdd/proj/QCA_SDK_11.5.CSU1_ent'
alias 614='cd $HOME/hdd/proj/QCA_SDK_11.5.CSU1_ent'
alias 624='cd $HOME/hdd/proj/QCA_SDK_11.5.CSU1_ent'
alias 602='cd $HOME/hdd/proj/QCA_SDK_11.5.CSU1_ent'
alias 612='cd $HOME/hdd/proj/QCA_SDK_11.5.CSU1_ent'
alias 622='cd $HOME/hdd/proj/QCA_SDK_11.5.CSU1_ent'
alias usen='cd $(get_proj_dir usen)'


alias owrt='cd $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt'
alias turbo='cd $(get_proj_dir turbo)/'
alias tb='turbo'
alias 754='turbo'
alias tbdts='cd $(get_proj_dir turbo)/Pinnacles_apps/apps_proc/owrt/src/kernel-5.15/kernel_platform/qcom/proprietary/devicetree'

#배쉬
alias sb='source ~/.bashrc'
alias sbal='source ~/.bash_aliases'
alias sbfu='source ~/.bash_functions'
alias bashbackup='cp -a ~/.bash* ~/hdd/bash_backup/.'
alias vimbackup='cp -a ~/.vimrc ~/hdd/bash_backup/.'

#tags
alias maketags='~/proj/ksc_tool/make_tag.sh'
alias genindex='~/KscTool/scripts/tools/gen_index.sh'
alias genindex-tags='~/KscTool/scripts/tools/gen_index.sh -s'
alias genindex-bear='~/KscTool/scripts/tools/gen_index.sh -b'

#tools
#alias fn='find -name "$1"'
alias fn='function FIND() { find -name "$1";};FIND'
alias wis='wireshark_exec'
alias wireshark='wireshark_exec'
#alias logic='logic'

#gemini
alias gem="gemini"

#codevs
alias cdf="code --diff"
alias csdf="csdf"

#cursor
alias cs="cursor"
alias csclangd='vi $SOURCE_DIR/.clangd'

alias codeext='code --list-extensions > vscode_ext.txt'
alias cursorext='cursor --list-extensions > cursor_ext.txt'

alias svnt='svn diff --diff-cmd diff' # for cursor

#antigravity
alias anti="antigravity"

#build
alias log='open_latest_build_hlos_log' #tb

#svn
alias svnignore='svn status | grep "^?" | awk "{print $2}" > asdf.txt'
alias svnsort='grep "^?" asdf.txt | awk "{print $2}" | xargs -n 1 basename | sort | uniq > asdf2.txt'
alias svnconfig='vi ~/.subversion/config'
#alias sst='svn status | grep "^M"'
alias sde='dv_svn_diff_export'
alias sdft='sdft'
alias sdfr="svn diff -r "
alias sdfmr="svn diff --diff-cmd meld -r "
alias svl="svn log | more"
#svn diff -r 리비전:리비전 파일명
alias rv='function _rv() { svn log -r "$1" -v; }; _rv'
alias svr="svn revert"
alias svrr="svn revert -R"
alias ssq="svn status -q"

#ksc_tools
##svn
alias scs="$HOME/KscTool/svn/svn_commit.sh"
##ftd (AP 파일 전송)
alias fwd='_ftd_main'
alias fwdc='fwd cmd'
# ap 함수는 file_to_dev.sh _ftd_register() 에서 정의 (preset 라우팅 포함)
##cpbak (SVN/Git 수정 파일 백업)
alias cpbak='_cpbak_main'
##build — 비활성화 (동작 안함)
#alias bep="$HOME/KscTool/build/build_error_parse.sh"
#alias rbc="$HOME/KscTool/build/rebuild_changed.sh"
##tools
alias obs="$HOME/KscTool/tools/obs.sh"
alias ucisnap="$HOME/KscTool/tools/ucisnap.sh"
alias spec="$HOME/KscTool/tools/spec.sh"
##watch (AP 로그 감시 / SSH 연결) — 비활성화 (동작 안함)
#alias dvwatch="$HOME/KscTool/watch/dvwatch.sh"
#alias dvcon="$HOME/KscTool/watch/dvcon.sh"

#http server
alias sv='cd ~/tftpboot'
alias startserver='python3 -m http.server --directory /tftpboot 8080'
alias ct='cptftp'

alias 'dynrecv'='nc -u -l -p 7557'

#공유폴더
alias smb='cd $HOME/smb'
alias samba='smb'


# alias scr
alias scr=scr

# alias scd
alias scd=scd

# vim diff
alias vd=vimdiff

# fzf Aliases
alias ff='fzf_connect_vim Curr_Dir'
alias ffs='fzf_connect_vim Source_Dir'
alias ffa='fzf_connect_vim All_Dir'
alias ffc='fzf_connect_codevs Curr_Dir'
alias fcd='fzf_connect_cd'
alias fl='show_fzf_search_log'

# clean vim temp
alias cvt=clean_vim_temp

# alias rgc
alias rgc='rg -n -i --type-add "noext:!*.*" --type noext --glob="*.{c,h,txt,md,sh}" --color=auto'
alias rgch='rg -n -i --glob="*.{c,h}" --color=auto'
alias grnch='grep -nri --include=*.[ch] --color=auto'
alias rgall='rg -uu --hidden'
alias fdall='fd -uu --hidden'

# alias ls
alias lsmd='ls *.md'
alias lsc='ls *.c'
alias lsh='ls *.h'
alias llc='ll *.c'
alias llh='ll *.h'
alias lsch='ls *.c *.h'
alias llch='ll *.c *.h'

alias pwdc='pwd | tee >(xclip -selection clipboard)'



# 예약 작업 뷰어
crons() {
  local RESET='\033[0m' BOLD='\033[1m' CYAN='\033[36m' YELLOW='\033[33m' GREEN='\033[32m' DIM='\033[2m'
  local DAY_NAMES=("일" "월" "화" "수" "목" "금" "토")

  echo -e "\n${BOLD}${CYAN}══ 예약 작업 (crontab) ══${RESET}"

  local cron_entries
  cron_entries=$(crontab -l 2>/dev/null | awk '!/^\s*#/ && !/^\s*$/ && !/^[A-Z_][A-Z_0-9]*=/')

  if [ -z "$cron_entries" ]; then
    echo -e "  ${DIM}(등록된 cron 없음)${RESET}"
  else
    while IFS= read -r line; do
      local min hour dom mon dow cmd
      read -r min hour dom mon dow cmd <<< "$line"

      local dow_label=""
      if [ "$dow" = "*" ]; then
        dow_label="매일"
      else
        dow_label="매주 ${DAY_NAMES[$(( dow % 7 ))]}요일"
      fi

      local time_label
      if [ "$min" = "*" ] && [ "$hour" = "*" ]; then
        time_label="매분"
      elif [[ "$hour" == */* ]]; then
        time_label="매 ${hour#*/}시간 (분:${min})"
      elif [[ "$min" == */* ]]; then
        time_label="매 ${min#*/}분"
      elif [[ "$hour" == *,* ]]; then
        local IFS=','
        time_label=""
        for h in $hour; do time_label+=$(printf "%02d:%02d " "$h" "$min"); done
        time_label="${time_label% }"
      else
        time_label=$(printf "%02d:%02d" "$hour" "$min")
      fi

      local short_cmd
      short_cmd=$(basename "${cmd%% *}")

      echo -e "  ${GREEN}●${RESET} ${BOLD}${short_cmd}${RESET}"
      echo -e "    ${YELLOW}${dow_label} ${time_label}${RESET}  ${DIM}${cmd}${RESET}"
    done <<< "$cron_entries"
  fi

  local timers
  timers=$(systemctl --user list-timers --no-legend 2>/dev/null)
  if [ -n "$timers" ]; then
    echo -e "\n${BOLD}${CYAN}══ systemd timers (user) ══${RESET}"
    while IFS= read -r line; do
      echo -e "  ${GREEN}●${RESET} $line"
    done <<< "$timers"
  fi

  echo ""
}
