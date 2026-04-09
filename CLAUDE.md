# CLAUDE.md — KscTool 개발 규칙

> AI가 KscTool 작업 시 자동으로 지켜야 할 규칙.
> 공통 워크플로우·스타일은 글로벌 CLAUDE.md 참조.

---

## 1. 저장소 개요

| 항목 | 내용 |
| ---- | ---- |
| **목적** | AP 개발 자동화 도구 모음 (개인 + 팀원 배포용) |
| **경로** | `~/KscTool/` |
| **GitHub** | https://github.com/ksc2320/KscTool.git |
| **개발 가이드** | `~/memo/20_areas/tools/ksctool_dev_guide.md` |

---

## 2. 폴더 구조

```
KscTool/
├── ftd/        # AP 파일 전송 (file_to_dev.sh)
├── svn/        # SVN 커밋 헬퍼
├── build/      # 빌드 도구
├── tools/      # 기타 유틸
├── cpbak/      # 파일 백업/원복 도구
├── dotfiles/   # 공유 가능한 shell 설정 (.bashrc, .bash_aliases, .bash_functions)
├── CHANGELOG.md
├── CLAUDE.md
└── README.md
```

**신규 도구 추가 시:**
- 기능별 폴더 생성 → `.sh` 작성 → `chmod +x`
- `~/.bash_aliases` `#ksc_tools` 섹션에 alias 추가
- `README.md` 표 업데이트
- `CHANGELOG.md`에 버전 항목 추가

**dotfiles 수정 시:**
- `~/.bash_aliases`, `~/.bash_functions`, `~/.bashrc`에서 개인정보 없는지 확인
- 개인정보(이메일, API 키, 패스워드, IP 등)는 반드시 `~/.private/`로 분리
- `dotfiles/` 폴더에 복사 후 git push
- 개인정보 분리 구조:
  - `~/.private/secrets.sh` — GEMINI_API_KEY, ROOT_PW
  - `~/.private/accounts.sh` — 이메일 계정 정보
  - `.bashrc`에서 `for _pvf in ~/.private/*.sh; do source; done` 패턴으로 로드

---

## 3. 버전 관리 규칙

### 3.1 버전 형식: `MAJOR.MINOR.PATCH`

| 변경 종류 | 올릴 자릿수 | 예시 |
| --------- | ----------- | ---- |
| 구조 변경, 인터페이스 파괴적 변경 | MAJOR | 1.x.x → 2.0.0 |
| 새 명령/기능 추가 | MINOR | x.1.x → x.2.0 |
| 버그 수정, 코드 정리, 문서 | PATCH | x.x.1 → x.x.2 |

### 3.2 각 도구별 버전 관리

각 `.sh` 파일 상단에 버전 변수 선언:

```bash
# ftd
FTD_VERSION='2.1.0'

# 기타 도구
TOOL_VERSION='1.0.0'
```

`version` 또는 `-V` 서브커맨드로 확인 가능하게:

```bash
version|-V) echo "${TOOL_NAME} v${TOOL_VERSION}" ;;
```

### 3.3 CHANGELOG.md 형식

사용자 관점으로 작성한다 — 구현 세부사항보다 "이걸 쓰면 뭐가 되는지"를 먼저 전달한다.

- **변경 내용** (필수): 사용자가 체감하는 변화 한 줄
- **사용법** (선택 — 명령어/인터페이스 바뀐 경우): 명령어 예시 + 설명
- **Fixed / Changed** (선택 — 내부 수정): 버그 수정, 리팩토링 등

```markdown
## [MAJOR.MINOR.PATCH] — YYYY-MM-DD — {도구명}

### 변경 내용
- {무엇이 바뀌었는지 1줄}

### 사용법
- `{명령어}` — {이 명령으로 무엇을 할 수 있는지}

### Fixed / Changed
- {버그 수정 또는 내부 변경}
```

### 3.4 AI가 작업 후 반드시 할 것

1. **버전 범프**: 기능 추가 → MINOR+1 / 버그 수정 → PATCH+1
2. **CHANGELOG.md 업데이트**: §3.3 형식 준수
3. **스크립트 내 VERSION 변수 업데이트**
4. `git commit` 메시지에 버전 명시: `feat(ftd): scan 개선 — v2.2.0`
5. `git push` — CHANGELOG.md 업데이트가 선행되지 않았으면 push 전에 먼저 처리

---

## 4. 문서화 규칙

### 4.1 세션 완료 시

