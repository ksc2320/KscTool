#!/bin/bash
# @desc 커스텀 bash 커맨드 목록 및 설명 / KscTool 설치 안내

# Colors (standalone 실행 대비 직접 선언)
_h_cRed='\e[31m'; _h_cGreen='\e[32m'; _h_cYellow='\e[33m'
_h_cSky='\e[36m'; _h_cDim='\e[2m'; _h_cBold='\e[1m'; _h_cReset='\e[0m'

FILTER="${1:-}"
ALIASES_FILE="${HOME}/.bash_aliases"
FUNCTIONS_FILE="${HOME}/.bash_functions"
KSCTOOL_DIR="${HOME}/KscTool"
KSCTOOL_REPO="https://github.com/ksc2320/KscTool.git"

_h_ksc_installed() { [[ -d "$KSCTOOL_DIR" ]]; }

# ─────────────────────────────────────────────────────────────
# 헤더
# ─────────────────────────────────────────────────────────────
echo -e ""
echo -e "${_h_cBold}${_h_cSky}[ dv 커맨드 목록 ]${_h_cReset}  ${_h_cDim}프로젝트: ${NOW_PROJECT:-?}  /  ${WORKSPACE_DIR:-?}${_h_cReset}"
[[ -n "$FILTER" ]] && echo -e "  ${_h_cDim}검색어: '${FILTER}'${_h_cReset}"

if ! _h_ksc_installed; then
    echo -e ""
    echo -e "  ${_h_cYellow}⚠  KscTool 미설치${_h_cReset} — 일부 명령어가 비활성화됩니다."
    echo -e "  ${_h_cDim}설치: git clone ${KSCTOOL_REPO} ~/KscTool && source ~/.bashrc${_h_cReset}"
fi
echo ""

