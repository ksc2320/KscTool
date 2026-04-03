# cpbak — SVN/Git 수정 파일 백업 & 원복 도구

> KscTool 모음의 일부. SVN/Git 워크스페이스에서 수정된 파일을 안전하게 백업하고 원복하는 bash 스크립트.

---

## 왜 만들었나

OpenWrt 빌드 환경에서는 `svn revert` 또는 빌드 clean이 작업 파일을 날릴 위험이 있다.  
그렇다고 매번 수동으로 파일을 복사해두기도 번거롭다.

- **문제**: `svn revert -R` 또는 빌드 재실행 → 내 수정 파일 사라짐
- **해결**: 작업 전 `cpbak save` 한 번으로 스냅샷 → 언제든 `cpbak restore`로 복원

---

## 설치

```bash
# 딱 한 줄 — init이 bash_functions, bash_aliases 자동 등록
bash ~/KscTool/cpbak/cpbak.sh init

# 적용 (새 터미널 열거나)
source ~/.bash_functions

# 확인
cpbak help
```

`init`이 수행하는 작업:
1. `~/.devtools/cpbak/` 디렉토리 생성
2. `~/.bash_functions`에 source 등록 (중복 체크)
3. `~/.bash_aliases`에 `alias cpbak='_cpbak_main'` 등록 (중복 체크)
4. `~/.devtools/cpbak/config` 기본 설정 파일 생성

---

## 사용법

### 기본 흐름

```
1. cpbak status          ← 백업 대상 파일 미리 확인
2. cpbak save -m "메모"  ← 백업 실행
3. (작업, revert, 빌드 등)
4. cpbak restore last    ← 필요하면 복원
```

### status — 백업 예정 파일 미리보기

```bash
cpbak status              # 현재 디렉토리 기준
cpbak status --verbose    # 필터 제외 목록도 함께 표시
cpbak status /path/to/dir # 특정 경로 기준
```

출력 항목:

| 기호 | 의미 |
|------|------|
| `M`  | 수정됨 — 백업 대상 |
| `A`  | 새 파일 추가됨 — 백업 대상 |
| `D`  | 삭제됨 — 목록만 기록 (복사 불가) |
| `◆`  | 미추적 IDE 설정 (`.vscode` 등) — 자동 포함 |
| `⚠`  | 미추적 미결정 — save 시 interactive 선택 |
| `⊘`  | ignore 패턴으로 제외됨 |
| `~`  | 내장 필터 제외 (autoconf 자동생성 파일) |

### save — 백업 생성

```bash
cpbak save                       # 기본 백업
cpbak save -m "IPv6 작업 전"     # 메모 포함
cpbak save --scope davo/feeds    # 특정 하위 경로만
```

백업 위치: `~/temp_copy/{proj}_{timestamp}/`  
경로 구조 유지: `~/temp_copy/workspace_20260403_153042/davo/files_kt/etc/init.d/macvlan`

메타 파일 `.cpbak_meta`에 날짜, VCS 루트, 파일 목록 기록됨.

### restore — 복원

```bash
cpbak restore last                 # 가장 최근 백업으로 복원
cpbak restore workspace_20260403_153042  # 특정 백업으로 복원
cpbak restore last --dry-run       # 실제 복사 없이 미리보기
```

- 실행 전 확인 프롬프트(`[y/N]`) 필수.
- 백업 당시 VCS 루트와 현재 루트가 다르면 **경고 + 중단 선택** 제시 (다른 머신·경로 복원 보호).

### list — 백업 목록

```bash
cpbak list      # 백업 이름 / 파일수 / 메모 테이블 출력
```

### diff — 백업 vs 현재 비교

```bash
cpbak diff last               # 최근 백업 vs 현재 diff
cpbak diff workspace_20260403_153042  # 특정 백업 diff
```

`colordiff`가 설치되어 있으면 컬러 출력.

### clean — 오래된 백업 삭제

```bash
cpbak clean --days 7    # 7일 이상 된 백업 목록 + 확인 후 삭제
cpbak clean --days 30   # 30일 기준
```

삭제 전 목록(이름/크기/메모)을 보여주고 `[y/N]` 확인.

---

## ignore 관리

수정 파일 중 백업에서 **영구 제외**할 파일/경로 관리.

