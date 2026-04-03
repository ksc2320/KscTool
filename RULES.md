# KscTool 개발 규칙 (RULES.md)

> KscTool 모음에 새 도구를 추가하거나 기존 도구를 수정할 때 반드시 준수한다.

---

## 1. 디렉토리 구조

```
~/KscTool/
├── RULES.md            ← 이 파일 (개발 규칙)
├── <toolname>/
│   ├── <toolname>.sh   ← 메인 스크립트
│   └── README.md       ← 사용 설명서
├── ftd/                (file_to_dev — AP 파일 전송)
├── cpbak/              (cpbak — SVN/Git 백업)
├── svn/                (scs — SVN 커밋 도우미)
├── build/              (rbc, bep — 빌드 도구)
└── tools/              (기타 유틸)
```

---

## 2. 설정/데이터 저장 경로 — `~/.devtools/`

**모든 KscTool은 런타임 데이터(설정, 로그, 캐시)를 `~/.devtools/<toolname>/` 에 저장한다.**

```
~/.devtools/
├── cpbak/       (config, ignore, history.log)
├── ftd/         (config, history.log)
├── scs/         (config, last_check, update_status)
└── <new_tool>/  (새 도구 추가 시)
```

### 파일 이름 컨벤션

| 파일 | 용도 |
|------|------|
| `config` | 사용자 설정 (bash 변수 형식, source 가능) |
| `history.log` | 실행 이력 (날짜 \| 커맨드 \| 결과 형식) |
| `ignore` | 제외 패턴 목록 (cpbak 전용 개념, 필요 시 다른 도구도 동일 이름 사용) |

### 스크립트 내 상수 선언 예시

```bash
TOOL_CONF_DIR="$HOME/.devtools/<toolname>"
TOOL_CONF="${TOOL_CONF_DIR}/config"
TOOL_LOG="${TOOL_CONF_DIR}/history.log"
```

---

## 3. init 서브커맨드 (필수)

**모든 KscTool은 `init` 서브커맨드를 제공해야 한다.**

`init`이 한 번만 실행되면 사용자가 아무 설정 없이 바로 도구를 쓸 수 있어야 한다.

### init이 수행해야 하는 작업

1. **`~/.devtools/<toolname>/` 디렉토리 생성**
2. **`~/.bash_functions`에 source 등록** (중복 체크 필수)
3. **`~/.bash_aliases`에 alias 등록** (중복 체크 필수)
4. **기본 `config` 파일 생성** (없는 경우, 주석으로 설명 포함)
5. **완료 후 `source ~/.bash_functions` 안내** 출력

### 중복 체크 패턴

```bash
# bash_functions에 이미 등록됐는지 확인
if grep -qF "<toolname>.sh" "$HOME/.bash_functions" 2>/dev/null; then
    echo "이미 등록됨 (skip)"
else
    echo "[ -f \"${TOOL_SELF}\" ] && source \"${TOOL_SELF}\"" >> "$HOME/.bash_functions"
fi

# bash_aliases에 이미 등록됐는지 확인
if grep -qE "alias <alias>|alias.*_<tool>_main" "$HOME/.bash_aliases" 2>/dev/null; then
    echo "이미 등록됨 (skip)"
else
    echo "alias <alias>='_<tool>_main'" >> "$HOME/.bash_aliases"
fi
```

---

## 4. source/직접실행 분기 (필수)

모든 스크립트는 `source`로 불릴 때와 직접 실행될 때를 구분해야 한다.

```bash
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # source 로 불림 → 함수 등록만
    _<tool>_register
else
    # 직접 실행
    _<tool>_main "$@"
fi
```

`_<tool>_register()`는 alias를 등록하고 설정을 로드한다:

```bash
_<tool>_register() {
    _<tool>_load_conf
    eval "alias ${TOOL_ALIAS:-<toolname>}='_<tool>_main'"
}
```

---

## 5. alias 등록 위치

- **`~/.bash_functions`**: `source ~/KscTool/<toolname>/<toolname>.sh`
- **`~/.bash_aliases`**: `alias <name>='_<tool>_main'`

현재 등록된 alias:

| alias | 함수 | 스크립트 |
|-------|------|----------|
| `fwd` | `_ftd_main` | `ftd/file_to_dev.sh` |
| `cpbak` | `_cpbak_main` | `cpbak/cpbak.sh` |
| `scs` | (직접 실행) | `svn/svn_commit.sh` |
| `rbc` | (직접 실행) | `build/rebuild_changed.sh` |
| `bep` | (직접 실행) | `build/build_error_parse.sh` |

---

## 6. 컬러/스타일 컨벤션

- **변수 prefix**: `_<TOOL>_` (예: `_CB_RED`, `_F_GREEN`)
- **구분선 함수**: `_<t>_ln()`, `_<t>_hd()`, `_<t>_sec()`
- **ANSI 코드 직접 사용** (tput 사용 금지 — 터미널 환경 무관)
- 컬러 팔레트는 ftd/cpbak 참조
- **파스텔톤 병행 사용**: 원색(Bold Red/Green/Yellow)과 함께 파스텔 계열 256색(`\e[38;5;NNNm`)도 적극 활용
  - 헤더·배너·구분선: 파스텔 (`\e[38;5;153m` 하늘, `\e[38;5;183m` 연보라, `\e[38;5;120m` 연두 등)
  - PASS/FAIL/WARN 상태값: 원색 (가독성 우선)
  - 참고 팔레트: `dv init` 출력 스타일 (밝고 부드러운 톤)

---

## 7. help 서브커맨드 (필수)

모든 서브커맨드와 옵션을 help에 표시해야 한다.  
`-h`, `--help`, 인자 없음 모두 help 출력.

---

## 8. 함수 네임스페이스

전역 함수 오염 방지를 위해 **모든 함수는 `_<toolname>_` prefix 사용**:

```bash
_cpbak_main()
_cpbak_init()
_cpbak_cmd_save()
_ftd_main()
_ftd_init()
```

---

## 9. README.md (권장)

각 도구 폴더에 README.md를 작성한다.  
내용: 왜 만들었나, 설치법, 사용법, 내부 동작 설명.  
AI가 작성한 경우 하단에 출처 표기: `_작성: Claude ... / 작성일: YYYY-MM-DD_`

---

_최종 갱신: 2026-04-03_
