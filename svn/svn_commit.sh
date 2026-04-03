#!/bin/bash

# --- 스크립트 버전 ---
SCRIPT_VERSION="1.1.1"
# 스크립트 수정 시, 이 버전 번호를 올려주세요. (예: 1.0.2)
# 'upload' 명령은 이 버전을 자동으로 1.1.1, 1.1.2 등으로 올립니다.
# ---

# --- 스크립트 원본 Git 저장소 정보 ---
# update, upload, 알림 기능에 사용됩니다.
SCRIPT_REMOTE_URL="https://github.com/ksc2320/KscTool.git"
SCRIPT_FILE_NAME="svn_commit.sh" # KscTool 저장소 내의 이 스크립트 파일명
SCRIPT_GIT_BRANCH="main"
# ---

# 색깔 설정
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m' # 기본 색상

# --- 스크립트 및 전역 설정 경로 ---
# 스크립트 파일이 위치한 실제 디렉토리 (Git 저장소 루트여야 함)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
# 전역 설정 (프로젝트 경로, 업데이트 상태 저장)
GLOBAL_CONFIG_DIR="$HOME/.config/svn_commit_helper"
GLOBAL_CONFIG_FILE="$GLOBAL_CONFIG_DIR/config"
UPDATE_STATUS_FILE="$GLOBAL_CONFIG_DIR/update_status"
LAST_CHECK_FILE="$GLOBAL_CONFIG_DIR/last_check"

# --- 1. 전역 설정 관리 ---

# 1.1. 전역 설정 디렉토리 및 파일 준비
setup_global_config() {
    mkdir -p "$GLOBAL_CONFIG_DIR"
    touch "$GLOBAL_CONFIG_FILE"
    touch "$UPDATE_STATUS_FILE"
}

# 1.2. 전역 설정 로드 (PROJECT_PATH 로드)
load_global_config() {
    if [ -f "$GLOBAL_CONFIG_FILE" ]; then
        source "$GLOBAL_CONFIG_FILE"
    fi
    # PROJECT_PATH가 비어있거나 설정된 적 없으면 기본값(현재 경로)
    if [ -z "$PROJECT_PATH" ]; then
        PROJECT_PATH="."
    fi
    # 경로가 유효한지 확인
    if [ ! -d "$PROJECT_PATH" ]; then
        echo -e "${YELLOW}경고: 설정된 프로젝트 경로(${PROJECT_PATH})를 찾을 수 없습니다. 기본값(.)으로 설정합니다.${NC}"
        PROJECT_PATH="."
        set_global_setting "PROJECT_PATH" "."
    fi
}

# 1.3. 전역 설정 저장 (PROJECT_PATH 저장)
set_global_setting() {
    local key=$1
    local value=$2
    
    # 설정 파일에서 해당 키를 찾아 값 변경 (없으면 추가)
    if grep -q "^${key}=" "$GLOBAL_CONFIG_FILE"; then
        sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$GLOBAL_CONFIG_FILE"
    else
        echo "${key}=\"${value}\"" >> "$GLOBAL_CONFIG_FILE"
    fi
    echo -e "${GREEN}전역 설정 변경: ${key} = ${value}${NC}"
}

# --- 2. 프로젝트 로컬 설정 관리 ---

# 2.1. 프로젝트 설정 기본값
DEFAULT_AUTO_PREFIX="ON"
DEFAULT_JIRA_CONVERT="ON"

# 2.2. 프로젝트 설정 로드 (AUTO_PREFIX 등)
# 이 함수는 load_global_config가 실행된 *후*에 호출되어야 함
load_project_setting() {
    if [ ! -f "$SETTING_FILE" ]; then
        echo -e "${YELLOW}프로젝트 설정 파일($SETTING_FILE)이 없어 기본값으로 생성합니다.${NC}"
        echo "AUTO_PREFIX=${DEFAULT_AUTO_PREFIX}" > "$SETTING_FILE"
        echo "JIRA_AUTO_CONVERT=${DEFAULT_JIRA_CONVERT}" >> "$SETTING_FILE"
    fi

    if ! grep -q "^AUTO_PREFIX=" "$SETTING_FILE"; then
        echo -e "${YELLOW}AUTO_PREFIX 설정이 없어 추가합니다.${NC}"
        echo "AUTO_PREFIX=${DEFAULT_AUTO_PREFIX}" >> "$SETTING_FILE"
    fi
    if ! grep -q "^JIRA_AUTO_CONVERT=" "$SETTING_FILE"; then
        echo -e "${YELLOW}JIRA_AUTO_CONVERT 설정이 없어 추가합니다.${NC}"
        echo "JIRA_AUTO_CONVERT=${DEFAULT_JIRA_CONVERT}" >> "$SETTING_FILE"
    fi
    
    source "$SETTING_FILE"
}

