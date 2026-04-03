#!/bin/bash
# ================================================================= #
#                           CUSTOM SCRIPT                           #
# ----------------------------------------------------------------- #
#                                                                   #
# * This file is shell script bundle for 'Gnet System'				#
#                                                                   #
# ----------------------------------------------------------------- #
#                                                                   #
# 1. fzf Utility													#
#       - Search utility function using fzf							#
#                                                                   #
# 2. Mk Tool														#
#       - A set of shell script commands for convenience			#
#                                                                   #
# ----------------------------------------------------------------- #
#                                                                   #
# 1. Essential Package												#
#       - fzf														#
#       - ripgrep													#
#                                                                   #
# 2. Recommended Package											#
#       - duf														#
#       - neofetch													#
#                                                                   #
# ----------------------------------------------------------------- #
#                                                                   #
# > Install 'fzf'													#
#   git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf	#
#   ~/.fzf/install													#
#                                                                   #
# ----------------------------------------------------------------- #
#											Author : So Byung Jun	#
# ================================================================= #

# Fix Carriage Return Error when Window <-> Linux
# 성능 최적화: 파일이 이미 수정되었는지 확인 후 실행
if [ -f ~/.bash_aliases ] && grep -q $'\r' ~/.bash_aliases 2>/dev/null; then
    sed -i -e 's/\r$//' ~/.bash_aliases
fi
if [ -f ~/.bash_completion ] && grep -q $'\r' ~/.bash_completion 2>/dev/null; then
    sed -i -e 's/\r$//' ~/.bash_completion
fi

# Global Define : Color
cRed='\e[31m'
cBlue='\e[34m'
cGreen='\e[32m'
cYellow='\e[33m'
cWhite='\e[37m'
cSky='\e[36m'
cDim='\e[2m'
cBold='\e[1m'
cLine='\e[4m'
cReset='\e[0m'

# Global Define : Prefix
RUN="${cBold}[ ${cGreen}RUN${cReset} ${cBold}]${cReset}"
SET="${cBold}[ ${cBlue}SET${cReset} ${cBold}]${cReset}"
ERROR="${cBold}[ ${cRed}ERROR${cReset} ${cBold}]${cReset}"
NOTICE="${cBold}[ ${cYellow}NOTICE${cReset} ${cBold}]${cReset}"
DONE="${cBold}[ ${cGreen}DONE${cReset} ${cBold}]${cReset}"

function HEAD() {
	echo -e -n "${cBold}[ $1 ]${cReset}"
}

function check_installed_package() {
	$1 --version &>/dev/null
}

function show_how_install_fzf() {
	echo -e "${NOTICE} Sorry. that function need ${cGreen}fzf${cReset} Package"
	echo -e "  ================================================================="
	echo -e "  - git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf"
	echo -e "  - ~/.fzf/install"
	echo -e "  ================================================================="
}

function get_prompt_color() {
	local cur_path=$(pwd | sed "s#${HOME}##g")
	local NOW_COLOR="${cGreen}" # 일반 경로는 초록색

	test x"${cur_path}" == x && NOW_COLOR="${cSky}" # 기본 홈 디렉토리 이름 설정
	echo "$NOW_COLOR"
}

function shorten_path() {
	local cur_path=$(pwd | sed "s#${HOME}##g")
	#	test x"${cur_path}" == x && cur_path="${cSky}HOME_${USER_NAME}"
	test x"${cur_path}" == x && cur_path="HOME_${NOW_PROJECT}" # 기본 홈 디렉토리 이름 설정
	echo "$cur_path"
}

function get_fw_install_dir() {
	#나중에 수정하자
	# $1 : project name ( ex : a3, v8 )
	if [ "$1" == "" ]; then
		local project_name=$(echo -e ${NOW_PROJECT} | tr "[:upper:]" "[:lower:]")
		if [ "${project_name}" == "a3" ]; then
			echo -e -n "${HOME}/tftpboot/janus_a3/fw_install"
		else
			echo -e -n "${HOME}/tftpboot/gnet_${project_name}/fw_install"
		fi
	elif [ "$1" == "a3" ]; then
		echo -e -n "${HOME}/tftpboot/janus_a3/fw_install"
	else
		echo -e -n "${HOME}/tftpboot/gnet_$1/fw_install"
	fi
}

function get_install_dir() {
	# 나중에 수정하자

	#FW_PATH="./images/$(ls -t ./images/ | grep DV03-501H | grep .img | head -n 1) "
	#cp $FW_PATH /srv/tftp/fw_012hr.img
	#cp ./images/img.tar /srv/tftp/mg.tar
	#echo "[!] finished copy [${FW_PATH}] -> /srv/tftp/fw_012hr.img]"
	#echo "[!] finished copy [./images/img.tar] -> /srv/tftp/img.tar]"
	# $1 : project name ( ex : a3, v8 )
	if [ "$1" == "" ]; then
		local project_name=$(echo -e ${NOW_PROJECT} | tr "[:upper:]" "[:lower:]")
		if [ "${project_name}" == "a3" ]; then
			echo -e -n "${HOME}/install/janus_a3"
		else
			echo -e -n "${HOME}/install/gnet_${project_name}"
		fi
	elif [ "$1" == "a3" ]; then
		echo -e -n "${HOME}/install/janus_a3"
	else
		echo -e -n "${HOME}/install/gnet_$1"
	fi
}

# ================================================================= #
# 		                     fzf Utility	                  		#
# ================================================================= #

# base fzf setting
FZF_SETTING="	--height 50%                        \
                --border                            \
                --extended                          \
                --ansi                              \
                --reverse                           \
                --cycle                             \
                --multi                             \
		        --bind=ctrl-d:preview-page-down     \
                --bind=ctrl-u:preview-page-up       \
                --bind=ctrl-space:preview-page-down \
                --bind=ctrl-z:preview-page-up       \
                --bind=ctrl-/:toggle-preview"

# fzf Functions - ff, ffa, ffs
function fzf_connect_vim() {
	local pre_dir=$(pwd)
	local search_value="${cYellow}None Search Value${cReset}"
	local search_time=$(date +%H:%M:%S)
	local search_list=()

	echo -n -e "${RUN} fzf-vim Utility By ${cYellow}$1${cReset} "

	# ffs : search current project source path
	if [ "$1" == "Source_Dir" ]; then
		cd ~/blackbox/source

	# ffa : search home path
	elif [ "$1" == "All_Dir" ]; then
		cd ~/

	# ff : search current path
	else
		cd $(pwd)
	fi

	echo -e "( ${cLine}$(pwd)${cReset} )"

	# check grep word
	if [ "$#" -eq 2 ]; then
		search_value=$2
		echo -e "${SET} grep -> ${cLine}$2${cReset}"

		# rg -i --files-with-matches --no-messages : find word-matcthes files list

		_file=$(rg -i --files-with-matches --no-messages "$2" |
			fzf ${FZF_SETTING} \
				--preview "cat -n {} | rg -i --color always \"$2\"" \
				--header "[ Select the file you want to edit ]")
	else
		_file=$(fzf ${FZF_SETTING} \
			--preview "cat -n {}" \
			--header "[ Select the file you want to edit ]")
	fi

	# write log
	#	search_list+=(${_file})
	#	echo -e "[ ${cGreen}${search_value}${cReset} ] _${search_time}" >> ${HOME}/fzf_search_log.txt
	#	for i in ${!search_list[@]}
	#	do
	#		echo -e "-" ${search_list[i]} >> ${HOME}/fzf_search_log.txt
	#	done
	#	echo -e "" >> ${HOME}/fzf_search_log.txt

	# open vim
	if [ ! "${_file}" == "" ]; then
		if [ "$#" -eq 2 ]; then
			vim -O -c "/$2" ${_file}
		else
			vim -O ${_file}
		fi
		echo -e "${NOTICE} If you want to see the search history, enter the '${cYellow}fl${cReset}' command."
	fi

	cd ${pre_dir}
}

function fzf_connect_codevs() {
	local pre_dir=$(pwd)
	local search_value="${cYellow}None Search Value${cReset}"
	local search_time=$(date +%H:%M:%S)
	local search_list=()

	echo -n -e "${RUN} fzf-codevs Utility By ${cYellow}$1${cReset} "

	# ffs : search current project source path
	if [ "$1" == "Source_Dir" ]; then
		cd ~/blackbox/source

	# ffa : search home path
	elif [ "$1" == "All_Dir" ]; then
		cd ~/

	# ff : search current path
	else
		cd $(pwd)
	fi

	echo -e "( ${cLine}$(pwd)${cReset} )"

	# check grep word
	if [ "$#" -eq 2 ]; then
		search_value=$2
		echo -e "${SET} grep -> ${cLine}$2${cReset}"

		# rg -i --files-with-matches --no-messages : find word-matcthes files list

		_file=$(rg -i --files-with-matches --no-messages "$2" |
			fzf ${FZF_SETTING} \
				--preview "cat -n {} | rg -i --color always \"$2\"" \
				--header "[ Select the file you want to edit ]")
	else
		_file=$(fzf ${FZF_SETTING} \
			--preview "cat -n {}" \
			--header "[ Select the file you want to edit ]")
	fi

	# write log
	search_list+=(${_file})
	echo -e "[ ${cGreen}${search_value}${cReset} ] _${search_time}" >>${HOME}/fzf_search_log.txt
	for i in ${!search_list[@]}; do
		echo -e "-" ${search_list[i]} >>${HOME}/fzf_search_log.txt
	done
	echo -e "" >>${HOME}/fzf_search_log.txt

	# open codevs
	if [ ! "${_file}" == "" ]; then
		if [ "$#" -eq 2 ]; then
			code -O -c "/$2" ${_file}
		else
			code -O ${_file}
		fi
		echo -e "${NOTICE} If you want to see the search history, enter the '${cYellow}fl${cReset}' command."
	fi

	cd ${pre_dir}
}

# fcd
function fzf_connect_cd() {
	local pre_dir=$(pwd)

	cd ~/
	echo -e "${RUN} fzf-cd Utility in ${cLine}$(pwd)${cReset}"

	if [ "$#" -eq 1 ]; then
		echo -e "${SET} grep -> ${cLine}$1${cReset}"
		_file=$(rg -i --files-with-matches --no-messages "$1" |
			fzf ${FZF_SETTING} \
				--preview "cat -n {} | rg -i --color always \"$1\"" \
				--header "[ Select Dir/File you want to move Dir ]")
	else
		_file=$(fzf ${FZF_SETTING} \
			--preview "cat -n {}" \
			--header "[ Select Dir/File you want to move Dir ]")
	fi

	if [ ! "${_file}" == "" ]; then
		cd $(dirname ${_file})
	else
		cd ${pre_dir}
	fi
}