### 두 가지 ignore 파일

| 종류 | 경로 | 적용 범위 |
|------|------|-----------|
| 글로벌 | `~/.devtools/cpbak/ignore` | 모든 프로젝트 |
| 프로젝트 | `{VCS_ROOT}/.cpbakignore` | 해당 워크스페이스만 |

### 패턴 형식 (`.gitignore` 스타일 glob)

```
# 주석 (# 시작)

# 특정 파일 제외
.vscode/settings.json

# 패키지 전체 제외 (glob)
build_dir/*/iperf*/

# 확장자 패턴
*.min.js
*.min.css
```

- 후행 `/`는 있어도 없어도 동일하게 동작 (`foo/` = `foo` 하위 전체)
- `*`는 단일 path segment 매칭 (`build_dir/*/iperf*/` → `build_dir/[패키지명]/iperf*/`)

### 서브커맨드

```bash
# 목록 확인
cpbak ignore list

# 프로젝트에 패턴 추가 (기본)
cpbak ignore add "build_dir/*/iperf*/"

# 글로벌에 패턴 추가 (-g)
cpbak ignore add -g ".vscode/settings.json"

# 패턴 삭제
cpbak ignore rm "build_dir/*/iperf*/"
cpbak ignore rm -g ".vscode/settings.json"

# 에디터로 직접 편집
cpbak ignore edit        # 프로젝트 .cpbakignore
cpbak ignore edit -g     # 글로벌 ignore
```

### .cpbakignore를 SVN ignore에 등록

```bash
# 프로젝트 루트에서
svn propset svn:ignore ".cpbakignore" .
```

또는 `~/.subversion/config`의 `global-ignores`에 `.cpbakignore` 추가.

---

## 내장 필터 (변경 불가)

사용자가 건드리지 않아도 자동 제외되는 파일들:

**build_dir 하위, dv_pkg가 아닌 패키지의 autoconf 자동생성 파일:**

```
configure, config.guess, config.sub, config.h.in, *.h.in
install-sh, ltmain.sh, sysoptions.h, .dep_files, Makefile.in
build_dir/*/ipkg-arm_*/**      (패키징 산출물)
build_dir/*/ipkg-install/**    (설치 staging)
```

`build_dir/*/dv_pkg/**`는 실제 개발 소스이므로 내장 필터에서 **제외되지 않음**.

---

## 설정 파일

`~/.config/cpbak/config` (없으면 기본값 사용):

```bash
CPBAK_BACKUP_ROOT="$HOME/temp_copy"   # 백업 루트 경로
CPBAK_ALIAS="cpbak"                   # alias 이름
CPBAK_USE_FZF="auto"                  # fzf 사용 여부 (auto|on|off)
```

---

## 파일 구조

```
~/temp_copy/
└── 20260403_153042/
    ├── .cpbak_meta                          ← 메타 정보 (복원에 사용)
    ├── davo/feeds/webui/.../lan.ejs
    ├── davo/files_kt/etc/init.d/macvlan
    └── build_dir/.../dv_pkg/dvmgmt/...
```

`.cpbak_meta` 내용:
```bash
CPBAK_DATE="20260403_153042"
CPBAK_VCS_ROOT="/home/workspace"
CPBAK_MEMO="IPv6 작업 전"
CPBAK_FILES_M=("davo/files_kt/..." ...)
CPBAK_FILES_D=(...)    # 삭제 파일 목록 (복원 불가, 참고용)
```

---

## Phase 3 예정 기능

| 커맨드 | 내용 |
|--------|------|
| `cpbak revert` | `svn revert` 래퍼 (fzf로 파일 선택) |

---

## 관련 KscTool

| 도구 | alias | 용도 |
|------|-------|------|
| `file_to_dev.sh` | `fwd` | AP 장치 펌웨어/파일 전송 |
| `svn_commit.sh` | `scs` | SVN 커밋 도우미 |
| `rebuild_changed.sh` | `rbc` | 수정 파일 선택적 빌드 |
| `cpbak.sh` | `cpbak` | 수정 파일 백업 & 원복 |

---

_작성: Claude Sonnet 4.6 / 최초 작성: 2026-04-03 / 갱신: 2026-04-03 (v1.3 list·diff·clean 추가)_