# 2.3. 프로젝트 설정 변경 함수
set_project_setting() {
    local key=$1
    local value=$2
    
    if grep -q "^${key}=" "$SETTING_FILE"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$SETTING_FILE"
    else
        echo "${key}=${value}" >> "$SETTING_FILE"
    fi
    echo -e "${GREEN}프로젝트 설정 변경: ${key} = ${value}${NC}"
}

# --- 3. 업데이트 확인 및 알림 ---

# 3.1. 백그라운드 업데이트 확인
check_for_updates_bg() {
    ( # 서브셸에서 백그라운드로 실행
        cd "$SCRIPT_DIR"
        git fetch origin > /dev/null 2>&1
        
        # 원격 저장소와 비교
        if [[ $(git status -uno | grep "Your branch is behind") ]]; then
            # 최근 커밋 메시지 가져오기
            local log=$(git log "origin/${SCRIPT_GIT_BRANCH}" -n 1 --pretty=format:"%h - %s (%ar)")
            echo -e "${YELLOW}새 버전 발견: ${log}${NC}" > "$UPDATE_STATUS_FILE"
        else
            # 업데이트 없음, 상태 파일 비우기
            > "$UPDATE_STATUS_FILE"
        fi
        
        # 마지막 확인 시간 기록
        touch "$LAST_CHECK_FILE"
    ) &
}

# 3.2. 업데이트 알림 표시
show_update_notification() {
    if [ -s "$UPDATE_STATUS_FILE" ]; then
        echo -e "${YELLOW}----------------------------------------------------------------------${NC}"
        echo -e "${YELLOW}새로운 스크립트 버전이 있습니다. ${BOLD}'./svn_commit.sh update'${NC}${YELLOW}로 업데이트하세요.${NC}"
        cat "$UPDATE_STATUS_FILE"
        echo -e "${YELLOW}----------------------------------------------------------------------${NC}"
    fi
}

# 3.3. 업데이트 확인 트리거 (1시간(3600초)에 한 번)
trigger_update_check() {
    local now=$(date +%s)
    local last_check=0
    
    if [ -f "$LAST_CHECK_FILE" ]; then
        last_check=$(date +%s -r "$LAST_CHECK_FILE")
    fi
    
    local diff=$((now - last_check))
    
    if [ $diff -gt 3600 ]; then
        check_for_updates_bg
    fi
}


# --- 스크립트 시작 ---

# 1. 전역 설정 (PROJECT_PATH) 로드
setup_global_config
load_global_config

# 2. 프로젝트 경로 기준 변수 설정
COMMIT_FILE="$PROJECT_PATH/svn_commit_info.txt"
SETTING_FILE="$PROJECT_PATH/svn_commit.setting"

# 3. 프로젝트 설정 (AUTO_PREFIX 등) 로드
load_project_setting

# 4. 업데이트 알림 표시
show_update_notification


# --- 명령어 처리 ---

# ./svn_commit.sh version (버전 확인)
if [ "$1" == "version" ]; then
    echo -e "svn_commit.sh 버전: ${BOLD}${SCRIPT_VERSION}${NC}"
    exit 0
fi