# fl
function show_fzf_search_log {
	local search_count="3"

	if [ $# -eq 1 ]; then
		search_count=$1
	fi

	echo -e "\n=== ${cBold}Fzf Search List : Last ${search_count} Log ${cReset}========================"

	local CUT_LINE=$(cat ~/fzf_search_log.txt | grep -n "\[ " | tail -n ${search_count} | head -n 1 | awk -F ':' '{print $1}')
	local END_LINE=$(wc -l ~/fzf_search_log.txt | awk -F ' ' '{print $1}')
	local START_LINE=$((${END_LINE} - ${CUT_LINE} + 1))

	echo
	cat ~/fzf_search_log.txt | tail -n ${START_LINE}
	echo -e "=========================================================\n"
}

# ================================================================= #
#                              DV Tool                              #
# ================================================================= #

# Option
AUTO_DIR_COPY=N
AUTO_NFS_DETECT=Y
AUTO_BACKUP=N
CHANGE_PROMPT=Y
IMPROVED_AUTO_COMPLETE=N
FASTER_MK_APP=Y

MK_VERSION=1.0.0
LAST_UPDATE=2024-12-13
#공유시 삭제 — 실제 값은 ~/.secrets에서 로드됨
# ROOT_PW는 ~/.secrets에서 설정

PROJECT_LIST=("609" "13_0" "13_1" "12_5" "12_4" "901" "012" "501" "704" "usen" "turbo")
# ============== svn diff macro ============== #
DV_SVN_DIFF_TOOL="meld"
# ============== dv diff macro ============== #
DV_DIFF_TOOL="meld"
DV_DIFF_PROJ_1="609"
DV_DIFF_PROJ_2="410o"

# ============== Extensions ============== #
EXTENSIONS_DIR=${HOME}/MkTool/Extensions

# SearchTree Ext
EXT_SEARCH_TREE="${EXTENSIONS_DIR}/search_tree.py"
SEARCH_TREE_LOG="openDirName.tree"
# ============== Extensions ============== #

# .bash_profile 또는 .bashrc 파일
if [ -t 0 ]; then
	# Only if the shell is interactive
	if [ "${IMPROVED_AUTO_COMPLETE}" == "Y" ]; then
		bind 'TAB:menu-complete'
		bind '"\e\e":unix-word-rubout'
		bind "set show-all-if-ambiguous on"
		bind "set completion-ignore-case on"
		bind "set menu-complete-display-prefix on"
		bind "set colored-completion-prefix on"
		bind "set colored-stats on"
	else
		bind 'TAB:complete'
		bind '"\e\e":complete'
		bind "set show-all-if-ambiguous off"
		bind "set completion-ignore-case off"
		bind "set menu-complete-display-prefix off"
		bind "set colored-completion-prefix off"
		bind "set colored-stats off"
	fi
fi

# Line number of projects currently active in bashrc
function get_line_project_name() {
	if [ $# -eq 1 ]; then
		cat ~/.bashrc | grep -n NOW_PROJECT | grep $1$ | awk -F ':' '{print $1}'
	else
		cat ~/.bashrc | grep -n ^NOW_PROJECT | grep -v "#" | awk -F ':' '{print $1}'
	fi
}

# ex) NOW_PROJECT=S3
function get_value_project_name() {
	if [ $# -eq 1 ]; then
		cat ~/.bashrc | grep -n NOW_PROJECT | grep $1$ | awk -F '#' '{print $2}'
	else
		cat ~/.bashrc | grep -n ^NOW_PROJECT | grep -v "#" | awk -F ':' '{print $2}'
	fi
}

# ex) s3
function project_version_name() {
	cat ~/.bashrc | grep -n ^NOW_PROJECT | grep -v "#" | awk -F '=' '{print $2}' | tr "[:upper:]" "[:lower:]"
}

function get_line_option() {
	cat ~/.bash_aliases | grep -na ^$1 | awk -F ':' '{print $1}'
}

function get_value_option() {
	cat ~/.bash_aliases | grep -na ^$1 | awk -F '=' '{print $2}'
}

function get_backup_value_option() {
	cat ~/.bash_aliases_backUp | grep -na ^$1 | awk -F '=' '{print $2}'
}

function version_change_to_upload() {
	local VERSION_LINE=$(get_line_option MK_VERSION)
	local UPDATE_TIME_LINE=$(get_line_option LAST_UPDATE)

	local LAST_VERSION=$(echo ${MK_VERSION//./})
	LAST_VERSION=$((${LAST_VERSION} + 1))

	local CURRENT_VERSION=$(echo ${LAST_VERSION:0:1}.${LAST_VERSION:1:1}.${LAST_VERSION:2:1})
	local CURRENT_DATE=$(date +%Y-%m-%d)

	sed -i "${VERSION_LINE}s/.*/MK_VERSION=${CURRENT_VERSION}/g" ~/.bash_aliases
	sed -i "${UPDATE_TIME_LINE}s/.*/LAST_UPDATE=${CURRENT_DATE}/g" ~/.bash_aliases

	cd ~
	source ~/.bashrc
}

function version_info() {
	echo -e "$(HEAD Version) \t: ${MK_VERSION}"
	echo -e "$(HEAD Last_Update) : ${LAST_UPDATE}"
}

function update_project_name() {
	local TARGET_PROJECT_NAME=$1 # 입력된 새로운 프로젝트 이름

	# 기존 프로젝트 라인 찾기
	local PROJECT_LINE=$(get_line_project_name)

	# 기존 프로젝트를 새로운 이름으로 변경
	if [[ -n "${PROJECT_LINE}" ]]; then
		sed -i "${PROJECT_LINE}s/NOW_PROJECT=.*/NOW_PROJECT=${TARGET_PROJECT_NAME}/" ~/.bashrc
	else
		# 만약 기존 설정이 없다면 새로 추가
		echo "NOW_PROJECT=${TARGET_PROJECT_NAME}" >>~/.bashrc
	fi
}


function change_workspace_path() {
	if [ -n "$PROJECT_DIR" ]; then
		echo -e ${cSky}"\n [ change workspace path ] \n"${cReset}
		echo "Updating workspace link to: $PROJECT_DIR"
		echo "${ROOT_PW}" | sudo -kS rm -rf /home/workspace
		echo "${ROOT_PW}" | sudo -kS ln -sf "$PROJECT_DIR" /home/workspace
	else
		echo "Error: PROJECT_DIR is empty."
	fi
}

function change_project() {
	local check_value="false"
	local PRE_PROJECT=${NOW_PROJECT}
	local LIST=(${PROJECT_LIST[@]})

	local is_valid_arg="false"
	local temp_select=""
	local SELECT_PROJECT=""

	echo -e "\n${cBold}[ Current Project : ${cYellow}${PRE_PROJECT}${cReset} ${cBold}]${cReset}"

	# Check Var is valid
	if [ $# -ge 1 ]; then
		temp_select=$(echo -e $1 | tr "[:lower:]" "[:upper:]")
		for each in ${LIST[@]}; do
			if [ "${temp_select}" == "${each}" ]; then
				is_valid_arg="true"
				break
			fi
		done

		if [ "${is_valid_arg}" == "false" ]; then
			echo -e "${NOTICE} Not Valid Argument.\n"
		fi
	fi

	# Choose Project to Change
	if [ "${is_valid_arg}" == "true" ]; then
		# Set Change Project when recv Correct Arg
		SELECT_PROJECT="${temp_select}"
	else
		# Set Change Project when not recv Arg
		LIST+=("Exit")
		echo -e "${cYellow}[ Choice Project to Change ]${cReset}"
		select var in "${LIST[@]}"; do
			SELECT_PROJECT="${var}"
			break
		done

		# Exit
		for value in ${LIST[@]}; do [ "${value}" == "${SELECT_PROJECT}" ] && check_value="true"; done
		if [ "${check_value}" == "false" ]; then
			echo -e ${ERROR} "Invalid Project Name"
			return
		fi
		test "${SELECT_PROJECT}" == "Exit" && return
	fi

	# Change Setting
	echo -e " - Change setting : .bashrc ${SELECT_PROJECT}"
	#	change_project_by_bashrc ${SELECT_PROJECT}	# 활성 비활성 함수
	update_project_name ${SELECT_PROJECT}

	echo -e " - ${cYellow}${PRE_PROJECT}${cReset} -> ${cGreen}${SELECT_PROJECT}${cReset}"

	SELECT_PROJECT=$(echo -e ${SELECT_PROJECT} | tr "[:upper:]" "[:lower:]")

	#	echo -e " - Change setting : project_change.sh -> ${SELECT_PROJECT}"
	#	cd ~/blackbox
	#	./project_change.sh ${SELECT_PROJECT}
	#	echo -e " - Change Done."

	#	cd ~
	source ~/.bashrc

	change_workspace_path

	echo -e " - source ~/.bashrc Done.\n"
}

function setting_option() {
	local choice_num="-1"
	local OPT_LIST=("AUTO_DIR_COPY" "AUTO_NFS_DETECT" "AUTO_BACKUP" "CHANGE_PROMPT" "IMPROVED_AUTO_COMPLETE" "FASTER_MK_APP" "Exit")
	local opt_line=""
	local opt_value=""
	local separator="|"

	local DETAIL_INFO_LIST=(
		"- Create FW directory in home directory.\n- Automatically copies the .arm file generated by 'mk' to the ${cYellow}~/FW${cReset} directory."
		"- Check if nfs is mounted.\n- If connected, the .arm file is automatically copied to the ${cYellow}~/install${cReset} directory."
		"- Automatically save the code you are currently working on in git stash.\n- This function only works once every hour."
		"- Replace the prompt output of the terminal.\n- Prints the current project and directory."
		"- Change the autocomplete algorithm.\n- Delete word when esc key twice | Auto-completion cycle | Highlight"
		"- Speed up mk_app.sh by using multiple cores"
	)

	while [ "${choice_num}" -lt 6 ]; do
		clear
		echo -e "\n== [ Option ] ================================================================="
		for n in {0..6}; do
			opt_line=$(get_line_option ${OPT_LIST[$n]})
			opt_value=$(get_value_option ${OPT_LIST[$n]})
			separator="|"

			if [ "${choice_num}" -eq $n ]; then
				echo -e -n "${cBold}"
				separator=">"
			fi

			test "${opt_value}" == "Y" && printf "${cGreen}"
			test "${opt_value}" == "N" && printf "${cDim}"
			echo -e "$n ${separator} ${OPT_LIST[$n]}"
			printf "${cReset}"
		done
		echo -e "-------------------------------------------------------------------------------"
		if [ "${choice_num}" == "-1" ]; then
			echo -e "* No number has been entered yet.\n-\n-"
		else
			echo -e "${cBold}* ${OPT_LIST[$choice_num]}${cReset}"
			echo -e "${DETAIL_INFO_LIST[$choice_num]}"
		fi
		echo -e "== [ Option ] ================================================================="
		printf "Enter the number of options you want to ${cGreen}enable${cReset}/${cDim}disable${cReset} : "

		read choice_num

		if [ "${choice_num}" -gt 6 ]; then
			continue
		elif [ "${choice_num}" -eq 6 ]; then
			cd ~
			source ~/.bashrc
			break
		fi

		opt_line=$(get_line_option ${OPT_LIST[$choice_num]})
		opt_value=$(get_value_option ${OPT_LIST[$choice_num]})

		if [ "${opt_value}" == "Y" ]; then
			sed -i "${opt_line}s/.*/${OPT_LIST[$choice_num]}=N/g" ~/.bash_aliases
		else
			sed -i "${opt_line}s/.*/${OPT_LIST[$choice_num]}=Y/g" ~/.bash_aliases
		fi

		cd ~
		source ~/.bashrc
	done
	echo -e "\n${DONE} mk Option Setting Done.\n"
}

# send_file_to_tftp → send_file_to 통합으로 대체
function send_file_to_tftp() {
	send_file_to tftp "$@"
}

# send_file_to_http → send_file_to 통합으로 대체
function send_file_to_http() {
	send_file_to http "$@"
}

# ============== 통합 파일 전송 함수 ============== #
# 사용법:
#   send_file_to tftp          → TFTP로 전송 (이름 유지)
#   send_file_to tftp fw       → TFTP로 전송 (FW_NAME으로 이름 변경)
#   send_file_to tftp uboot    → TFTP로 uboot 이미지 전송
#   send_file_to http          → HTTP로 전송 (FW_NAME으로 이름 변경)
function send_file_to() {
	local DEST_TYPE="${1:-tftp}"  # tftp 또는 http
	local MODE="${2:-}"           # fw, uboot, 또는 빈칸
	local COPY_DIR SELECT_FILE DEST_FILE_NAME
	local UBOOT_FILE_NAME="nand-ipq5332-single-256M.img"

	# 대상 디렉토리 결정
	case "$DEST_TYPE" in
		tftp) COPY_DIR="$TFTP_PATH" ;;
		http) COPY_DIR="$HTTP_PATH" ;;
		*)    echo -e "${ERROR} 알 수 없는 대상: $DEST_TYPE (tftp|http)"; return 1 ;;
	esac

	cd "${FW_DIR}" || { echo -e "${ERROR} FW_DIR 이동 실패: $FW_DIR"; return 1; }
	echo -e "${RUN} .img file : ${FW_DIR} -> ${cLine}${COPY_DIR}${cReset}"

	# uboot 모드면 파일 선택 스킵
	if [ "$MODE" == "uboot" ]; then
		SELECT_FILE="$UBOOT_FILE_NAME"
	fi

	# 파일 선택 (SELECT_FILE이 아직 비어있으면)
	if [ -z "$SELECT_FILE" ]; then
		local img_count=$(ls -1 2>/dev/null | grep -c '\.img$')
		local zip_count=$(ls -1 2>/dev/null | grep -c '\.zip$')

		if [ "$img_count" -ge 2 ]; then
			SELECT_FILE=$(_pick_file "img" "[ Choice file to copy ./$DEST_TYPE ]")
		elif [ "$zip_count" -ge 2 ]; then
			SELECT_FILE=$(_pick_file "zip" "[ Choice file to copy ./$DEST_TYPE ]")
		elif [ "$img_count" -ge 1 ]; then
			SELECT_FILE="$(ls -t | grep '\.img$' | head -n 1)"
		elif [ "$zip_count" -ge 1 ]; then
			SELECT_FILE="$(ls -t | grep '\.zip$' | head -n 1)"
		fi
	fi

	if [ -z "$SELECT_FILE" ] || [ "$SELECT_FILE" == "Not Copy File" ]; then
		echo -e "- Cancel File Copy to $DEST_TYPE"
		return
	fi

	# 기존 이미지 백업
	cd "${COPY_DIR}" || return 1
	if [ "$(ls -1 2>/dev/null | grep -c '\.img$')" -ge 2 ] && [ -d backup_img ]; then
		mv *.img backup_img/. 2>/dev/null
	fi

	# 대상 파일명 결정
	case "$MODE" in
		uboot) DEST_FILE_NAME="$UBOOT_FILE_NAME" ;;
		fw)    DEST_FILE_NAME="$FW_NAME" ;;
		*)
			# http는 기본적으로 FW_NAME, tftp는 원본명 유지
			[ "$DEST_TYPE" == "http" ] && DEST_FILE_NAME="$FW_NAME" || DEST_FILE_NAME="$SELECT_FILE"
			;;
	esac

	cp -a "${FW_DIR}/${SELECT_FILE}" "${COPY_DIR}/${DEST_FILE_NAME}"
	if [ $? -gt 0 ]; then
		echo -e "\n${ERROR} Copy file to ${DEST_TYPE^^} FAILED.\n"
		return 1
	fi

	echo -e "${DONE} select file : ${cGreen}${SELECT_FILE}${cReset}"
	echo -e "${DONE} file copy done : ${cGreen}${DEST_FILE_NAME}${cReset}"
}