- `~/memo/20_areas/tools/ksctool_dev_guide.md` — 설계 결정, 알려진 이슈, 해결 이력 추가
- `CHANGELOG.md` — 이번 세션 변경 내용 기록
- README.md — 신규 도구/명령어 있으면 업데이트

### 4.2 신규 도구 작성 시

스크립트 상단 헤더 형식:

```bash
#!/bin/bash
# ============================================================================
#  toolname.sh — 한 줄 설명 vX.Y.Z
# ============================================================================
#  사용법: toolname <command> [args]
#
#  Commands:
#    ...
# ============================================================================
TOOL_VERSION='X.Y.Z'
```

### 4.3 개발 가이드 업데이트 조건

- 새로운 설계 결정이 생겼을 때
- 알려진 이슈가 추가/해결됐을 때
- 새 도구가 추가됐을 때

---

## 5. 스크립트 스타일

**UX 경험 우선 원칙**: 사용자가 "지금 뭐가 되고 있는지" 항상 알 수 있게 만든다.

### 5.1 컬러 및 아이콘

- **컬러 적극 사용** (SVN 미포함 → 자유롭게)
- 단계 표시: `[1/3]` 또는 `[1] 복사 ▸ [2] HTTP ▸ [3] wget` 흐름 형태
- 실패 시 이유 명시 + 해결 힌트 출력
- `_OK` / `_FAIL` / `_RUN` / `_WARN` 아이콘 통일

ftd의 컬러/아이콘 정의를 참조하거나 동일하게 사용 권장:

```bash
_F_RED='\033[1;31m'; _F_GREEN='\033[1;32m'; _F_YELLOW='\033[1;33m'
_F_CYAN='\033[1;36m'; _F_WHITE='\033[1;37m'; _F_DIM='\033[0;90m'; _F_RST='\033[0m'
_OK="${_F_GREEN}✔${_F_RST}"; _FAIL="${_F_RED}✘${_F_RST}"
_RUN="${_F_CYAN}▶${_F_RST}"; _WARN="${_F_YELLOW}⚠${_F_RST}"
```

### 5.2 결과 배너 (`_banner`)

성공/실패/경고 결과는 단순 echo 대신 `_banner`로 시각적 구분:

```bash
_banner() {
    local type="$1" msg="$2" elapsed="${3:-}"
    local t_str=""; [ -n "$elapsed" ] && t_str=" ${_F_DIM}(${elapsed}s)${_F_RST}"
    case "$type" in
        ok)   echo -e "${_F_GREEN}╔══╗\n║ ✔ ${_F_WHITE}${msg}${t_str}\n${_F_GREEN}╚══╝${_F_RST}" ;;
        fail) echo -e "${_F_RED}╔══╗\n║ ✘ ${_F_WHITE}${msg}${t_str}\n${_F_RED}╚══╝${_F_RST}" ;;
        warn) echo -e "${_F_YELLOW}╔══╗\n║ ⚠ ${_F_WHITE}${msg}${t_str}\n${_F_YELLOW}╚══╝${_F_RST}" ;;
    esac
}
# 사용: _banner ok "완료 메시지" "$elapsed"
```

### 5.3 대기 중 실시간 피드백

장시간 대기(부팅, 네트워크 등) 시 `\r` 카운터로 사용자가 얼마나 기다렸는지 표시:

```bash
printf "\r  ${_F_DIM}대기 중 %3ds ...${_F_RST}" "$elapsed"
```

### 5.4 위험 동작 확인 프롬프트

재부팅·포맷 등 비가역 동작은 컬러 박스로 강조:

```bash
echo -e "${_F_RED}╔════════════════════╗${_F_RST}"
echo -e "${_F_RED}║  ⚠  AP가 재부팅됩니다 ║${_F_RST}"
echo -e "${_F_RED}╚════════════════════╝${_F_RST}"
echo -ne "  진행? [y/N]: "; read -r confirm
```

### 5.5 재시도 + 애니메이션

ping/연결 등 재시도 로직은 점 애니메이션으로 진행 상황 표시:

```bash
for i in 1 2 3; do
    ping -c1 -W1 "$host" &>/dev/null && { echo -e "${_OK}"; return 0; }
    echo -ne "${_F_DIM}.${_F_RST}"
    [ $i -lt 3 ] && sleep 1
done
```

---

_최종 갱신: 2026-04-06_ <!-- §3.3-3.4: 사용자 관점 패치노트 형식 추가 -->