# ./svn_commit.sh update (자가 업데이트)
if [ "$1" == "update" ]; then
    echo -e "${CYAN}스크립트 업데이트를 시도합니다... (저장소: ${SCRIPT_DIR})${NC}"

    if ! command -v git &> /dev/null; then
        echo -e "${RED}오류: 'git' 명령어를 찾을 수 없습니다. 업데이트를 진행할 수 없습니다.${NC}"
        exit 1
    fi
    
    cd "$SCRIPT_DIR" || { echo -e "${RED}스크립트 디렉토리(${SCRIPT_DIR})로 이동 실패${NC}"; exit 1; }
    
    echo -e "${CYAN}1. 원격 저장소 정보 가져오는 중... (git fetch)${NC}"
    git fetch origin
    
    if [[ ! $(git status -uno | grep "Your branch is behind") ]]; then
        echo -e "${GREEN}이미 최신 버전(${SCRIPT_VERSION})입니다.${NC}"
        > "$UPDATE_STATUS_FILE" # 상태 파일 비우기
        exit 0
    fi
    
    echo -e "${CYAN}2. 새 버전을 발견했습니다. 변경 내역:${NC}"
    git log "HEAD..origin/${SCRIPT_GIT_BRANCH}" --pretty=format:"  ${YELLOW}%h${NC} - %s ${CYAN}(%ar)${NC}"
    
    echo -e "\n${CYAN}3. 업데이트 진행 중... (git pull)${NC}"
    if git pull origin "$SCRIPT_GIT_BRANCH"; then
        echo -e "${GREEN}업데이트 완료! 스크립트를 다시 실행해주세요.${NC}"
        > "$UPDATE_STATUS_FILE" # 상태 파일 비우기
    else
        echo -e "${RED}업데이트 실패. 'git pull' 중 충돌이 발생했을 수 있습니다.${NC}"
        echo -e "수동으로 ${SCRIPT_DIR} 디렉토리에서 충돌을 해결해주세요."
    fi
    exit 0
fi

# ./svn_commit.sh upload (스크립트 배포)
if [ "$1" == "upload" ]; then
    echo -e "${CYAN}스크립트 배포를 시도합니다... (파일: ${SCRIPT_FILE_NAME})${NC}"
    
    if ! command -v git &> /dev/null; then
        echo -e "${RED}오류: 'git' 명령어를 찾을 수 없습니다.${NC}"; exit 1;
    fi

    cd "$SCRIPT_DIR" || { echo -e "${RED}스크립트 디렉토리(${SCRIPT_DIR})로 이동 실패${NC}"; exit 1; }

    # Git 저장소인지 먼저 확인
    if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        echo -e "${RED}오류: 현재 스크립트 디렉토리(${SCRIPT_DIR})가 Git 저장소가 아닙니다.${NC}"
        echo -e "'upload' 명령어는 스크립트 원본 Git 저장소 내에서만 실행할 수 있습니다."
        exit 1
    fi

    # 스크립트 파일($0)이 아닌, 저장소 내의 파일($SCRIPT_FILE_NAME) 기준
    git_status=$(git status --porcelain "$SCRIPT_FILE_NAME" 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo -e "${RED}오류: 'git status' 실행에 실패했습니다. (경로: ${SCRIPT_DIR})${NC}"
        exit 1
    fi

    if [[ -z "$git_status" ]]; then
        echo -e "${YELLOW}수정된 내용이 없습니다. (${SCRIPT_FILE_NAME})${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}스크립트 파일(${SCRIPT_FILE_NAME})에 수정 사항이 감지되었습니다.${NC}"
    read -p "수정 내역(커밋 메시지)을 한 줄로 입력하세요: " commit_msg

    if [ -z "$commit_msg" ]; then
        echo -e "${RED}커밋 메시지가 필요합니다. 중단합니다.${NC}"
        exit 1
    fi

    # 버전 자동 증가 (Patch 버전 1 증가)
    CURRENT_VERSION=$SCRIPT_VERSION
    IFS='.' read -r -a ver_parts <<< "$CURRENT_VERSION"
    new_patch=$((ver_parts[2] + 1))
    NEW_VERSION="${ver_parts[0]}.${ver_parts[1]}.$new_patch"
    
    echo -e "${CYAN}버전 자동 증가: ${CURRENT_VERSION} -> ${NEW_VERSION}${NC}"
    
    # 스크립트 파일 내의 버전 번호 수정
    sed -i "s/SCRIPT_VERSION=\"$CURRENT_VERSION\"/SCRIPT_VERSION=\"$NEW_VERSION\"/" "$SCRIPT_FILE_NAME"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}오류: 스크립트 파일 내의 버전 번호 수정에 실패했습니다.${NC}"
        echo -e "수동으로 'git reset --hard' 후 다시 시도하세요."
        exit 1
    fi
    
    echo -e "${CYAN}Git에 추가 및 커밋 중...${NC}"
    git add "$SCRIPT_FILE_NAME"
    git commit -m "$commit_msg" -m "Version: $NEW_VERSION"
    
    echo -e "${CYAN}원격 저장소로 푸시 중... (git push origin ${SCRIPT_GIT_BRANCH})${NC}"
    if git push origin "$SCRIPT_GIT_BRANCH"; then
        echo -e "${GREEN}배포 완료! (버전: ${NEW_VERSION})${NC}"
    else
        echo -e "${RED}푸시 실패. Git 설정을 확인하세요.${NC}"
    fi
    exit 0