# fzf 또는 select로 파일 선택하는 헬퍼
# _pick_file <ext> <header>
_pick_file() {
	local ext="$1" header="$2"
	local result

	check_installed_package fzf
	if [ $? -eq 0 ]; then
		local query_opt=""
		[ -n "$FW_PRIORITY_SEARCH" ] && query_opt="--query=$FW_PRIORITY_SEARCH"
		result=$(ls -t | grep "\.${ext}$" | head -n 5 |
			fzf --cycle --height 10% --reverse --border \
				--header "$header" $query_opt)
	else
		local FILE_LIST=($(ls -t | grep "\.${ext}$" | head -n 3) "Not Copy File")
		echo -e "${cYellow}${header}${cReset}"
		select var in "${FILE_LIST[@]}"; do
			result="$var"
			break
		done
	fi
	echo "$result"
}

function send_file_to_nfs() {
	#나중에 수정

	local CUR_DATE=$(date +%Y%m%d)
	local INS_DIR=""
	local PROJECT_NAME=$(project_version_name)
	local SELECT_FILE=""
	local COPY_DIR=""

	# Set To. Dir
	INS_DIR=$(get_fw_install_dir ${PROJECT_NAME})

	# Set From. Dir
	COPY_DIR=$(get_install_dir ${PROJECT_NAME})

	cd ${INS_DIR}

	echo -e "${RUN} .arm file : fw_install -> ${cLine}${COPY_DIR}${cReset}"

	# Set Target File
	if [ $(ls -l | grep ${CUR_DATE}\.arm$ | wc -l) -ge 2 ]; then
		check_installed_package fzf
		if [ "$?" == 0 ]; then
			SELECT_FILE=$(ls -t | grep ${CUR_DATE}\.arm$ | head -n 5 |
				fzf --cycle --height 10% --reverse --border \
					--header "[ Choice file to copy ./janus ]")
		else
			local FILE_LIST=($(ls -t | grep \.arm$ | awk "NR==1")
			$(ls -t | grep \.arm$ | awk "NR==2")
			$(ls -t | grep \.arm$ | awk "NR==3")
			"Not Copy File")

			echo -e "[ More than one file in fw_install dir. ]"
			echo -e "${cYellow}[ Choice file to copy ./janus ]${cReset}"
			select var in "${FILE_LIST[@]}"; do
				SELECT_FILE="${var}"
				break
			done

		fi
	else
		SELECT_FILE="$(ls -t | grep ${CUR_DATE}\.arm$ | head -n 1)"
	fi

	if [ "${SELECT_FILE}" == "Not Copy File" -o "${SELECT_FILE}" == "" ]; then
		echo -e "- Cancel File Copy to ./janus"
		return
	fi

	cd ${COPY_DIR}
	if [ $(ls -l | grep \.arm$ | wc -l) -gt 0 ]; then
		rm *.arm
	fi

	cp -a ${INS_DIR}/${SELECT_FILE} ${COPY_DIR}

	if [ $? -gt 0 ]; then
		echo -e "\n${ERROR} Copy file to NFS FAILED.\n"
		return
	fi

	echo -e "${DONE} file copy done : ${cGreen}${SELECT_FILE}${cReset}"
}

function make_update_file() {
	#나중에 수정

	local _option=" "
	local _project_name=$(project_version_name)

	echo -e "\n${RUN} make_update_file"

	local valid_model_list=($(extract_mkapp_list))
	local valid_model_value="false"
	valid_model_list+=(".")

	for arg in ${valid_model_list[@]}; do
		if [ "${arg}" == "$1" ]; then
			valid_model_value="true"
			break
		fi
	done

	if [ "${valid_model_value}" == "false" ]; then
		echo -e "${NOTICE} Model name Invalid. mkTool run canceled.\n"
		return
	fi

	if [ ! "$2" == "mkAppOnly" ]; then
		# Setting option
		if [ "$2" == "all" -o "$2" == "cleanInstall" ]; then
			_option=" clean "
		fi

		if [ "${AUTO_DIR_COPY}" == "Y" ]; then
			if [ -d "${HOME}/FW" ]; then
				echo -e "${SET} reset FW dir."
				cd ~/FW
				if [ $(ls -l | grep \.arm$ | wc -l) -gt 0 ]; then
					rm *
				fi
			else
				echo -e "${NOTICE} FW dir not exist. make dir."
				cd ~
				mkdir FW
			fi
		fi

		if [ "${AUTO_BACKUP}" == "Y" ]; then
			local CUR_BACKUP_DATE=$(date +%m%d)
			local CUR_BACKUP_HOUR=$(date +%k)

			echo -e "${SET} Auto backup option."
			if [ ! "${LAST_BACKUP_DATE}" == "${CUR_BACKUP_DATE}" ] || [ ! "${LAST_BACKUP_HOUR}" == "${CUR_BACKUP_HOUR}" ]; then
				git_stash_save_backup_file

				if [ $? -gt 0 ]; then
					echo -e "${ERROR} Auto backup FAILED.\n"
					break
				fi

				echo -e "${DONE} Auto backup done."

			else
				echo -e ${cGreen}"* Already backed up within an hour"${cReset}
			fi

		fi

		cd ~/blackbox/source

		echo -e "${RUN} make${_option}install.\n"
		make${_option}install

		if [ $? -gt 0 ]; then
			echo -e "\n${ERROR} make${_option}install FAILED.\n"
			return
		fi

		echo -e "\n\n${DONE} make${_option}install."
	fi

	cd ~/blackbox/system
	echo -e "${RUN} mk_app.sh${cGreen}" $1 "${cReset}\n\n"

	if [ "${FASTER_MK_APP}" == "Y" ]; then
		local core_num=$(cat /proc/cpuinfo | grep cores | wc -l)

		echo -e "${SET} mk_app.sh run faster."
		echo -e "${SET} Get cpu process : ${cSky}${core_num}${cReset}"
		echo -e "${SET} copy mk_app.sh -> faster_mk_app.sh"
		echo -e "${SET} run core process num 1 -> ${core_num}\n\n"

		touch make_app.log

		cp -af mk_app.sh faster_mk_app.sh
		sed -i "s/-processors 1/-processors ${core_num} -no-progress /g" faster_mk_app.sh
		sed -i 's/rm -rf ${SQFS_NAME}/rm -rf ${SQFS_NAME}\n echo -e " - $INSTALL_TOTAL_NAME.arm" >> make_app.log\n/g' faster_mk_app.sh

		./faster_mk_app.sh "$1"

		echo -e "\n\n================= MAKE F/W LIST ==========================="
		cat make_app.log
		echo -e "==========================================================="

		rm make_app.log
		rm faster_mk_app.sh
	else
		./mk_app.sh "$1"
	fi

	if [ $? -gt 0 ]; then
		echo -e "\n${ERROR} mk_app.sh $1 FAILED.\n"
		return
	fi

	local make_name="Default"
	test "$1" == "." || make_name=$1

	echo -e "\n\n${DONE}\tF/W update File (${cGreen} ${make_name} ${cReset}) make Done."
	echo -e "$(HEAD PROJECT)\t"${NOW_PROJECT}

	local CUR_DATE=$(date +%Y%m%d)
	local INS_DIR=""

	echo -e "$(HEAD MAKE_TIME)\t"$(date)

	# Auto copy file to ~/FW ( when option : Y )
	if [ "${AUTO_DIR_COPY}" == "Y" ]; then
		INS_DIR=$(get_fw_install_dir ${_project_name})
		cd ${INS_DIR}

		if [ $(ls -l | grep ${CUR_DATE}\.arm$ | wc -l) -ge 2 ]; then
			local file_count=$(ls -l | grep ${CUR_DATE}\.arm$ | wc -l)
			for n in $(seq 1 ${file_count}); do
				cp -a ${INS_DIR}/$(ls -t | grep ${CUR_DATE}\.arm$ | awk "NR==${n}") ~/FW
				if [ ${n} -gt 3 ]; then break; fi
			done
		else
			cp -a ${INS_DIR}/$(ls -t | grep ${CUR_DATE}\.arm$ | head -1) ~/FW
		fi

		if [ $? -gt 0 ]; then
			echo -e "\n${ERROR} Copy file FAILED.\n"
			return
		fi

		echo -e "${DONE}\tFile Copy to '~/FW' Direcotry.\n"
	fi

	# Auto copy file to ~install ( ./janus )
	if [ "${AUTO_NFS_DETECT}" == "Y" ]; then
		ping ${NFS_IP} -c 1 -i 1 &>/dev/null
		if [ $? -eq 0 ]; then
			echo -e "${cSky}[ NFS Connected : Copy to update file to ./janus ]${cReset}\n"
			send_file_to_nfs
		fi
	fi

	echo ""
}

function davo_macro_help() {
	resize -s 50 ${COLUMNS} >/dev/null

	echo -e "\n== [ HELP ] =================================================================\n"
	echo -e " * ${cSky}dv ap${cReset}		: Sudo chown Owner:Owner /dev/ttyUSB0"
	echo -e " * ${cSky}mk setg${cReset} 	: Change & Adjust project"
	echo -e " * ${cSky}mk option${cReset} 	: Setting mk Tool option"
	echo -e "\n ---------------------------------------------------------------------------\n"
	echo -e "\n ${cSky}[Option]${cReset}"
	echo -e " NOT WORKING HERE "
	echo -e " - m	: 'compile make ' current Project"
	echo -e " - c 	: 'compile clean' current Project"
	echo -e " - i 	: 'mkimage.sh' without compile make"
	echo -e " - cm 	: 'compile clean make' current Project"
	echo -e " - cp 	: 'image copy' current Project"
	echo -e "\n ${cSky}[Sub Option]${cReset}"
	echo -e " - .	: 'compile make + mkimage.sh +copy '"
	echo -e " - all : 'compile clean make + mkimage.sh +copy '"
	#	echo -e ""
	#	echo -e " ex) mk i	: 'make install' the Project in any directory"
	#	echo -e "     mk ci .	: 'make clean install' at current directory"
	#	echo -e "     mk ${cGreen}.${cReset}	: 'make install' & 'mk_app.sh' ${cGreen}default${cReset} model"
	#	echo -e "     mk ${cGreen}aoki${cReset}	: 'make install' & 'mk_app.sh ${cGreen}aoki${cReset}'"
	#	echo -e "     mk ${cGreen}gdr${cReset} all	: 'make clean install' & 'mk_app.sh ${cGreen}gdr${cReset}'"
	#	echo -e "\n ---------------------------------------------------------------------------\n"
	echo -e " * mk clear\t: Clear the 'tftp Folder' "
	#	echo -e " * mk store\t: Backup the '../fw_install' in Current Project"
	#	echo -e " * ${cYellow}mk open${cReset}\t: Open the '../fw_install' in Current Project or Other Dir."
	echo -e " * ${cYellow}mk upp${cReset}\t: sudo apt update & upgrade at once"
	#	echo -e " * mk version\t: View version information"
	#	echo -e " * mk patch_log\t: View the patch log"
	#	echo -e " * mk sd_copy\t: Copy the most recent arm file to the mounted SD card"
	#	echo -e " * ${cYellow}mk pull${cReset}\t: Git pull Current Project"
	#	echo -e " * ${cYellow}mk kill${cReset}\t: Close all terminals except the process is running"

	echo -e "\n== [ HELP ] =================================================================\n"
}