# ─────────────────────────────────────────────────────────────
# Alias 파싱 — ## 섹션 기준 그룹화
# ─────────────────────────────────────────────────────────────
_h_parse_aliases() {
    local file="$1"
    [[ ! -f "$file" ]] && return

    local section="" section_printed=0 any_printed=0
    local line name raw_name raw_val val desc ksc_path missing

    while IFS= read -r line; do
        # 섹션 헤더 (## ...)
        if [[ "$line" =~ ^##[[:space:]]*(.+)$ ]]; then
            section="${BASH_REMATCH[1]}"
            section_printed=0
            continue
        fi

        [[ "$line" =~ ^alias[[:space:]] ]] || continue

        # 이름 추출 (따옴표 제거)
        raw_name="${line#alias }"
        raw_name="${raw_name%%=*}"
        name="${raw_name//\'/}"; name="${name//\"/}"; name="${name// /}"
        [[ -z "$name" ]] && continue

        # 값 추출
        raw_val="${line#*=}"
        val="${raw_val#\'}"; val="${val%\'}"; val="${val#\"}"; val="${val%\"}"

        # 인라인 주석 desc
        desc=""
        if [[ "$val" =~ ^(.*[^[:space:]])[[:space:]]+\#[[:space:]]+(.+)$ ]]; then
            val="${BASH_REMATCH[1]}"
            desc="${BASH_REMATCH[2]}"
        fi

        # cd 경로에서 desc 자동 생성
        if [[ -z "$desc" && "$val" =~ ^cd[[:space:]]+(.+)$ ]]; then
            desc="${BASH_REMATCH[1]}"
            desc="${desc//\$TARGET_DIR\/dv_pkg\//}"
            desc="${desc//\$TARGET_DIR\/dv_pkg/dv_pkg}"
            desc="${desc//\$SOURCE_DIR\/davo\//davo/}"
            desc="${desc//\$SOURCE_DIR\//}"
            desc="${desc//\$TARGET_DIR\//}"
        fi

        # KscTool 경로 감지 → 파일 존재 여부 확인
        missing=""
        if [[ "$val" == *"KscTool"* ]]; then
            ksc_path="${val/\$HOME/$HOME}"; ksc_path="${ksc_path/\~/$HOME}"
            if [[ ! -f "$ksc_path" ]]; then
                missing=" ${_h_cRed}[미설치]${_h_cReset}"
            fi
        fi

        # 필터 적용
        if [[ -n "$FILTER" ]]; then
            [[ "$name" != *"$FILTER"* && "$desc" != *"$FILTER"* && "$section" != *"$FILTER"* ]] && continue
        fi

        # 섹션 헤더 출력
        if [[ "$section_printed" -eq 0 ]]; then
            [[ "$any_printed" -eq 1 ]] && echo ""
            echo -e "  ${_h_cBold}${_h_cSky}── ${section:-기타}${_h_cReset}"
            section_printed=1; any_printed=1
        fi

        printf "    ${_h_cGreen}%-22s${_h_cReset} ${_h_cDim}%s${_h_cReset}%b\n" "$name" "$desc" "$missing"

    done < "$file"
}

# ─────────────────────────────────────────────────────────────
# Function 파싱 — # @desc 달린 것만 노출
# ─────────────────────────────────────────────────────────────
_h_parse_functions() {
    local file="$1"
    [[ ! -f "$file" ]] && return

    local pending_desc="" printed_header=0 line name

    while IFS= read -r line; do
        if [[ "$line" =~ ^#[[:space:]]*@desc[[:space:]]+(.+)$ ]]; then
            pending_desc="${BASH_REMATCH[1]}"
            continue
        fi
        # 함수 정의가 아닌 줄이면 desc 리셋
        if [[ -n "$line" && ! "$line" =~ ^# && ! "$line" =~ ^function ]]; then
            pending_desc=""
        fi

        if [[ "$line" =~ ^function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*\( ]]; then
            name="${BASH_REMATCH[1]}"
            [[ -z "$pending_desc" ]] && continue
            [[ "$name" == _* ]] && pending_desc="" && continue

            if [[ -n "$FILTER" ]]; then
                [[ "$name" != *"$FILTER"* && "$pending_desc" != *"$FILTER"* ]] && pending_desc="" && continue
            fi

            if [[ "$printed_header" -eq 0 ]]; then
                echo -e "\n  ${_h_cBold}${_h_cSky}── 함수${_h_cReset}"
                printed_header=1
            fi
            printf "    ${_h_cYellow}%-22s${_h_cReset} ${_h_cDim}%s${_h_cReset}\n" "$name" "$pending_desc"
            pending_desc=""
        fi
    done < "$file"
}

# ─────────────────────────────────────────────────────────────
# KscTool 스크립트 목록
# ─────────────────────────────────────────────────────────────
_h_parse_ksctool() {
    _h_ksc_installed || return

    local printed_header=0 tool_name desc line first_comment

    for script in "$KSCTOOL_DIR"/tools/*.sh; do
        [[ -f "$script" ]] || continue
        tool_name=$(basename "$script" .sh)

        # @desc 우선, fallback은 첫 번째 일반 주석 — bash regex로 통일 (서브셸 없음)
        desc="" first_comment=""
        while IFS= read -r line; do
            if [[ "$line" =~ ^#[[:space:]]*@desc[[:space:]]+(.+)$ ]]; then
                desc="${BASH_REMATCH[1]}"; break
            elif [[ -z "$first_comment" && "$line" =~ ^#[[:space:]]+(.+)$ && ! "$line" =~ ^#! ]]; then
                first_comment="${BASH_REMATCH[1]}"
            fi
        done < "$script"
        [[ -z "$desc" ]] && desc="$first_comment"

        if [[ -n "$FILTER" ]]; then
            [[ "$tool_name" != *"$FILTER"* && "$desc" != *"$FILTER"* ]] && continue
        fi

        if [[ "$printed_header" -eq 0 ]]; then
            echo -e "\n  ${_h_cBold}${_h_cSky}── KscTool / tools${_h_cReset}"
            printed_header=1
        fi
        printf "    ${_h_cBold}%-22s${_h_cReset} ${_h_cDim}%s${_h_cReset}\n" "$tool_name" "$desc"
    done
}

# ─────────────────────────────────────────────────────────────
# 실행
# ─────────────────────────────────────────────────────────────
_h_parse_aliases   "$ALIASES_FILE"
_h_parse_functions "$FUNCTIONS_FILE"
_h_parse_ksctool

echo -e ""
echo -e "  ${_h_cDim}사용법: dvhelp [키워드]   예) dvhelp kernel / dvhelp ksc${_h_cReset}"
echo -e ""

# 미설치 시 설치 안내 재강조
if ! _h_ksc_installed; then
    echo -e "  ${_h_cYellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_h_cReset}"
    echo -e "  ${_h_cYellow}  KscTool 설치 방법${_h_cReset}"
    echo -e "  ${_h_cYellow}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${_h_cReset}"
    echo -e ""
    echo -e "    ${_h_cGreen}git clone ${KSCTOOL_REPO} ~/KscTool${_h_cReset}"
    echo -e "    ${_h_cGreen}source ~/.bashrc${_h_cReset}"
    echo -e ""
    echo -e "  설치 후 ${_h_cRed}[미설치]${_h_cReset} 표시된 명령어들이 활성화됩니다."
    echo -e ""
fi

# 내부 함수 정리
unset -f _h_ksc_installed _h_parse_aliases _h_parse_functions _h_parse_ksctool
unset _h_cRed _h_cGreen _h_cYellow _h_cSky _h_cDim _h_cBold _h_cReset