fi

# ./svn_commit.sh setting (설정 관리 인터페이스)
if [ "$1" == "setting" ]; then
    
    # ./svn_commit.sh setting project (프로젝트 경로 설정)
    if [ "$2" == "project" ]; then
        local new_path=""
        if [ -n "$3" ]; then
            new_path="$3"
        elif command -v fzf &> /dev/null; then
            echo "현재 경로(.)에서 하위 3레벨까지의 디렉토리를 검색합니다..."
            # fzf로 디렉토리 선택 (숨김 디렉토리 제외)
            new_path=$(find . -maxdepth 3 -type d -not -path '*/\.*' | fzf --prompt="[SVN 프로젝트 경로 선택] ")
            if [ -z "$new_path" ]; then
                echo -e "${RED}선택이 취소되었습니다.${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}fzf가 설치되어 있지 않습니다. 경로를 직접 입력하세요.${NC}"
            read -p "새 프로젝트 경로 입력 (예: ./my_svn_repo): " new_path
        fi

        if [ -z "$new_path" ]; then
            echo -e "${RED}경로가 입력되지 않았습니다.${NC}"
            exit 1
        elif [ "$new_path" == "." ]; then
            echo "기본값(현재 디렉토리)으로 설정합니다."
            set_global_setting "PROJECT_PATH" "."
        elif [ -d "$new_path" ]; then
            # 상대 경로를 절대 경로로 변환하여 저장
            local abs_path=$(cd "$new_path" && pwd)
            set_global_setting "PROJECT_PATH" "$abs_path"
        else
            echo -e "${RED}존재하지 않는 디렉토리입니다: $new_path${NC}"
            exit 1
        fi
        exit 0
    fi
    
    # ./svn_commit.sh setting (설정 보기)
    if [ -z "$2" ]; then
        echo -e "${CYAN}--- 전역 설정 (${GLOBAL_CONFIG_FILE}) ---${NC}"
        echo -e "  * SVN 프로젝트 경로 (PROJECT_PATH) : ${BOLD}${PROJECT_PATH}${NC}"
        echo -e "\n${CYAN}--- 현재 프로젝트 설정 (${SETTING_FILE}) ---${NC}"
        echo -e "  1. 자동 접두사 (auto_prefix) : ${BOLD}${AUTO_PREFIX}${NC} (ON: \t• , OFF: 수동)"
        echo -e "  2. Jira 자동 변환 (jira_convert): ${BOLD}${JIRA_AUTO_CONVERT}${NC} (ON: '-' -> ':', OFF: 수동)"
        echo -e "\n${YELLOW}사용법:${NC}"
        echo -e "  ./svn_commit.sh setting project [경로] : SVN 프로젝트 경로 설정 (fzf 사용 가능)"
        echo -e "  ./svn_commit.sh setting <항목> <on|off> : 프로젝트 설정 변경"
        echo -e "    예: ./svn_commit.sh setting auto_prefix off"
        exit 0
    fi

    local key_to_set=""
    local value_to_set=""

    case "$2" in
        1 | auto_prefix)
            key_to_set="AUTO_PREFIX"
            ;;
        2 | jira_convert)
            key_to_set="JIRA_AUTO_CONVERT"
            ;;
        *)
            echo -e "${RED}알 수 없는 설정 항목입니다: $2${NC}"
            echo -e "항목: ${BOLD}auto_prefix${RED}, ${BOLD}jira_convert${NC}, ${BOLD}project${NC}"
            exit 1
            ;;
    esac

    case "$3" in
        on | ON | On)
            value_to_set="ON"
            ;;
        off | OFF | Off)
            value_to_set="OFF"
            ;;
        *)
            echo -e "${RED}값은 'on' 또는 'off' 만 가능합니다: $3${NC}"
            exit 1
            ;;
    esac
    
    set_project_setting "$key_to_set" "$value_to_set"
    exit 0