function mk_open_dir() {
	#나중에 수정
	local INS_DIR=""
	local PROJECT_NAME=$(project_version_name)

	if [ $# -eq 1 ]; then
		if [ "$1" == "FW" ]; then
			nautilus ${HOME}/FW
			return
		else
			nautilus $1
			return
		fi
	fi

	INS_DIR=$(get_fw_install_dir ${PROJECT_NAME})
	nautilus ${INS_DIR}
}


function tftp_dir_clear() {
	local INS_DIR="${TFTP_PATH}"

	if [ -d "${INS_DIR}" ]; then
		cd ${INS_DIR}
	else
		echo -e "${NOTICE} ${INS_DIR} not exist."
		return
	fi

	if [ $(ls -l | grep \.img$ | wc -l) -gt 0 ]; then
		rm *.img
	fi
	echo -e "- ${cGreen}${INS_DIR}${cReset} Clear"
}

function run_git_pull() {
	local PROJECT_NAME=$1
	local Pull_Dir="${HOME}/blackbox/${PROJECT_NAME}"

	echo -n -e "${RUN} Git Pull - ${cGreen}"
	echo -e ${PROJECT_NAME} | tr "[:upper:]" "[:lower:]"
	echo -n -e ${cReset}

	cd ${Pull_Dir}
	git pull
	echo
}

function manage_git_pull() {
	local route_list=("v4" "a3" "s3" "v3" "v8" "util" "all")
	local is_all_value="false"
	local args=$(echo $@ | tr "[:upper:]" "[:lower:]")
	local PROJECT_NAME=$(project_version_name)

	echo ""
	if [ "${args}" == "" ]; then
		run_git_pull ${PROJECT_NAME}
		echo -e "${DONE} Git Pull\n"
		return
	fi

	for arg in ${args[@]}; do
		if [ "${arg}" == "all" ]; then
			run_git_pull v4
			run_git_pull s3
			run_git_pull a3
			run_git_pull v3
			run_git_pull v8
			run_git_pull util
			echo -e "${DONE} Git Pull\n"
			return
		fi

		for route in ${route_list[@]}; do
			if [ "${arg}" == "${route}" ]; then
				run_git_pull ${arg}
			fi
		done
	done
	echo -e "${DONE} Git Pull\n"
}

function fw_install_dir_backup() {
	local CUR_DATE=$(date +%Y%m%d)
	local INS_DIR=""
	local PROJECT_NAME=$(project_version_name)
	local SELECT_FILE=""
	local COPY_DIR=""
	local BACKUP_DIR="${INS_DIR}/${CUR_DATE}"

	# Set To. Dir
	INS_DIR=$(get_fw_install_dir ${PROJECT_NAME})
	BACKUP_DIR="${INS_DIR}/${CUR_DATE}"

	echo -e "${RUN} Backup arm file in fw_install dir"

	if [ -d ${BACKUP_DIR} ]; then
		cd ${INS_DIR}
		mv -vf *.arm ${BACKUP_DIR}
	else
		mkdir ${BACKUP_DIR}
		cd ${INS_DIR}
		mv -vf *.arm ${BACKUP_DIR}
	fi

	if [ $? -gt 0 ]; then
		echo -e "\n${ERROR} Move file FAILED.\n"
		return
	fi

	echo -e "\n${DONE} File Move to ${cGreen}${BACKUP_DIR}${cReset} Directory.\n"
}

function update_mk_file() {
	local pre_dir=$(pwd)

	echo -e "\n${RUN} mk Tool Update"

	cd ~
	cp ~/.bash_aliases ~/.bash_aliases_backUp
	cp ~/.bash_completion ~/.bash_completion_backUp

	local BACKUP_FLAG=("AUTO_DIR_COPY" "AUTO_NFS_DETECT" "AUTO_BACKUP" "CHANGE_PROMPT" "IMPROVED_AUTO_COMPLETE"
		"FASTER_MK_APP" "LAST_BACKUP_DATE" "LAST_BACKUP_HOUR" "ROOT_PW")
	local BACKUP_OPTION_LINE=()
	local BACKUP_OPTION_VALUE=()
	local temp_line=""
	local temp_value=""
	local opt_len=${#BACKUP_FLAG[@]}

	if [ $? -gt 0 ]; then
		echo -e "\n${ERROR} Copy Backup file Failed.\n"
		return
	fi

	echo -e "${SET} Extract and save locally saved options"

	for ((i = 0; i < ${opt_len}; i++)); do
		temp_value=$(get_backup_value_option ${BACKUP_FLAG[$i]})

		if [ "${temp_value}" == "" -a ! ${BACKUP_FLAG[$i]} == "ROOT_PW" ]; then
			temp_value=N
		fi

		BACKUP_OPTION_VALUE+=(${temp_value})
	done

	if [ -d "${HOME}/MkTool" ]; then
		rm -rf ${HOME}/MkTool
	fi

	echo -e "${RUN} Git Clone - MkTool"

	cd ${HOME}
	git clone ${GitAddress}
	cd MkTool

	\mv -f .bash_aliases ${HOME}/
	\mv -f .bash_completion ${HOME}/

	if [ $? -gt 0 ]; then
		echo -e "${ERROR} Update Failed. Rollback .bash_aliases file."
		mv ~/.bash_aliases_backUp ~/.bash_aliases
		return
	fi

	echo -e "${SET} Applies the temporary saved local storage variable to the newly received file."

	for ((i = 0; i < ${opt_len}; i++)); do
		temp_line=$(get_line_option ${BACKUP_FLAG[$i]})
		BACKUP_OPTION_LINE+=(${temp_line})
	done

	for ((i = 0; i < ${opt_len}; i++)); do
		sed -i "${BACKUP_OPTION_LINE[$i]}s/.*/${BACKUP_FLAG[$i]}=${BACKUP_OPTION_VALUE[$i]}/g" ~/.bash_aliases
	done

	echo -e "${DONE} Applies done."

	cd ~
	echo -e "${RUN} Meld Backup .bash_aliases & .bash_completion"
	meld .bash_aliases .bash_aliases_backUp
	meld .bash_completion .bash_completion_backUp

	echo -e "${RUN} Autocomplete script being applied to root directory"
	source ~/.bashrc

	echo -e "${DONE} Autocomplete script being applied done."
	echo -e "${DONE} mk Tool Update Complete\n"

	cd ${pre_dir}
}

function check_root_pw() {
	if [ "${ROOT_PW}" == "" ]; then
		echo -e "${ERROR} ROOT_PW가 설정되지 않았습니다."
		echo -e "  ~/.private/secrets.sh 에 ROOT_PW=<패스워드> 를 추가하세요."
		return 1
	fi
}


function wireshark_exec() {
	echo -e "\n${RUN} WireShark "

	check_root_pw

	echo -e ${cSky}"\n [ WireShark ] \n"${cReset}
	echo "${ROOT_PW}" | sudo -kS wireshark &

}

function update_package_version() {
	echo -e "\n${RUN} Package Update "

	check_root_pw

	echo -e ${cSky}"\n [ apt-get update ] \n"${cReset}
	echo "${ROOT_PW}" | sudo -kS apt-get update -y
	echo -e ${cSky}"\n [ apt-get upgrade ] \n"${cReset}
	echo "${ROOT_PW}" | sudo -kS apt-get upgrade -y

	check_installed_package snap
	if [ "$?" == 0 ]; then
		echo -e ${cSky}"\n [ snap refresh ] \n"${cReset}
		echo "${ROOT_PW}" | sudo -kS snap refresh
	fi

	echo -e ${cSky}"\n [ vim PlugInstall ] \n"${cReset}
	vim -c ':PlugInstall | qa' -y

#	echo -e ${cSky}"\n [ gemini-cli update ] \n"${cReset}
#	npm install -g @google/gemini-cli

	echo -e "\n${DONE} Package Update Done\n"
}

function davo_macro_ap_connect() {

	check_root_pw

	echo "${ROOT_PW}" | sudo -S chown ${USER}:${USER} /dev/ttyUSB0
	echo "${ROOT_PW}" | sudo -S chown ${USER}:${USER} /dev/ttyUSB1
	echo "${ROOT_PW}" | sudo -S chown ${USER}:${USER} /dev/ttyUSB2
	#	echo -e "sudo chown ${USER}:${USER} /dev/ttyUSB0"

	echo -e "\n${DONE} AP_Connect Done"
}

function save_to_bash_functions() {
	local key=$1
	local value=$2
	local file="$HOME/.bash_functions"

	if grep -q "^$key=" "$file"; then
		sed -i "s|^$key=.*|$key=\"$value\"|" "$file"
	else
		echo "$key=\"$value\"" >>"$file"
	fi

	export "$key"="$value"
	echo "✅ $key 값이 [$value] 로 저장되었습니다."
}

function davo_macro_diff() {
	local cmd=$1
	shift
	local tools=("meld" "vimdiff" "bcompare" "vscode")

	show_settings() {
		echo -e "📌 현재 설정"
		echo -e "- 비교 도구: [\033[1;32m$DV_DIFF_TOOL\033[0m]"
		echo -e "- 프로젝트 1: [\033[1;34m$DV_DIFF_PROJ_1\033[0m]"
		echo -e "- 프로젝트 2: [\033[1;35m$DV_DIFF_PROJ_2\033[0m]"
	}

	select_project() {
		local prompt="$1"
		local proj
		proj=$(printf "%s\n" "${PROJECT_LIST[@]}" | fzf --prompt="$prompt (입력 가능): " --print-query | tail -1)
		echo "$proj"
	}

	case $cmd in
	-s | set)
		local opt=$1
		shift
		case $opt in
		t | tool)
			local tool=$(printf "%s\n" "${tools[@]}" | fzf --prompt="비교 도구 선택: " --print-query | tail -1)
			[[ -z "$tool" ]] && {
				echo "❗ 선택 취소됨"
				return
			}
			save_to_bash_functions "DV_DIFF_TOOL" "$tool"
			;;
		p | pr | pj | proj)
			local p1=$(select_project "프로젝트 1 선택")
			local p2=$(select_project "프로젝트 2 선택")

			if [[ " ${PROJECT_LIST[@]} " =~ " $p1 " ]]; then
				save_to_bash_functions "DV_DIFF_PROJ_1" "$p1"
			else
				echo "❗ [$p1] 은 유효하지 않음. 기존값 유지 [$DV_DIFF_PROJ_1]"
			fi

			if [[ " ${PROJECT_LIST[@]} " =~ " $p2 " ]]; then
				save_to_bash_functions "DV_DIFF_PROJ_2" "$p2"
			else
				echo "❗ [$p2] 은 유효하지 않음. 기존값 유지 [$DV_DIFF_PROJ_2]"
			fi
			;;
		p1)
			local p1=$(select_project "프로젝트 1 선택")
			if [[ " ${PROJECT_LIST[@]} " =~ " $p1 " ]]; then
				save_to_bash_functions "DV_DIFF_PROJ_1" "$p1"
			else
				echo "❗ [$p1] 은 유효하지 않음. 기존값 유지 [$DV_DIFF_PROJ_1]"
			fi
			;;
		p2)
			local p2=$(select_project "프로젝트 2 선택")
			if [[ " ${PROJECT_LIST[@]} " =~ " $p2 " ]]; then
				save_to_bash_functions "DV_DIFF_PROJ_2" "$p2"
			else
				echo "❗ [$p2] 은 유효하지 않음. 기존값 유지 [$DV_DIFF_PROJ_2]"
			fi
			;;
		"" | all)
			echo "⚙️ 전체 설정 시작"

			local tool=$(printf "%s\n" "${tools[@]}" | fzf --prompt="비교 도구 선택: " --print-query | tail -1)
			[[ -n "$tool" ]] && save_to_bash_functions "DV_DIFF_TOOL" "$tool"

			local p1=$(select_project "프로젝트 1 선택")
			[[ " ${PROJECT_LIST[@]} " =~ " $p1 " ]] && save_to_bash_functions "DV_DIFF_PROJ_1" "$p1"

			local p2=$(select_project "프로젝트 2 선택")
			[[ " ${PROJECT_LIST[@]} " =~ " $p2 " ]] && save_to_bash_functions "DV_DIFF_PROJ_2" "$p2"
			;;
		*)
			echo "❗ 알 수 없는 설정 옵션입니다."
			;;
		esac
		;;
	sh | show)
		show_settings
		;;
	*)
		local path=$cmd
		local dir1=$(get_proj_dir "$DV_DIFF_PROJ_1")
		local dir2=$(get_proj_dir "$DV_DIFF_PROJ_2")

		if [[ -z "$dir1" || -z "$dir2" ]]; then
			echo "❗ 프로젝트 설정에 오류. 다시 설정하세요."
			show_settings
			return 1
		fi

		if [[ -z "$path" ]]; then
			path=$(fd --type file . "$dir1" "$dir2" |
				sed -E "s|$dir1/||; s|$dir2/||" |
				sort -u | fzf --prompt="비교할 파일 선택: ")
		fi

		[[ -z "$path" ]] && {
			echo "❗ 파일 선택 취소됨"
			return 1
		}

		# 현재 작업 디렉토리 (심볼릭 경로 유지)
		local cwd="$PWD"

		# 상대 경로 추출 (proj/프로젝트명/ 이후 경로만 남김)
		if [[ "$path" != /* && "$path" != "$dir1"* && "$path" != "$dir2"* ]]; then
			# 'proj/'가 포함된 위치 찾아서 그 이후만 추출
			local sub_path="${cwd#*proj/}"    # dv03-410h or dv03-410h/...
			local proj_name="${sub_path%%/*}" # dv03-410h

			if [[ "$sub_path" == "$proj_name" ]]; then
				# 프로젝트 루트일 경우 rel_path 없음 → 현재 path 그대로 사용
				:
			else
				local rel_path="${sub_path#*/}" # 이후 경로만 추출

				if [[ "$path" == "." ]]; then
					path="$rel_path"
				else
					path="$rel_path/$path"
				fi
			fi
		fi

		# echo "🔎 DEBUG INFO"
		# echo "  - cwd   : $cwd"
		# echo "  - dir1  : $dir1"
		# echo "  - dir2  : $dir2"
		# echo "  - path  : $path"

		# path가 절대경로면 그대로 사용, 아니면 dir 붙여줌
		if [[ "$path" == /* ]]; then
			file1="$path"
			file2="${path/$dir1/$dir2}"
		else
			file1="$dir1/$path"
			file2="$dir2/$path"
		fi

		if [[ ! -e "$file1" && ! -e "$file2" ]]; then
			echo -e "❗ 두 파일 모두 없음: \n$file1\n$file2\n"
			return 1
		elif [[ ! -e "$file1" ]]; then
			echo -e "❗ 파일 없음 (file1): \n$file1\n"
			return 1
		elif [[ ! -e "$file2" ]]; then
			echo -e "❗ 파일 없음 (file2): \n$file2\n"
			return 1
		fi

		case "$DV_DIFF_TOOL" in
			meld) meld "$file1" "$file2" & ;;
			bcompare) bcompare "$file1" "$file2" & ;;
			vimdiff) vimdiff "$file1" "$file2" ;;
			vscode) code --diff "$file1" "$file2" & ;;
			*) echo "❗ 지원되지 않는 툴: $DV_DIFF_TOOL" ;;
		esac
		;;
	esac
}



function docker_open() {
	# Docker 컨테이너 이름 검색
	DOCKER_OUTPUT=$(docker ps -a --format "{{.Names}}") # 컨테이너 이름만 가져옴

	# 포함 여부 확인
	if echo "$DOCKER_OUTPUT" | grep -q "$NOW_PROJECT"; then
		echo "$PROJECT_DIR/start.sh 실행"
		echo "bash $PROJECT_DIR/start.sh"
	else
		echo "$PROJECT_DIR/run.sh 실행"
		echo "bash $PROJECT_DIR/run.sh"
	fi
}

#STANDARD_MANAGEMENT - 규격서 관리
STANDARD_MANAGEMENT_DIR="$HOME/.standard_management_files"
STANDARD_MANAGEMENT_LIST="$STANDARD_MANAGEMENT_DIR/standard_management_files.txt"
BASH_CONFIG_FILE="$HOME/.bashrc"

function standard_management_add_file() {
	# 파일 선택
	local selected_file=$(find "$PWD" -mindepth 1 -type f ! -path "*/.git/*" ! -path "*/node_modules/*" | fzf --prompt="파일 선택: " --height=40% --border --preview="cat {}")

	# 사용자가 취소했을 경우
	if [[ -z "$selected_file" ]]; then
		echo -e "${cRed}파일 선택이 취소되었습니다.${cReset}"
		return 1
	fi

	# 새로운 이름 입력
	echo -e "${cBlue}이 파일을 어떤 이름으로 등록할까요? (취소하려면 엔터): ${cReset}"
	read -r alias_name

	if [[ -z "$alias_name" ]]; then
		echo -e "${cRed}등록이 취소되었습니다.${cReset}"
		return 1
	fi

	# 원본 파일이 존재하는지 확인
	if [[ ! -f "$selected_file" ]]; then
		echo -e "${cRed}선택한 파일이 존재하지 않습니다.${cReset}"
		return 1
	fi

	# 원본 파일을 특정 위치로 복사
	target_file="$STANDARD_MANAGEMENT_DIR/$alias_name"
	cp -a "$selected_file" "$target_file"

	# 경로 저장
	echo -e "$alias_name|$target_file|$selected_file" >>"$STANDARD_MANAGEMENT_LIST"
	echo -e "${cGreen}[$alias_name] 등록 완료!${cReset}"
}

function standard_management_open_file() {
	if [[ ! -f "$STANDARD_MANAGEMENT_LIST" || ! -s "$STANDARD_MANAGEMENT_LIST" ]]; then
		echo -e "${cRed}등록된 파일이 없습니다.${cReset}"
		return 1
	fi

	# 등록된 파일 목록을 표시하고 선택
	local selected_entry=$(cut -d '|' -f1 "$STANDARD_MANAGEMENT_LIST" | fzf --prompt="열 파일 선택: " --height=40% --border)

	# 사용자가 취소했을 경우
	if [[ -z "$selected_entry" ]]; then
		echo -e "${cRed}파일 선택이 취소되었습니다.${cReset}"
		return 1
	fi

	# 선택한 파일 경로 찾기
	local target_file=$(grep "^$selected_entry|" "$STANDARD_MANAGEMENT_LIST" | cut -d '|' -f2)

	# 파일이 존재하는지 확인
	if [[ ! -f "$target_file" ]]; then
		echo -e "${cRed}파일이 존재하지 않습니다.${cReset}"
		return 1
	fi

	# 확장자에 따라 프로그램 선택
	case "$target_file" in
	*.pdf) xdg-open "$target_file" &>/dev/null ;;                                       # PDF는 기본 뷰어로 열기
	*.txt | *.md | *.log | *.sh | *.c | *.cpp | *.py) $DEFAULT_EDITOR "$target_file" ;; # 텍스트 파일은 에디터로 열기
	*) xdg-open "$target_file" &>/dev/null ;;                                           # 그 외 파일은 기본 프로그램으로 열기
	esac
}

function standard_management_remove_file() {
	if [[ ! -f "$STANDARD_MANAGEMENT_LIST" || ! -s "$STANDARD_MANAGEMENT_LIST" ]]; then
		echo -e "${cRed}등록된 파일이 없습니다.${cReset}"
		return 1
	fi

	local selected_entry=$(cut -d '|' -f1 "$STANDARD_MANAGEMENT_LIST" | fzf --prompt="삭제할 파일 선택: " --height=40% --border)

	if [[ -z "$selected_entry" ]]; then
		echo -e "${cRed}파일 선택이 취소되었습니다.${cReset}"
		return 1
	fi

	local target_file=$(grep "^$selected_entry|" "$STANDARD_MANAGEMENT_LIST" | cut -d '|' -f2)

	# 목록에서 제거
	grep -v "^$selected_entry|" "$STANDARD_MANAGEMENT_LIST" >"$STANDARD_MANAGEMENT_LIST.tmp"
	mv "$STANDARD_MANAGEMENT_LIST.tmp" "$STANDARD_MANAGEMENT_LIST"

	echo -e "${cGreen}[$selected_entry] 삭제 완료!${cReset}"
}

function standard_management_set_editor() {
	echo -e "${cYellow}1. Vim${cReset}"
	echo -e "${cYellow}2. VS Code${cReset}"
	echo -e "${cBlue}사용할 기본 에디터를 선택하세요:${cReset}"
	read -r editor_choice

	case "$editor_choice" in
	1)
		DEFAULT_EDITOR="vim"
		echo -e "${cGreen}기본 에디터가 Vim으로 설정되었습니다.${cReset}"
		;;
	2)
		DEFAULT_EDITOR="code"
		echo -e "${cGreen}기본 에디터가 VS Code로 설정되었습니다.${cReset}"
		;;
	*)
		echo -e "${cRed}잘못된 선택입니다.${cReset}"
		return 1
		;;
	esac

	# 기존 설정 제거 후 새 설정 추가
	sed -i '/export DEFAULT_EDITOR=/d' "$BASH_CONFIG_FILE"
	echo "export DEFAULT_EDITOR=$DEFAULT_EDITOR" >>"$BASH_CONFIG_FILE"

	source "$BASH_CONFIG_FILE"

	# `xdg-mime`을 사용하여 텍스트 파일 기본 프로그램 변경
	if [[ "$DEFAULT_EDITOR" == "code" ]]; then
		xdg-mime default code.desktop text/plain
		#elif [[ "$DEFAULT_EDITOR" == "vim" ]]; then
		# Vim은 GUI가 없으므로 기본 open 프로그램으로 설정하기 어려움 -> 별도 처리 필요
		#echo -e "${cYellow}Vim은 GUI 프로그램이 아니므로 xdg-open 적용이 제한적입니다.${cReset}"
	fi
}

# 메인 함수
function standard_management() {
	[[ ! -d "$STANDARD_MANAGEMENT_DIR" ]] && mkdir -p "$STANDARD_MANAGEMENT_DIR"

	echo -e "\n${cBlue}[규격서 관리]${cReset}\n"
	echo -e "${cWhite}1. 파일 추가${cReset}"
	echo -e "${cWhite}2. 파일 열기${cReset}"
	echo -e "${cWhite}3. 파일 삭제${cReset}"
	echo -e "${cWhite}4. 텍스트 에디터 변경${cReset}"
	echo -e "${cYellow}선택하세요: ${cReset}"
	read -r choice

	case "$choice" in
	1) standard_management_add_file ;;
	2) standard_management_open_file ;;
	3) standard_management_remove_file ;;
	4) standard_management_set_editor ;;
	*) echo -e "${DONE}${cRed}잘못된 입력입니다.${cReset}" ;;
	esac
}
### 규격서 관리 완료

function setting_nfs() {
	echo -e "\n${RUN} NFS Setting ( ${NOW_PROJECT} )\n"
	check_installed_package fzf
	if [ $? -gt 0 ]; then
		show_how_install_fzf
		return
	fi

	local PROJECT_NAME=$(project_version_name)
	local NFS_DIR=""
	local SELECT_VALUE=""

	# Set Dir
	NFS_DIR=$(get_install_dir ${PROJECT_NAME})

	cd ${NFS_DIR}/pack
	SELECT_FILE=$(find . -maxdepth 1 -type d |
		fzf --cycle --height 30% --reverse --border \
			--header "[ Select Model to apply oem.ini ]")

	if [ "${SELECT_FILE}" == "" ]; then
		echo -e "${NOTICE} setting nfs cancel"
		return
	fi

	cd ${SELECT_FILE}
	cp -a * ../..
	echo -e "${SET} ${cSky}oem.ini${cReset} ( ${cLine}${SELECT_FILE}${cReset} ) copy"

	cd ${NFS_DIR}/skin
	SELECT_FILE=$(find . -maxdepth 1 -type d |
		fzf --cycle --height 30% --reverse --border \
			--header "[ Select Model to apply skin ]")

	if [ "${SELECT_FILE}" == "" ]; then
		echo -e "${NOTICE} setting nfs cancel"
		return
	fi

	cd ${SELECT_FILE}
	cp -a * ./..
	echo -e "${SET} ${cSky}Model Skin${cReset} ( ${cLine}${SELECT_FILE}${cReset} ) copy"

	if [ "${PROJECT_NAME}" == "v3" ]; then
		cd ${NFS_DIR}/language/gnet/
		cp -a * ./..
		echo -e "${SET} ${cSky}Language${cReset} ( ${cLine}${SELECT_FILE}${cReset} ) copy"
	fi

	echo -e "\n${DONE} NFS Setting Done\n"
}

function nfs_skin_copy() {
	cd ~/install/gnet_v4/skin/dforce/
	cp -a * ../.
	cd ~/install/gnet_v4/pack/gnet_dforce/
	cp -a * ../../.
	#	cd ~/install/gnet_v8/skin/gnet/
	#	cp -a * ../.
	#	cd ~/install/gnet_v8/pack/gnet_g6/
	#	cp -a * ../../.
	#	cd ~/install/gnet_v8/language/gnet/
	#	cp -a * ../.
}

function sd_copy_file() {
	check_installed_package fzf
	if [ $? -gt 0 ]; then
		show_how_install_fzf
		return
	fi

	echo -e "\n${RUN} Copy file to SD card\n"

	local SD_PATH=""
	local SD_NUM=$(df -h | grep "sd" | grep -v "/$" | wc -l)

	if [ "${SD_NUM}" -gt 1 ]; then
		SD_PATH=$(df -h | grep "sd" | grep -v "/$" | fzf --cycle --height 10% --reverse --border --header "[ Select Disk for Copy file ]")
	elif [ "${SD_NUM}" -eq 0 ]; then
		echo -e "${ERROR} Not Connected SD card - Please check SD card mounted\n"
		return
	else
		SD_PATH=$(df -h | grep "sd" | grep -v "/$")
	fi

	SD_PATH=$(echo ${SD_PATH} | awk -F ' ' '{printf $6}')
	echo -e "${RUN} SD card Path - ${SD_PATH}"

	local INS_DIR=""
	local CUR_DATE=$(date +%Y%m%d)
	local PROJECT_NAME=$(project_version_name)
	local SELECT_FILE=""

	INS_DIR=$(get_fw_install_dir ${PROJECT_NAME})
	cd ${INS_DIR}

	# Set Target File
	if [ $(ls -l | grep ${CUR_DATE}\.arm$ | wc -l) -ge 2 ]; then
		SELECT_FILE=$(ls -t | grep ${CUR_DATE}\.arm$ | head -n 5 |
			fzf --cycle --height 10% --reverse --border \
				--header "[ Choice file to move SD disk ]")
	else
		SELECT_FILE="$(ls -t | grep ${CUR_DATE}\.arm$ | head -n 1)"
	fi

	if [ "${SELECT_FILE}" == "" ]; then
		echo -e "\n${NOTICE} Cancel File Copy to SD disk"
		return
	fi

	if [ ! -d "${SD_PATH}/update" ]; then
		mkdir "${SD_PATH}/update"
	fi

	echo -e "${RUN} Copying..."
	cp -av ${SELECT_FILE} "${SD_PATH}/update"

	if [ $? -gt 0 ]; then
		echo -e "\n${ERROR} Copy file to SD card FAILED.\n"
		return
	fi

	echo -e "\n${RUN} Unmount SD card : ${SD_PATH}"
	umount ${SD_PATH}
	echo -e "${DONE} Unmount SD card Done"

	if [ $? -gt 0 ]; then
		echo -e "\n${ERROR} Unmount SD card FAILED.\n"
		return
	fi

	echo -e "\n${DONE} Copy file ${cGreen}${SELECT_FILE}${cReset} to SD card Done"
	echo -e "${NOTICE} Please Uncheck Vbox Menu - USB\n"
}

function kill_all_terminal() {
	local PID_LIST=()
	local PPID_LIST=()
	local RUN_LIST=()
	local count=0

	PID_LIST+=($(ps -efc | grep "bash$" | awk '{print $2}'))
	PPID_LIST+=($(ps -efc | grep "bash$" | awk '{print $3}'))

	echo -e "\n${RUN} Kill all Terminal\n"

	if [ ! "$1" == "all" ]; then
		echo -e "${NOTICE} Safe Mode : The terminal where the process is running is not killed."
		echo -e "${NOTICE} If you want to kill all terminal, use '${cYellow}mk kill all${cReset}'\n"
		RUN_LIST+=($(ps -efc | grep "pts" | grep -v "bash$" | grep -v $$ | awk '{print $3}'))

		for i in ${!RUN_LIST[@]}; do
			for j in ${!PID_LIST[@]}; do
				if [ "${RUN_LIST[i]}" == "${PID_LIST[j]}" ]; then
					unset PID_LIST[j]
					unset PPID_LIST[j]
					break
				fi
			done
		done
	fi

	# Excluding processes whose PPID is PID of the current terminal
	for i in ${!PPID_LIST[@]}; do
		if [ "${PPID_LIST[i]}" == "$$" ]; then
			unset PID_LIST[i]
		fi
	done

	# Exclude current terminal from terminal exit list
	for i in ${!PID_LIST[@]}; do
		if [ "${PID_LIST[i]}" == "$$" ]; then
			unset PID_LIST[i]
			break
		fi
	done

	echo -e "- Total Terminal : ${#PID_LIST[@]}\n"

	for i in ${!PID_LIST[@]}; do
		count=$((${count} + 1))
		kill -9 ${PID_LIST[i]}
		echo -e "- Kill Terminal ${count} [ ${cYellow}${PID_LIST[i]}${cReset} ]"
	done

	echo -e
	killall --quiet nautilus

	echo -e "\n${DONE} Kill all Terminal & Folder\n"
}

function show_info() {
	#	check_installed_package duf
	#	if [ "$?" -gt 0 ]
	#	then
	#		echo -e "${NOTICE} : Sorry. that function need ${cGreen}duf${cReset} Package"
	#		echo -e "- sudo apt-get install duf"
	#		return
	#	fi

	resize -s 32 ${COLUMNS} >/dev/null
	duf /home
	echo
	neofetch --ascii_colors 7 4 --colors 4 4 4 4 --color_blocks off
	echo

	#	show_git_log_all
}

function check_inDir_size() {
	local SELECT_DIR=""
	local pre_dir=$(pwd)

	echo -e "\n${RUN} check_inDir_size"

	if [ $# -eq 1 ]; then
		if [ "$1" == "?" ]; then
			cd ~/
			SELECT_DIR=$(fzf ${FZF_SETTING} \
				--preview "cat -n {}" \
				--header "[ Select Dir to Check Size ]")
			if [ ! "${SELECT_DIR}" == "" ]; then
				echo -e "* SearchDir : ${cGreen}$(dirname ${SELECT_DIR})${cReset}\n"
				du -kh $(dirname ${SELECT_DIR}) --max-depth=1
			fi
			cd ${pre_dir}
		elif [ -d "$1" ]; then
			echo -e "* SearchDir : ${cGreen}$1${cReset}\n"
			du -kh $1 --max-depth=1
			echo
		else
			echo -e "${NOTICE} $1 not exist.\n"
		fi
		return
	fi

	echo -e "* SearchDir : ${cGreen}$(pwd)${cReset}\n"
	du -kh --max-depth=1
	echo
}

function show_package_list() {
	if [ ! "$1" == "" ]; then
		dpkg -l | grep $1
	else
		dpkg -l
	fi
}

function solve_gitPull_conflict() {
	local moveList=()
	local checkList=()
	local selectFile=""
	local pre_dir=$(pwd)
	local CUR_BACKUP_DATE=$(date +%m%d)
	local CUR_BACKUP_TIME=$(date +%H%M)
	local check_format='\.c|Makefile|makefile|\.ini|\.h|\.sh|\.xml'
	local prevFile=""
	local fixedFile=""

	local CUR_PROJECT=${NOW_PROJECT}
	local PROJECT_NAME=$(project_version_name)
	local rootDir=$(echo -e ${HOME}/blackbox/${PROJECT_NAME})

	echo -e "\n${RUN} solve_gitPull_conflict"
	echo -e "${NOTICE} You Need Match Project to SolveConflict [ Cur : ${cYellow}${CUR_PROJECT}${cReset} ]"

	if [ ! -d "${TEMP_BACKUP_CONFILICT_FILES}" ]; then
		echo -e "${NOTICE} TEMP_BACKUP_CONFILICT_FILES dir not exist. make dir."
		mkdir ${TEMP_BACKUP_CONFILICT_FILES}
	fi

	if [ ! -d "${TEMP_BACKUP_CONFILICT_FILES}/${CUR_BACKUP_DATE}_${CUR_BACKUP_TIME}" ]; then
		echo -e "${SET} Create BackupDir : ${cGreen}${TEMP_BACKUP_CONFILICT_FILES}/${CUR_BACKUP_DATE}_${CUR_BACKUP_TIME}${cReset}"
		mkdir ${TEMP_BACKUP_CONFILICT_FILES}/${CUR_BACKUP_DATE}_${CUR_BACKUP_TIME}
	fi

	echo -e "\n( Tab : Select File / Enter : Finish / Esc : Exit )"

	cd ${rootDir}
	selectFile=$(fzf ${FZF_SETTING} \
		--preview "cat -n {}" \
		--header "[ File select:TAB / Finish:Enter / Cancel:ESC ]")

	moveList+=(${selectFile})

	echo -e "\n${RUN} Move ${#moveList[@]} Files"

	if [ "${#moveList[@]}" == "0" ]; then
		echo -e "${NOTICE} solve_gitPull_conflict Canceled.\n"
		return
	fi

	for i in ${!moveList[@]}; do
		cp -avi ${moveList[i]} ${TEMP_BACKUP_CONFILICT_FILES}/${CUR_BACKUP_DATE}_${CUR_BACKUP_TIME}
		git checkout -- ${rootDir}/${moveList[i]}
	done

	manage_git_pull

	cd ${TEMP_BACKUP_CONFILICT_FILES}/${CUR_BACKUP_DATE}_${CUR_BACKUP_TIME}
	checkList+=($(ls))

	resize -s 24 160 >/dev/null

	for i in ${!checkList[@]}; do
		prevFile=""
		prevFile=$(echo -e ${checkList[i]} | grep -E ${check_format})
		if [ ! "${prevFile}" == "" ]; then
			fixedFile=""
			for j in ${!moveList[@]}; do
				fixedFile=$(echo -e ${moveList[j]} | grep -E ${prevFile})
				if [ ! "${fixedFile}" == "" ]; then
					echo -e "* File Matching  : '${cGreen}${prevFile}${cReset}' -> ${rootDir}/${fixedFile}"
					meld ./${prevFile} ${rootDir}/${fixedFile}
					break
				fi
			done
		else
			echo -e "* Invalid Format : '${cYellow}${checkList[i]}${cReset}' is Not Valid Format"
		fi
	done

	echo -e "\n${DONE} solve_gitPull_conflict\n"
	cd ${pre_dir}
}

function open_git_cola() {
	local PROJECT_LIST=(${PROJECT_LIST[@]})

	local is_valid_arg="false"
	local temp_select=""
	local SELECT_PROJECT=""

	# Check Var is valid
	if [ $# -ge 1 ]; then
		temp_select=$(echo -e $1 | tr "[:upper:]" "[:lower:]")
		for each in ${PROJECT_LIST[@]}; do
			if [ "${temp_select}" == "${each}" ]; then
				is_valid_arg="true"
				break
			fi
		done

		if [ "${is_valid_arg}" == "false" ]; then
			echo -e "${NOTICE} Not Valid Argument.\n"
			return
		fi
	fi

	# Choose Project to Change
	if [ "${is_valid_arg}" == "true" ]; then
		# Set Change Project when recv Correct Arg
		SELECT_PROJECT=$(echo -e ${temp_select} | tr "[:upper:]" "[:lower:]")
	else
		SELECT_PROJECT=$(project_version_name)
	fi

	echo -e "${RUN} open_git_cola [ ${cYellow}$SELECT_PROJECT${cReset} ]"

	git-cola -r ${HOME}/blackbox/${SELECT_PROJECT}
}

function show_git_log() {
	local PROJECT_NAME=$1
	local LOWER_PJ_NAME=$(echo -e ${PROJECT_NAME} | tr "[:upper:]" "[:lower:]")
	local PDIR="${HOME}/blackbox/${LOWER_PJ_NAME}"

	local check_day=$2
	test x"$check_day" == x && check_day=1

	echo -e " ===== ${cBold}${cGreen}${PROJECT_NAME}${cReset} Project Git Log Until ${cBold}$check_day Days${cReset} ============================================================"

	cd ${PDIR}
	git log --color --pretty=format:'%<(2)%C(bold blue)[%>(9) %cr ]%C(reset) - %<(9)%s %C(bold green)/ %an %C(reset)' --since=$check_day.Days
	echo -e " =================================================================================================="

	echo
}

function show_git_log_all() {
	local pre_dir=$(pwd)
	resize -s 40 150 >/dev/null
	local check_day=1

	local input_val=$1
	local check_val=${input_val//[0-9]/}

	if [ -z "$check_val" ]; then
		check_day=$input_val
	else
		echo -e "${ERROR} '$input_val' is not number."
		return
	fi

	echo

	for each in ${PROJECT_LIST[@]}; do
		show_git_log $each $check_day
	done

	cd $pre_dir
}

function show_git_status() {
	local PROJECT_NAME=$1
	local LOWER_PJ_NAME=$(echo -e ${PROJECT_NAME} | tr "[:upper:]" "[:lower:]")
	local PDIR="${HOME}/blackbox/${LOWER_PJ_NAME}"

	cd ${PDIR}

	echo -e "${RUN} Git Pull - ${cGreen}${PROJECT_NAME}${cReset}"
	echo -e "===================================================================================="
	git status -b | head -2
	echo -e "------------------------------------------------------------------------------------"
	git status -uno | grep -E "Makefile|makefile|\.c$|\.cpp$|\.h$|\.sh|\.ini|\.xml$"
	echo -e "===================================================================================="
	echo
}

function show_git_status_all() {
	local pre_dir=$(pwd)

	for each in ${PROJECT_LIST[@]}; do
		show_git_status $each
	done

	cd $pre_dir
}

function search_tree() {

	check_installed_package python3
	if [ "$?" -gt 0 ]; then
		echo -e "${NOTICE} : Sorry. that function need ${cGreen}python3${cReset} Package"
		echo -e "- sudo apt-get install python3"
		return
	fi

	if [ ! -e ${EXT_SEARCH_TREE} ]; then
		echo -e "${NOTICE} There are no files to support that feature - ${cYellow}${EXT_SEARCH_TREE}${cReset}"
		return
	fi

	if [ "$1" == "kernel" ]; then
		if [ $# -eq 2 ]; then
			/bin/python3 ${EXT_SEARCH_TREE} kernel $2
		else
			/bin/python3 ${EXT_SEARCH_TREE} kernel None
		fi
	else
		/bin/python3 ${EXT_SEARCH_TREE} $1
	fi

	if [ -e ${EXTENSIONS_DIR}/${SEARCH_TREE_LOG} ]; then
		local openDir=$(cat ${EXTENSIONS_DIR}/${SEARCH_TREE_LOG})
		echo -e ${SET} "Oepn Dir : ${cGreen}$openDir${cReset}\n"
		nautilus $openDir
	fi
}

function show_patch_log() {
	local pre_dir=$(pwd)
	resize -s 40 150 >/dev/null

	if [ -e "${HOME}/MkTool" ]; then
		cd ${HOME}/MkTool
		git pull --quiet
	else
		cd ${HOME}
		git clone --quiet ${GitAddress}
	fi

	if [ $? -gt 0 ]; then
		cd ${HOME}
		git clone --quiet ${GitAddress}
	fi

	cd ${HOME}/MkTool

	echo -e "\n ===== ${cBold}${cGreen}mkTool${cReset} Project Git Log${cReset} ============================================================"
	git log --color --pretty=format:'%<(2)%C(bold blue)[%>(9) %cr ]%C(reset) - %<(9)%s %C(bold green)/ %an %C(reset)' echo -e " =========================================================================================\n"

	cd ${pre_dir}
}

function unpack_fw_file() {
	local pre_dir=$(pwd)
	local project_name=$(project_version_name)
	local SELECT_FILE=

	echo -e "\n${RUN} unpack_fw_file"

	check_installed_package fzf
	if [ $? -gt 0 ]; then
		show_how_install_fzf
		return
	fi

	local TARGET_DIR="${HOME}/tftpboot/gnet_${project_name}"

	cd ${TARGET_DIR}/fw_install
	SELECT_FILE=$(find . -maxdepth 1 -type f |
		fzf --cycle --height 30% --reverse --border \
			--header "[ Select .arm file to unpack ]")

	if [ "${SELECT_FILE}" == "" ]; then
		echo -e "${NOTICE} unpack_fw_file cancel"
		return
	fi

	echo -e "================================================="
	echo $SELECT_FILE
	echo -e "================================================="

	local UNPACK_DIR=$(basename ${SELECT_FILE} | awk -F '.' '{printf $1}')

	if [ -d "${TARGET_DIR}/Unpack" ]; then
		if [ -d "${TARGET_DIR}/Unpack/$UNPACK_DIR" ]; then
			echo -e $SET Already Exist Same .arm Dir
		else
			mkdir ${TARGET_DIR}/Unpack/$UNPACK_DIR
		fi
	else
		mkdir ${TARGET_DIR}/Unpack
		mkdir ${TARGET_DIR}/Unpack/$UNPACK_DIR
	fi

	cp -a ${HOME}/blackbox/system/trfw/trfw ${TARGET_DIR}/Unpack/$UNPACK_DIR/
	cd ${TARGET_DIR}/Unpack/$UNPACK_DIR

	echo
	echo -e $RUN Unpacking...
	./trfw -r ${TARGET_DIR}/fw_install/${SELECT_FILE}

	echo
	echo -e $RUN Unzip Files...
	echo -e "================================================="
	tar -xvf ./temp_fw_gnet.arm
	echo -e "=================================================\n"

	rm ./temp_fw_gnet.arm ./trfw
	echo -e $DONE unpack_fw_file
	echo

	nautilus .
	cd $pre_dir
}

function davo_macro_tool() {
	CUR_DIR=$(pwd)
	# cd ~/

	if [ $# -eq 0 ]; then
		davo_macro_help

	elif [ $# -ge 1 ]; then
		case $1 in
		tag)
			cscope -Rbq
			ctags -R
			;;
		ap)
			davo_macro_ap_connect
			;;
		df | diff)
			davo_macro_diff $2 $3 $4
			;;
		dk)
			docker_open
			;;
		std)
			standard_management
			;;
		.)
			#				make_update_file . $2
			;;
		c)
			if [ $# -eq 1 ]; then
				make clean
			elif [ "$2" == "." ]; then
				cd ${CUR_DIR}
				make clean
			fi
			;;
		i)
			if [ $# -eq 1 ]; then
				make install
			elif [ "$2" == "." ]; then
				cd ${CUR_DIR}
				make install
			else
				make_update_file $2
			fi
			;;
		ci)
			if [ $# -eq 1 ]; then
				make clean install
			elif [ "$2" == "." ]; then
				cd ${CUR_DIR}
				make clean install
			else
				make_update_file $2 cleanInstall
			fi
			;;
#		a)
#			if [ $# -eq 1 ]; then
#				make_update_file . mkAppOnly
#			else
#				make_update_file $2 mkAppOnly
#			fi
#			;;
		r)
			./release.sh
			;;
		dir)
			make make_dir
			;;
		help | -h)
			davo_macro_help
			;;
		list | -l | \?)
			visualized_mkapp_list $2
			;;
		title | \!)
			visualized_mkapp_list title
			;;
		set | setting | -s)
			change_project $2
			;;
		bu | backup)
			git_stash_save_backup_file
			;;
		load)
			git_stash_apply_backup_file
			;;
		opt | -o | option)
			setting_option
			;;
		cp)
			send_file_to_tftp $2
			;;
		cpsv)
			send_file_to_http
			;;
		clear)
			#manage_dir_clear ${@:2}
			tftp_dir_clear
			;;
		store)
			fw_install_dir_backup
			;;
		open)
			cd ${CUR_DIR}
			mk_open_dir $2
			;;
		update)
			update_mk_file
			;;
		upp | update_package)
			update_package_version
			;;
		ver | version | verison)
			version_info
			;;
		nfs)
			setting_nfs
			;;
		sd_copy)
			sd_copy_file
			;;
		pull)
			manage_git_pull ${@:2}
			;;
		pull_all)
			manage_git_pull all
			;;
		kill | kill_terminal)
			kill_all_terminal $2
			;;
		show)
			show_info
			;;
		init)
			update_package_version
			#				manage_git_pull all
			#				code #vscode
			davo_macro_ap_connect
			show_info
			;;
		size)
			cd ${CUR_DIR}
			check_inDir_size $2
			;;
		package_list | plist)
			show_package_list $2
			;;
		solve_conflict | solve)
			solve_gitPull_conflict
			;;
		git_cola | gc)
			open_git_cola $2
			;;
		log)
			show_git_log_all $2
			;;
		tree)
			search_tree $2
			;;
		ktree)
			search_tree kernel $2
			;;
		status)
			show_git_status_all
			;;
		patch_log)
			show_patch_log
			;;

		skin)
			nfs_skin_copy
			;;
		unpack)
			unpack_fw_file
			;;
		*)
			#				make_update_file $1 $2
			;;
		esac
	fi

	cd ${CUR_DIR}
}

#alias mk='make_update_file_tool'

alias dv='davo_macro_tool'

# ================================================================= #
#                          Global Aliases                           #
# ================================================================= #

alias sc='f() {
			source ~/.bashrc;
			echo -e "${DONE} Source ~/.bashrc Complete "; }; f'

alias x='exit'
alias t='gnome-terminal --working-directory="$(pwd)"'

# alias st='strip_file'
# alias get_idf='. $HOME/ESP/esp-idf/export.sh'
# alias get_42_if='. $HOME/ESP/esp_4_2/esp-idf/export.sh'
alias mm='make clean; make; make install;'

function show_alias() {
	echo -e " =============================="
	cat $1 | grep -n ^alias | awk -F 'alias ' '{print $2}' | awk -F '=' '{print " - " $1}'
	echo -e " ==============================\n"
}

# show alias list
alias al='f() {
			echo -e "\n "`HEAD .bashrc`;
			show_alias ~/.bashrc;
			echo -e "\n "`HEAD .bash_aliases`;
			show_alias ~/.bash_aliases; }; f'

# Personal Function
function strip_file() {
	local FileList=()
	FileList+=($(ls -R))
	CUR_DIR=
	VAR=

	for each in ${FileList[@]}; do
		if [[ "${each}" =~ "./" ]]; then
			CUR_DIR=${each/:/\/}
			continue
		fi

		VAR=$(file ${CUR_DIR}${each} | grep "not stripped")
		if [ -n "${VAR}" ]; then
			${CROSS_COMPILE}strip --strip-unneeded ${CUR_DIR}${each}
			if [ $? -gt 0 ]; then
				echo -e "[ \x1b[31mStip File Failed\x1b[0m ] - ${CUR_DIR}${each}"
				continue
			fi
			echo -e "[ \x1b[32mStip File\x1b[0m ] - ${CUR_DIR}${each}"
		else
			echo -e "${CUR_DIR}${each} not a suitable format to run strip"
		fi
		VAR=
	done
}

# alias st='strip_file'

sst() {
	# 강조할 확장자 목록
	highlight_ext="c|h|sh|config|cpp|hpp|java|js|bash|zsh|yml|yaml|mk|md|txt"

	# 임시 파일 생성
	temp_file=$(mktemp)
	filtered_temp=$(mktemp)
	svn status >"$temp_file"

	# 필터링: 강조/회색 처리 기준 외 파일 및 불필요 확장자 제거
	awk -v ext="$highlight_ext" '
        $1 == "M" || $1 == "A" || $1 == "?" {
            if ($2 !~ /\.py$|\.mod$|\.mod.c|\.xml$|\.m4$|\.in$|\.cmm$|\.sub$|\.guess$/ &&
                ($2 ~ "\\.(" ext ")$" || $2 ~ /[가-힣]/))
                print $1, $2
        }' "$temp_file" >"$filtered_temp"

	# 파일 개수에 따라 병렬 작업 개수 조정
	num_files=$(wc -l <"$filtered_temp")
	parallel_jobs=$((num_files / 100 + 1))

	# 파일 수정 정보 가져오기, +0900 및 나노초 제거
	echo "=== 날짜별로 정리된 SVN 상태 ==="
	awk '{print $1, $2}' "$filtered_temp" | while read -r status file; do
		ls -l --time-style="+%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null | awk -v status="$status" '
        {
            file_date = $6;
            file_time = $7;
            file_name = $8;
            print file_date, file_time, status, file_name;
        }'
	done | sort -k1,1 -k2,2 | while read -r date time status file; do
		# 상태별 색상 구분 및 간단한 텍스트 사용
		if [[ $status == "M" ]]; then
			echo -e "\033[1;36m$date $time [Mod]: $file\033[0m" # 밝은 청록색
		elif [[ $status == "A" ]]; then
			echo -e "\033[1;32m$date $time [Add]: $file\033[0m" # 밝은 초록색
		elif [[ $status == "?" ]]; then
			echo -e "\033[1;33m$date $time [New]: $file\033[0m" # 밝은 노란색
		else
			echo -e "\033[1;90m$date $time [Unknown]: $file\033[0m" # 어두운 회색
		fi
	done

	echo ""
	echo "=== SVN 상태 확인 중 (기본 출력: svn st -q) ==="
	# svn st -q 결과도 필터링
	svn status -q | awk '$2 !~ /\.m4$|\.in$|\.cmm$|\.sub$|\.guess$/'

	# 임시 파일 삭제
	rm -f "$temp_file" "$filtered_temp"
}

function scr() {
	local revision="$1" # 리비전 번호
	local filepath="$2" # 원본 파일 경로

	# 원본 파일명과 확장자 분리
	local filename=$(basename -- "$filepath")
	local extension="${filename##*.}" # 확장자 추출
	local basename="${filename%.*}"   # 확장자 제외한 파일명 추출

	# 리비전 번호를 포함한 새로운 파일명 생성
	local new_filename
	if [[ "$filename" == "$extension" ]]; then
		# 확장자가 없는 경우
		new_filename="${basename}_r${revision}"
	else
		# 확장자가 있는 경우
		new_filename="${basename}_r${revision}.${extension}"
	fi

	# svn cat 명령 실행하여 파일 생성
	svn cat -r "$revision" "$filepath" >"$new_filename"

	# 결과 출력
	echo "Saved as $new_filename"
}

function scd() {
	local pattern="_r[0-9]+" # 리비전 번호가 포함된 파일명 패턴

	# 해당 디렉토리에서 패턴에 맞는 파일 제거
	find . -type f -regextype posix-extended -regex ".*${pattern}.*" -exec rm -v {} +

	echo "All revision files matching the pattern '${pattern}' have been removed."
}

#cvt
clean_vim_temp() {
	# 기본값: 하위 디렉토리를 포함한 검색
	local recursive=true

	# 옵션 처리: '.'이 인자로 전달되면 현재 디렉토리만 검색
	if [[ "$1" == "." ]]; then
		recursive=false
	fi

	# 검색 범위 설정
	local files
	if [ "$recursive" = false ]; then
		# 현재 디렉토리만 검색
		files=$(find . -maxdepth 1 -type f -name "*.sw*" 2>/dev/null)
	else
		# 하위 디렉토리 포함 검색
		files=$(find . -type f -name "*.sw*" 2>/dev/null)
	fi

	# 파일이 없을 경우 메시지 출력 후 종료
	if [ -z "$files" ]; then
		echo "선택한 디렉토리에 *.sw* 파일이 없습니다."
		return
	fi

	# 파일 리스트 출력
	echo "다음 *.sw* 파일이 발견되었습니다:"
	echo "$files"
	echo

	# 삭제 여부 확인 (한글 메시지와 y/Y 처리 추가)
	read -p "이 파일들을 삭제하시겠습니까? (y/n): " confirm

	if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
		echo "$files" | xargs rm -f
		echo "파일이 삭제되었습니다."
	else
		echo "파일이 삭제되지 않았습니다."
	fi
}

function vim() {
	local arg="$1"
	if [[ "$arg" =~ ^([^:]+):([0-9]+)$ ]]; then
		command vim +"${BASH_REMATCH[2]}" "${BASH_REMATCH[1]}"
	else
		command vim "$@"
	fi
}

function cptftp() {
    if [ "$#" -eq 0 ]; then
        echo "사용법: cptftp <파일>..." >&2
        return 1
    fi
    cp -a "$@" /tftpboot/
}

dv_svn_diff_export() {
    local usb_root="${USB_ROOT:-/media/$USER/KSC_USB}"
    local base_path="$(pwd)"
    local folder_name="$(basename "$base_path")"
    local timestamp="$(date +%Y%m%d_%H%M)"
    local export_dir="$usb_root/${folder_name}_$timestamp"
    local list_file="$export_dir/modified_files.txt"

    # USB 경로 확인
    if [ ! -d "$usb_root" ]; then
        echo "🔴 USB 경로가 존재하지 않습니다: $usb_root"
        return 1
    fi

    mkdir -p "$export_dir"

    echo "🔵 변경 파일 목록 생성 중..."
    svn st -q | awk '{print $2}' > "$list_file"

    echo "🟢 변경 파일 복사 중..."
    while IFS= read -r rel_path; do
        src="$base_path/$rel_path"
        dst="$export_dir/$rel_path"
        dst_dir="$(dirname "$dst")"

        mkdir -p "$dst_dir"
        cp -a "$src" "$dst"
    done < "$list_file"

    echo "✅ 완료: $export_dir 에 파일 및 목록이 복사됨"
}

open_latest_build_hlos_log() {
    local BASE_DIR="$(get_proj_dir turbo)/build_log"
    # 가장 최근에 수정된 디렉토리 찾기
    local LATEST_DIR=$(find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -n | tail -1 | cut -d' ' -f2-)

    if [ -z "$LATEST_DIR" ]; then
        echo "최신 폴더를 찾을 수 없습니다."
        return 1
    fi

    local TARGET_LOG="$LATEST_DIR/build_hlos.log"
    if [ -f "$TARGET_LOG" ]; then
        vim "$TARGET_LOG"
    else
        echo "$TARGET_LOG 파일이 없습니다."
        return 1
    fi
}

logic() {
  echo "${ROOT_PW}" | sudo -S "$HOME/문서/Logic-2.4.29-linux-x64.AppImage" --no-sandbox &
}



minicom() {
	sudo -kS minicom -s
}

# svn diff (sdf)를 DV_SVN_DIFF_TOOL 설정에 따라 실행
function sdf() {
    # DV_SVN_DIFF_TOOL 변수는 .bash_functions에서 로드됩니다.
    # 'sdft' 명령으로 변경할 수 있습니다.
    local tool="$DV_SVN_DIFF_TOOL"

    case "$tool" in
    meld)
        echo "INFO: ($tool) svn diff --diff-cmd meld 실행"
        svn diff --diff-cmd meld "$@"
        ;;
    vscode)
        echo "INFO: ($tool) svn diff --diff-cmd code --extensions \"--diff -r\" 실행"
        svn diff --diff-cmd code --extensions "--diff -r" "$@"
        ;;
    vimdiff)
        echo "INFO: ($tool) svn diff --diff-cmd vimdiff 실행"
        svn diff --diff-cmd vimdiff "$@"
        ;;
    bcompare)
        echo "INFO: ($tool) svn diff --diff-cmd bcompare 실행"
        svn diff --diff-cmd bcompare "$@"
        ;;
    *)
        # $tool 값이 비어있거나 인식되지 않을 경우
        echo "INFO: (기본) svn diff 실행"
        command svn diff "$@"
        ;;
    esac
}

# SVN Diff Tool (sdf) 설정 함수
function sdft() {
    local tools=("meld" "vscode" "vimdiff" "bcompare")
    local current_tool="$DV_SVN_DIFF_TOOL"

    echo -e "📌 현재 SVN Diff 도구: [\033[1;32m$current_tool\033[0m]"

    # fzf로 도구 선택
    local tool=$(printf "%s\n" "${tools[@]}" | fzf --prompt="SVN Diff 도구 선택: " --print-query | tail -1)

    if [[ -z "$tool" ]]; then
        echo "❗ 선택 취소됨"
        return 1
    fi

    # save_to_bash_functions 함수 [cite: 138]를 사용하여 설정 저장
    if [[ " ${tools[@]} " =~ " ${tool} " ]]; then
        save_to_bash_functions "DV_SVN_DIFF_TOOL" "$tool"
    else
        echo "❗ [$tool] 은(는) 유효하지 않은 도구입니다."
    fi
}

function csdf() {
	svn diff --diff-cmd code --extensions "--diff -r" "$@"
}

# 프로젝트명+디렉토리명 조합으로 디렉토리 이동 (예: 13.0dvmgmt, 012dnsmasq)
function pjcd() {
	local input="$1"
	local project_name dir_name project_dir source_dir target_dir final_path
	local alias_file="$HOME/.bash_aliases"
	local alias_pattern alias_path
	
	if [ -z "$input" ]; then
		echo "사용법: pjcd <프로젝트명><디렉토리명> (예: 13.0dvmgmt, 012dnsmasq)"
		return 1
	fi
	
	if [[ ! "$input" =~ ^([0-9]+\.?[0-9_]*|012|609|704|501|901|turbo|usen)([a-zA-Z0-9_]+)$ ]]; then
		echo "❌ 잘못된 형식입니다. 예: 13.0dvmgmt, 012dnsmasq"
		return 1
	fi
	
	project_name="${BASH_REMATCH[1]}"
	dir_name="${BASH_REMATCH[2]}"
	
	case "$project_name" in
		"13.0"|"13_0") project_name="13_0" ;;
		"13.1"|"13_1") project_name="13_1" ;;
		"12.4"|"12_4") project_name="12_4" ;;
		"12.5"|"12_5") project_name="12_5" ;;
	esac
	
	project_dir=$(get_proj_dir "$project_name" 2>/dev/null)
	if [ -z "$project_dir" ]; then
		echo "❌ 프로젝트 '$project_name'를 찾을 수 없습니다."
		return 1
	fi
	
	case "$project_name" in
		"turbo") source_dir="$project_dir/Pinnacles_apps/apps_proc/owrt" ;;
		*) source_dir="$project_dir" ;;
	esac
	
	case "$project_name" in
		"012") target_dir="$source_dir/build_dir/target-aarch64_cortex-a53_musl-1.1.16" ;;
		"12_4"|"12_5") target_dir="$source_dir/build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi" ;;
		"609"|"13_0"|"13_1") target_dir="$source_dir/build_dir/target-arm_cortex-a7+neon-vfpv4_musl_eabi" ;;
		"704") target_dir="$source_dir/build_dir/target-arm" ;;
		"turbo") target_dir="$source_dir/build_dir/target-aarch64_cortex-a53_musl" ;;
		*) target_dir="$source_dir/build_dir/target-arm" ;;
	esac
	
	if [ -f "$alias_file" ]; then
		alias_pattern=$(grep "^alias.*${dir_name}" "$alias_file" 2>/dev/null | head -1)
		[ -z "$alias_pattern" ] && alias_pattern=$(grep -E "^alias [\"']${dir_name}[\"']=" "$alias_file" 2>/dev/null | head -1)
		
		if [ "${#alias_pattern}" -gt 0 ]; then
			alias_path=$(echo "$alias_pattern" | sed -E "s/^alias [^=]+=['\"]?cd //; s/['\"]?$//")
			alias_path=$(echo "$alias_path" | sed "s|\$SOURCE_DIR|$source_dir|g" | sed "s|\$TARGET_DIR|$target_dir|g")
			
			while echo "$alias_path" | grep -q '\$(get_proj_dir'; do
				local proj_in_path=$(echo "$alias_path" | sed -n 's/.*$(get_proj_dir \([^)]*\)).*/\1/p')
				[ -z "$proj_in_path" ] && break
				local proj_path=$(get_proj_dir "$proj_in_path" 2>/dev/null)
				[ -z "$proj_path" ] && break
				alias_path=$(echo "$alias_path" | sed "s|\$(get_proj_dir $proj_in_path)|$proj_path|g")
			done
			
			if echo "$alias_path" | grep -q '\*'; then
				if echo "$alias_path" | grep -q "^$target_dir/[^/]*\*"; then
					local pattern=$(echo "$alias_path" | sed "s|^$target_dir/||")
					local dir_pattern=$(echo "$pattern" | sed 's/\*.*$//')
					final_path=$(find "$target_dir" -maxdepth 1 -type d -name "${dir_pattern}*" 2>/dev/null | head -1)
				else
					local find_pattern=$(echo "$alias_path" | sed "s|\*|[^/]*|g")
					final_path=$(find "$target_dir" -type d -path "$find_pattern" 2>/dev/null | head -1)
				fi
			else
				final_path="$alias_path"
			fi
		fi
	fi
	
	if [ -z "$final_path" ]; then
		case "$dir_name" in
			"target") final_path="$target_dir" ;;
			"dvmgmt") final_path="$target_dir/dv_pkg/dvmgmt" ;;
			"dualnat") final_path="$target_dir/dv_pkg/kernel/dualnat" ;;
			"dnsmasq") final_path=$(find "$target_dir" -type d -path "*/dnsmasq*/dnsmasq*/src" 2>/dev/null | head -1) ;;
			"udhcp") final_path=$(find "$target_dir" -type d -path "*/busybox*/*/networking/udhcp" 2>/dev/null | head -1) ;;
			"hostap")
				case "$project_name" in
					"012") final_path="$target_dir/qca-hostap-supplicant-default/qca-hostap-g/src" ;;
					"13_0"|"13_1"|"609") final_path="$target_dir/qca-hostap-qca-hapd-supp-full/qca-hostap-g/src" ;;
					*) final_path=$(find "$target_dir" -type d -path "*/qca-hostap*/qca-hostap*/src" 2>/dev/null | head -1) ;;
				esac ;;
			*)
				echo "❌ 알 수 없는 디렉토리명: '$dir_name'"
				echo "💡 .bash_aliases에 해당 alias가 정의되어 있는지 확인하세요."
				return 1 ;;
		esac
	fi
	
	if [ -z "$final_path" ] || [ ! -d "$final_path" ]; then
		[ -z "$final_path" ] && echo "❌ 경로를 찾을 수 없습니다: $project_name/$dir_name"
		[ -n "$final_path" ] && echo "❌ 디렉토리가 존재하지 않습니다: $final_path"
		return 1
	fi
	
	cd "$final_path" || return 1
	echo "✅ 이동: $final_path"
}

