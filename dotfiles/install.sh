#!/bin/bash
# @desc 개발 환경 최초 세팅 — dotfiles 링크 + 개인 설정

set -euo pipefail

KSCTOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="$KSCTOOL_DIR/dotfiles"
PRIVATE_DIR="$HOME/.private"
PERSONAL_CFG="$PRIVATE_DIR/personal.sh"

cRed='\e[31m'; cGreen='\e[32m'; cYellow='\e[33m'
cSky='\e[36m'; cDim='\e[2m'; cBold='\e[1m'; cReset='\e[0m'

_STEP=0; _TOTAL=3
_step() { ((_STEP++)); echo -e "\n${cBold}${cSky}[${_STEP}/${_TOTAL}]${cReset} $1"; }
_ok()   { echo -e "  ${cGreen}✓${cReset}  $*"; }
_skip() { echo -e "  ${cDim}↩  $* (건너뜀)${cReset}"; }
_warn() { echo -e "  ${cYellow}⚠  $*${cReset}"; }
_ask()  { read -rp "  ${cBold}?${cReset}  $1 " "$2"; }

_link() {
    local name="$1"
    local src="$DOTFILES_DIR/$name"
    local dst="$HOME/$name"

    if [[ ! -f "$src" ]]; then
        _warn "$name: dotfiles에 없음 — 건너뜀"; return
    fi
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        _skip "$name (이미 링크됨)"; return
    fi
    if [[ -f "$dst" && ! -L "$dst" ]]; then
        local bak="${dst}.bak.$(date +%Y%m%d)"
        cp -f "$dst" "$bak"
        _warn "기존 파일 백업: $bak"
    fi
    ln -sf "$src" "$dst"
    _ok "$name  →  $src"
}

_setup_personal() {
    local _user _uname _pnum _proj _ws

    echo ""
    _ask "사용자 이름 (DV_USER, 예: jsh):" _user
    _ask "표시 이름  (DV_USER_NAME, 예: JSH):" _uname

    echo ""
    echo -e "  기본 프로젝트:"
    echo -e "    1) 609  (DV03-609H / 13_1)   2) 12_5   3) 12_4   4) 012   5) 직접 입력"
    _ask "선택 [1]:" _pnum
    case "${_pnum:-1}" in
        1) _proj="609"  ;; 2) _proj="12_5" ;;
        3) _proj="12_4" ;; 4) _proj="012"  ;;
        *) _ask "프로젝트 이름:" _proj ;;
    esac

    _ask "워크스페이스 경로 [/home/workspace]:" _ws
    _ws="${_ws:-/home/workspace}"

    cat > "$PERSONAL_CFG" << EOF
# ~/.private/personal.sh — 개인 환경 오버라이드 (공유 금지)
# dv firstsetup 으로 생성됨 — $(date '+%Y-%m-%d')

export DV_USER="${_user}"
export DV_USER_NAME="${_uname}"
NOW_PROJECT="${_proj}"
WORKSPACE_DIR="${_ws}"
HTTP_PATH="\$HOME/server_${_user}"
EOF
    _ok "~/.private/personal.sh 생성 완료"
}

# ─────────────────────────────────────────────────────────────
# 헤더
# ─────────────────────────────────────────────────────────────
echo -e ""
echo -e "${cBold}${cSky}┌─────────────────────────────────────┐${cReset}"
echo -e "${cBold}${cSky}│       dv firstsetup / install       │${cReset}"
echo -e "${cBold}${cSky}└─────────────────────────────────────┘${cReset}"
echo -e "  ${cDim}KscTool: $KSCTOOL_DIR${cReset}"

# ─────────────────────────────────────────────────────────────
# Step 1: dotfiles 심볼릭 링크
#   symlink 이후 ~/.bash_functions == dotfiles/.bash_functions (sync 자동화)
# ─────────────────────────────────────────────────────────────
_step "dotfiles 링크"
_link .bash_aliases
_link .bash_functions

# ─────────────────────────────────────────────────────────────
# Step 2: 개인 설정 (~/.private/personal.sh)
#   .bashrc 소싱 순서: NOW_PROJECT=609 → ~/.private/*.sh → bash_functions
#   personal.sh 가 마지막에 로드되므로 NOW_PROJECT 등 override 가능
# ─────────────────────────────────────────────────────────────
_step "개인 설정"

mkdir -m 700 -p "$PRIVATE_DIR"

if [[ ! -f "$PRIVATE_DIR/secrets.sh" ]]; then
    cat > "$PRIVATE_DIR/secrets.sh" << 'EOF'
# ~/.private/secrets.sh — 민감 정보 (공유 금지, gitignore)
# export ROOT_PW=""
# export GEMINI_API_KEY=""
EOF
    _ok "~/.private/secrets.sh 템플릿 생성 — 직접 편집 필요"
fi

if [[ -f "$PERSONAL_CFG" ]]; then
    _warn "기존 설정 있음: $PERSONAL_CFG"
    local _yn=''
    _ask "다시 설정하시겠습니까? [y/N]:" _yn
    if [[ "${_yn:-N}" == "y" || "${_yn:-N}" == "Y" ]]; then
        _setup_personal
    else
        _skip "개인 설정"
    fi
else
    _setup_personal
fi

# ─────────────────────────────────────────────────────────────
# Step 3: dvhelp 확인
# ─────────────────────────────────────────────────────────────
_step "설치 확인"

[[ -f "$KSCTOOL_DIR/tools/dvhelp.sh" ]] \
    && _ok "dvhelp 사용 가능" \
    || _warn "dvhelp.sh 없음 — git -C $KSCTOOL_DIR pull"

# ─────────────────────────────────────────────────────────────
# 완료
# ─────────────────────────────────────────────────────────────
echo -e ""
echo -e "${cBold}${cGreen}  완료!${cReset}"
echo -e ""
echo -e "  다음 단계:"
echo -e "    ${cYellow}source ~/.bashrc${cReset}      환경 적용"
echo -e "    ${cYellow}dvhelp${cReset}                커맨드 목록 확인"
echo -e ""
echo -e "  민감 정보 설정:"
echo -e "    ${cDim}~/.private/secrets.sh${cReset}  ROOT_PW, API 키 등"
echo -e ""