fi

# ./svn_commit.sh help (도움말 기능 추가)
if [ "$1" == "help" ]; then
    echo -e "${CYAN}--- SVN 커밋 헬퍼 스크립트 (버전: ${SCRIPT_VERSION}) ---${NC}"
    echo -e "현재 ${BOLD}${PROJECT_PATH}${NC} 경로의 프로젝트를 대상으로 작업합니다."
    
    echo -e "\n${BLUE}기본 사용 흐름:${NC}"
    echo -e "  1. ${BOLD}./svn_commit.sh setting project${NC}로 작업할 SVN 프로젝트 경로를 설정합니다. (최초 1회)"
    echo -e "  2. ${BOLD}${PROJECT_PATH}/svn_commit_info.txt${NC} 파일에 커밋 내용을 작성합니다."
    echo -e "  3. ${BOLD}./svn_commit.sh info${NC} (또는 ${BOLD}./svn_commit.sh${NC})로 미리보기를 확인합니다."
    echo -e "  4. ${BOLD}./svn_commit.sh check${NC}로 수정된 파일의 diff를 검토합니다. (선택)"
    echo -e "  5. ${BOLD}./svn_commit.sh run${NC}으로 실제 커밋을 실행합니다."

    echo -e "\n${BLUE}주요 명령어:${NC}"
    echo -e "  ${BOLD}./svn_commit.sh info${NC}    : 현재 ${BOLD}svn_commit_info.txt${NC}의 내용으로 커밋 상태와 미리보기를 표시합니다."
    echo -e "  ${BOLD}./svn_commit.sh run${NC}      : ${BOLD}svn add${NC}, ${BOLD}svn delete${NC} 및 ${BOLD}svn commit${NC}을 실행합니다."
    echo -e "  ${BOLD}./svn_commit.sh check${NC}   : ${BOLD}[MODIFY_FILE]${NC} 목록의 파일들을 순회하며 ${BOLD}svn diff${NC}를 실행합니다."
    echo -e "  ${BOLD}./svn_commit.sh clear${NC}   : ${BOLD}svn_commit_info.txt${NC}의 내용을 초기화합니다."
    
    echo -e "\n${BLUE}스크립트 관리 명령어:${NC}"
    echo -e "  ${BOLD}./svn_commit.sh setting${NC} : 전역/프로젝트 설정을 확인 및 변경합니다."
    echo -e "  ${BOLD}./svn_commit.sh help${NC}    : 지금 보고 있는 이 도움말을 표시합니다."
    echo -e "  ${BOLD}./svn_commit.sh version${NC} : 스크립트의 현재 버전을 표시합니다."
    echo -e "  ${BOLD}./svn_commit.sh update${NC}  : 이 스크립트를 Git 저장소에서 최신 버전으로 업데이트합니다."
    echo -e "  ${BOLD}./svn_commit.sh upload${NC}  : 이 스크립트의 수정본을 Git 저장소에 배포(커밋/푸시)합니다."
    
    echo -e "\n${BLUE}설정 항목 (./svn_commit.sh setting):${NC}"
    echo -e "  ${BOLD}project${NC}       : (전역) 작업할 SVN 프로젝트의 루트 경로를 지정합니다. (fzf 지원)"
    echo -e "  ${BOLD}auto_prefix${NC}  : (프로젝트) [상세 설명]의 각 줄에 자동으로 '\\t• '을 붙일지 (ON/OFF) 정합니다."
    echo -e "  ${BOLD}jira_convert${NC}: (프로젝트) [Jira 이슈]에 '이름-번호' 형식을 '이름:번호'로 자동 변환할지 (ON/OFF) 정합니다."
    exit 0
fi