generate_project_aliases() {
	local alias_file="$HOME/.bash_aliases"
	local projects=("012" "609" "13_0" "13_1" "12_4" "12_5" "704" "501" "901" "turbo" "usen")
	local in_section=0
	local alias_names=()
	local cache_file="$HOME/.bash_aliases_project_gen"
	local tmp_file=""
	
	[ ! -f "$alias_file" ] && return
	
	while IFS= read -r line; do
		[[ "$line" =~ ^#.*전.*프로젝트 ]] && in_section=1 && continue
		[ "$in_section" -eq 1 ] && [[ "$line" =~ ^if[[:space:]]+\[\[ ]] && break
		
		if [ "$in_section" -eq 1 ] && [[ "$line" =~ ^alias[[:space:]]+[\'\"]([a-zA-Z0-9_]+)[\'\"]= ]]; then
			local alias_name="${BASH_REMATCH[1]}"
			[[ ! "$alias_name" =~ ^[0-9]+$ ]] && alias_names+=("$alias_name")
		fi
	done < "$alias_file"
	
	tmp_file="${cache_file}.tmp.$$"
	{
		printf "# autogenerated by ~/.bash_functions (generate_project_aliases)\n"
		printf "# source: %s\n" "$alias_file"
		for project in "${projects[@]}"; do
			for alias_name in "${alias_names[@]}"; do
				local project_alias=""
				case "$project" in
					"13_0") project_alias="13.0${alias_name}" ;;
					"13_1") project_alias="13.1${alias_name}" ;;
					"12_4") project_alias="12.4${alias_name}" ;;
					"12_5") project_alias="12.5${alias_name}" ;;
					*) project_alias="${project}${alias_name}" ;;
				esac
				printf "alias '%s'='%s'\n" "$project_alias" "pjcd $project_alias"
			done
		done
	} > "$tmp_file"
	mv -f "$tmp_file" "$cache_file" 2>/dev/null
	[ -f "$cache_file" ] && source "$cache_file" 2>/dev/null
}

# 성능 최적화: .bash_aliases가 변경되었을 때만 캐시 파일을 재생성하고, 매번 캐시를 source
ALIAS_GEN_FILE="$HOME/.bash_aliases_project_gen"
if [ ! -f "$ALIAS_GEN_FILE" ] || [ "$ALIAS_GEN_FILE" -ot "$HOME/.bash_aliases" ] 2>/dev/null; then
	generate_project_aliases
else
	source "$ALIAS_GEN_FILE" 2>/dev/null
fi

# file_to_dev — AP 파일 전송 도구 (dv up / dv file 통합)
[ -f "$HOME/KscTool/ftd/file_to_dev.sh" ] && source "$HOME/KscTool/ftd/file_to_dev.sh"

# cpbak — SVN/Git 수정 파일 백업 & 원복 도구
[ -f "$HOME/KscTool/cpbak/cpbak.sh" ] && source "$HOME/KscTool/cpbak/cpbak.sh"

# ================================================================= #
#                    KscTool 미설치 안내 (fallback)                  #
# ================================================================= #
# @desc 커맨드 목록 조회 — dvhelp [키워드]
function dvhelp() {
    local script="$HOME/KscTool/tools/dvhelp.sh"
    if [[ -f "$script" ]]; then
        bash "$script" "$@"
    else
        _ksc_setup_hint "dvhelp"
    fi
}
# KscTool이 없을 때 관련 명령어 호출 시 설치 안내를 출력한다.
# KscTool이 설치되면 위의 source 구문이 먼저 실행되므로 아래 stubs는 무시된다.

_ksc_setup_hint() {
    local cmd="${1:-이 명령어}"
    echo -e ""
    echo -e "  ${cYellow}⚠  '${cmd}'은 KscTool이 필요합니다.${cReset}"
    echo -e ""
    echo -e "  ${cBold}설치 방법:${cReset}"
    echo -e "    ${cGreen}git clone https://github.com/ksc2320/KscTool.git ~/KscTool${cReset}"
    echo -e "    ${cGreen}source ~/.bashrc${cReset}"
    echo -e ""
    echo -e "  설치 후 dvhelp 로 활성화된 명령어 목록을 확인하세요."
    echo -e ""
}

if [[ ! -d "$HOME/KscTool" ]]; then
    # source로 로드되는 함수들 fallback
    function _ftd_main()   { _ksc_setup_hint "fwd (ftd)"; }
    function _cpbak_main() { _ksc_setup_hint "cpbak"; }

    # 직접 경로 alias들 fallback (bash_aliases보다 나중에 로드되므로 override 됨)
    for _ksc_cmd in scs obs ucisnap specver genindex genindex-tags genindex-bear; do
        # shellcheck disable=SC2139
        alias "$_ksc_cmd"="_ksc_setup_hint $_ksc_cmd"
    done
    unset _ksc_cmd
fi