# 텍스트 파일이 없으면 생성
if [ ! -f "$COMMIT_FILE" ]; then
    echo -e "${YELLOW}커밋 정보 파일($COMMIT_FILE)이 존재하지 않아 새로 생성합니다.${NC}"
    cat > "$COMMIT_FILE" << EOF
[Jira 이슈]
<Jira 이슈 번호>
(예: S1KTHOME-866 또는 S1ENTWIFI-1735)

[작업 내용]
<커밋 제목을 입력하세요 (필수)>
(예:dvmgmt 포팅)

[상세 설명]
<상세 내용을 입력하세요 (옵션)>

[ADD_FILE]

[MODIFY_FILE]

[REMOVE_FILE]
EOF
    echo -e "${GREEN}$COMMIT_FILE 생성 완료. 필요한 정보를 입력 후 다시 실행하세요.${NC}"
    exit 0
fi

# 파일 초기화 기능
if [ "$1" == "clear" ]; then
    echo -e "${YELLOW}커밋 정보를 초기화합니다. ($COMMIT_FILE)${NC}"
    cat > "$COMMIT_FILE" << EOF
[Jira 이슈]

[작업 내용]

[상세 설명]

[ADD_FILE]

[MODIFY_FILE]

[REMOVE_FILE]
EOF
    echo -e "${GREEN}초기화 완료.${NC}"
    exit 0
fi

# --- 파일 읽기 (프로젝트 경로 기준) ---
JIRA_NUMBER=$(awk '/^\[Jira 이슈\]/{getline; print}' "$COMMIT_FILE")
COMMIT_TITLE=$(awk '/^\[작업 내용\]/{getline; print}' "$COMMIT_FILE")
COMMIT_MSG=$(awk '/^\[상세 설명\]/{flag=1; next} /^\[/{flag=0} flag' "$COMMIT_FILE")
ADD_FILES=$(awk '/^\[ADD_FILE\]/{flag=1; next} /^\[/{flag=0} flag' "$COMMIT_FILE")
MODIFY_FILES=$(awk '/^\[MODIFY_FILE\]/{flag=1; next} /^\[/{flag=0} flag' "$COMMIT_FILE")
REMOVE_FILES=$(awk '/^\[REMOVE_FILE\]/{flag=1; next} /^\[/{flag=0} flag' "$COMMIT_FILE")

# Jira 이슈 형식 자동 변환
JIRA_AUTO_CONVERTED=0
if [[ "$JIRA_AUTO_CONVERT" == "ON" ]]; then
    if [[ -n "$JIRA_NUMBER" && ! "$JIRA_NUMBER" =~ \: && "$JIRA_NUMBER" =~ - ]]; then
        JIRA_NUMBER=$(echo "$JIRA_NUMBER" | sed 's/\(.*\)-/\1:/')
        JIRA_AUTO_CONVERTED=1
    fi
fi

# ./svn_commit.sh 또는 ./svn_commit.sh info
if [ -z "$1" ] || [ "$1" == "info" ]; then
    # 백그라운드 업데이트 확인 실행
    trigger_update_check
    
    echo -e "${CYAN}현재 커밋 정보 상태 (대상: ${BOLD}${PROJECT_PATH}${NC}):${NC}"

    if [[ "$JIRA_AUTO_CONVERTED" -eq 1 ]]; then
         echo -e "${BLUE}${BOLD}[Jira 이슈]:${NC} ${GREEN}$JIRA_NUMBER${NC} ${YELLOW}(-'를 ':'로 자동 변환)${NC}"
    elif [[ -z "$JIRA_NUMBER" ]]; then
         echo -e "${YELLOW}[Jira 이슈]가 비어 있습니다. (옵션)${NC}"
    else
         echo -e "${BLUE}${BOLD}[Jira 이슈]:${NC} ${GREEN}$JIRA_NUMBER${NC}"
    fi

    [[ -z "$COMMIT_TITLE" ]] && echo -e "${RED}[작업 내용]이 비어 있습니다. (필수)${NC}" || echo -e "${BLUE}${BOLD}[작업 내용]:${NC} ${GREEN}$COMMIT_TITLE${NC}"

    if [[ -z "$COMMIT_MSG" ]]; then
        echo -e "${YELLOW}[상세 설명]이 비어 있습니다. (옵션)${NC}"
    else
        echo -e "${BLUE}${BOLD}[상세 설명] (자동 접두사: $AUTO_PREFIX):${NC}"
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then 
                if [[ "$AUTO_PREFIX" == "ON" ]]; then
                    echo -e "  ${NC}- $line${NC}"
                else
                    echo -e "  ${NC}$line${NC}"
                fi
            fi
        done <<< "$COMMIT_MSG"
    fi

    # 파일 상태
    echo -e "${CYAN}파일 상태 (경로 기준: ${PROJECT_PATH}):${NC}"
    for FILE in $ADD_FILES; do
        echo -e "${BLUE}${BOLD}(A) ${FILE}${NC}"
    done
    for FILE in $MODIFY_FILES; do
        echo -e "${YELLOW}${BOLD}(M) ${FILE}${NC}"
    done
    for FILE in $REMOVE_FILES; do
        echo -e "${RED}${BOLD}(R) ${FILE}${NC}"
    done

    # 실제 로그 미리보기
    echo -e "${CYAN}실제 커밋 로그 미리보기:${NC}"
    FORMATTED_MSG=""
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            if [[ "$AUTO_PREFIX" == "ON" ]]; then
                FORMATTED_MSG+="- $line"$'\n'
            else
                FORMATTED_MSG+="$line"$'\n'
            fi
        fi
    done <<< "$COMMIT_MSG"

    if [[ -z "$JIRA_NUMBER" ]]; then
        echo -e "${BOLD}${COMMIT_TITLE}${NC}"
    else
        echo -e "${BOLD}${JIRA_NUMBER} ${COMMIT_TITLE}${NC}"
    fi
    echo -e "\n${NC}${FORMATTED_MSG}${NC}"

    echo -e "${YELLOW}모든 정보를 확인한 후 'run' 옵션으로 커밋을 진행하세요.${NC}"
    exit 0
fi

# ./svn_commit.sh check
if [ "$1" == "check" ]; then
    # 백그라운드 업데이트 확인 실행
    trigger_update_check

    echo -e "${CYAN}수정 내용 확인을 시작합니다. (대상: ${BOLD}${PROJECT_PATH}${NC})${NC}"
    
    if [[ -z "$MODIFY_FILES" ]]; then
        echo -e "${YELLOW}확인할 [MODIFY_FILE] 목록이 비어있습니다.${NC}"
        exit 0
    fi
    
    # (cd ... && ) : SVN 명령을 해당 프로젝트 경로에서 실행
    (
        cd "$PROJECT_PATH" || { echo -e "${RED}프로젝트 경로(${PROJECT_PATH})로 이동 실패${NC}"; exit 1; }
        
        for FILE in $MODIFY_FILES; do
            if [ ! -e "$FILE" ]; then # -e: 파일 또는 디렉토리
                echo -e "${RED}파일 $FILE 이 존재하지 않습니다. 건너뜁니다.${NC}"
                continue
            fi
            echo -e "${BLUE}${BOLD}파일: $FILE${NC}"
            echo -e "${CYAN}수정 내용을 확인 중...${NC}"
            svn diff "$FILE"
            read -p "다음 파일로 이동하려면 Enter를 누르세요. (중단: Ctrl+C)" CONTINUE
        done
    )
    echo -e "${GREEN}모든 파일 검토가 완료되었습니다.${NC}"
    exit 0
fi

# ./svn_commit.sh run (커밋 실행)
if [ "$1" == "run" ]; then
    # 백그라운드 업데이트 확인 실행
    trigger_update_check

    if [[ -z "$COMMIT_TITLE" ]]; then
        echo -e "${RED}[작업 내용]은 필수입니다. 정보를 채운 후 다시 실행하세요.${NC}"
        exit 1
    fi

    # (cd ... && ) : 파일 유효성 검사를 해당 프로젝트 경로에서 실행
    (
        cd "$PROJECT_PATH" || { echo -e "${RED}프로젝트 경로(${PROJECT_PATH})로 이동 실패${NC}"; exit 1; }
        
        # 파일 유효성 검사
        INVALID_FILES=()
        for FILE in $ADD_FILES $MODIFY_FILES $REMOVE_FILES; do
            if [ ! -e "$FILE" ] && [[ -n "$FILE" ]]; then # -e: 파일 또는 디렉토리
                INVALID_FILES+=("$FILE")
            fi
        done

        if [ ${#INVALID_FILES[@]} -gt 0 ]; then
            echo -e "${RED}다음 파일/디렉토리가 ${PROJECT_PATH}에 존재하지 않습니다. 커밋을 취소합니다:${NC}"
            for FILE in "${INVALID_FILES[@]}"; do
                echo -e "${RED}  - $FILE${NC}"
            done
            exit 1
        fi
    )
    # 서브셸 실행 실패 시
    if [ $? -ne 0 ]; then exit 1; fi


    # 커밋 메시지 작성
    FORMATTED_MSG=""
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            if [[ "$AUTO_PREFIX" == "ON" ]]; then
                FORMATTED_MSG+="- $line"$'\n'
            else
                FORMATTED_MSG+="$line"$'\n'
            fi
        fi
    done <<< "$COMMIT_MSG"

    if [[ -z "$JIRA_NUMBER" ]]; then
        COMMIT_MESSAGE="${COMMIT_TITLE}"$'\n\n'"${FORMATTED_MSG}"
    else
        COMMIT_MESSAGE="${JIRA_NUMBER} ${COMMIT_TITLE}"$'\n\n'"${FORMATTED_MSG}"
    fi

    # SVN 작업 수행 (프로젝트 경로에서 실행)
    (
        cd "$PROJECT_PATH" || { echo -e "${RED}프로젝트 경로(${PROJECT_PATH})로 이동 실패${NC}"; exit 1; }
        
        if [[ -n "$ADD_FILES" ]]; then
            echo -e "${CYAN}파일 추가 중...${NC}"
            for FILE in $ADD_FILES; do
                if [ -e "$FILE" ]; then
                    svn add "$FILE"
                fi
            done
        fi

        if [[ -n "$REMOVE_FILES" ]]; then
            echo -e "${CYAN}파일 삭제 중...${NC}"
            for FILE in $REMOVE_FILES; do
                if [ -e "$FILE" ]; then
                    svn delete "$FILE"
                fi
            done
        fi

        echo -e "${CYAN}커밋 실행 중... (대상: ${BOLD}${PROJECT_PATH}${NC})${NC}"
        svn commit -m "$COMMIT_MESSAGE" $ADD_FILES $MODIFY_FILES $REMOVE_FILES
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}커밋이 성공적으로 완료되었습니다.${NC}"
            # 커밋 성공 시 clear는 이 스크립트를 직접 호출해야 함
            # 서브셸에서는 $0을 정확히 알기 어려우므로 $SCRIPT_DIR/$SCRIPT_FILE_NAME 사용
            "$SCRIPT_DIR/$SCRIPT_FILE_NAME" clear
        else
            echo -e "${RED}커밋 도중 문제가 발생했습니다.${NC}"
            exit 1
        fi
    )
    exit 0
fi

# --- [수정됨] 알 수 없는 명령어 처리 ---
# 위에서 모든 if [ "$1" == "..." ] fi 에 해당하지 않으면
# 여기까지 도달하게 되며, 사용법을 안내합니다.

echo -e "${RED}알 수 없는 옵션입니다: $1${NC}"
echo -e "${CYAN}사용법:${NC}"
echo -e "  ./svn_commit.sh info    상태 확인"
echo -e "  ./svn_commit.sh run      커밋 실행"
echo -e "  ./svn_commit.sh check    수정 내용 확인"
echo -e "  ./svn_commit.sh clear    파일 초기화"
echo -e "  ./svn_commit.sh setting  설정 확인/변경"
echo -e "  ./svn_commit.sh help     도움말 표시"
echo -e "  ./svn_commit.sh version  버전 확인"
echo -e "  ./svn_commit.sh update   스크립트 업데이트"
echo -e "  ./svn_commit.sh upload   스크립트 배포(업로드)"
echo -e "\n${YELLOW}도움말을 보려면 './svn_commit.sh help' 를 입력하세요.${NC}"

# --- 스크립트 수정 시, 'upload' 명령어가 SCRIPT_VERSION을 자동으로 업데이트합니다. ---
