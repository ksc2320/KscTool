# KscTool

개인 개발 자동화 도구 모음 (Git 관리, SVN 미포함)

## 폴더 구조

```text
KscTool/
├── ftd/                        # AP 파일 전송 도구
│   ├── file_to_dev.sh          # 메인 (alias: fwd / ftd)
│   └── config.sample           # 설정 샘플 (~/.config/ftd/config)
├── svn/                        # SVN 커밋 도구
│   ├── svn_commit.sh           # SVN 커밋 헬퍼 (alias: scs)
│   └── svn_commit.setting      # 커밋 설정
├── build/                      # 빌드 도구
│   ├── build_error_parse.sh    # 빌드 에러 파서 (alias: bep)
│   └── rebuild_changed.sh      # SVN 변경분 재빌드 (alias: rbc)
├── watch/                      # AP 로그 감시 도구
│   ├── dvwatch.sh              # 로그 감시 (alias: dvwatch)
│   └── dvcon.sh                # AP SSH 연결 (alias: dvcon)
├── aptest/                     # AP 실기 디버그 테스트 하네스
│   ├── aptest.sh               # 메인 (alias: aptest)
│   └── suites/smoke.json       # 기본 read-only smoke suite
├── tools/                      # 기타 유틸리티
│   ├── obs.sh                  # OBS 제어 (alias: obs)
│   ├── gen_index.sh            # 인덱스 생성
│   └── claude_refresh.sh       # Claude Code 세션 초기화
└── README.md
```

## alias 등록 위치 (`~/.bash_aliases`)

| alias | 경로 | 설명 |
| ----- | ---- | ---- |
| `fwd` / `ftd` | `ftd/file_to_dev.sh` | AP 파일 전송 |
| `scs` | `svn/svn_commit.sh` | SVN 커밋 |
| `bep` | `build/build_error_parse.sh` | 빌드 에러 파서 |
| `rbc` | `build/rebuild_changed.sh` | 변경분 재빌드 |
| `obs` | `tools/obs.sh` | OBS 제어 |
| `dvwatch` | `watch/dvwatch.sh` | AP 로그 감시 |
| `dvcon` | `watch/dvcon.sh` | AP SSH 연결 |
| `aptest` | `aptest/aptest.sh` | AP 실기 디버그 테스트 하네스 |
| `ucisnap` | `tools/ucisnap.sh` | UCI 설정 스냅샷/diff |
| `spec` | `tools/spec.sh` | KT 규격서 버전 현황 / 열기 / 경로 / 스캔 |

---

## ftd — AP 파일 전송 도구

`~/.bash_functions` 끝에서 source됨 → `fwd` / `ftd` / `dv up` / `dv file` 모두 사용 가능.

```bash
fwd init            # 최초 설치 마법사 (팀원 배포용)
fwd up              # FW 자동 선택 → 전체 배포
fwd up s            # fzf FW 선택
fwd up -n           # sysupgrade -n
fwd up dry          # dry-run
fwd file            # tftpboot 파일 선택 → AP wget
fwd cp <파일>       # 로컬 파일 → tftpboot
fwd cp              # fzf 파일 선택 → tftpboot
fwd cmd <명령>      # AP에 임의 명령 전송
fwd reboot          # AP 재부팅
fwd clean           # tftpboot 파일 정리
fwd set             # 설정 편집
fwd log             # 배포 이력
fwd doctor          # 환경 진단
```

설정: `~/.config/ftd/config` (chmod 600)

---

## watch — AP 로그 감시 / SSH 연결

```bash
dvcon                           # ftd config 기반 AP SSH 자동 연결
dvcon 192.168.1.254             # IP 직접 지정
dvwatch                         # SSH → logread -f 스트림
dvwatch -p "dying gasp"         # 패턴 하이라이팅
dvwatch -p ERROR -p WARN -s     # 멀티 패턴 + 세션 저장
dvwatch --serial                # 시리얼 모드 (EBUSY → SSH 자동 폴백)
dvwatch --serial /dev/ttyUSB1   # 포트 명시
dvwatch -f /tmp/sys.log         # 로컬 파일 감시
dvwatch --save-on-match -p PANIC  # PANIC 감지 시 자동 저장 시작
dvwatch sessions                # 저장된 세션 목록
```

설정: `~/.config/dvwatch/config` (없으면 ftd config 값 사용)
저장: `~/.config/dvwatch/sessions/YYYYMMDD_HHMMSS.log`

---

## aptest — AP 실기 디버그 테스트 하네스

Codex/Claude가 같은 방식으로 AP와 데이터를 주고받기 위한 테스트 진입점.

```bash
aptest status             # 대상 AP / live 실행 가드 확인
aptest smoke              # 기본 smoke suite 미리보기(dry-run)
aptest smoke --live       # 사용자가 명시적으로 실기 테스트를 요청한 경우에만 실행
aptest script             # SSH 불가 시 AP 콘솔/시리얼용 스크립트 생성
aptest credential         # 비밀번호 파일 해석 가능 여부 확인(값 출력 안 함)
aptest login-file         # 첫 Enter 포함 콘솔 로그인 시퀀스 파일 생성
aptest suite list         # suite 목록
```

설정: `~/.devtools/aptest/config`  
결과: `~/.devtools/aptest/artifacts/`
비밀번호 참조: `~/memo/personal/pswd/ap_pw.txt`의 설정 섹션을 실행 시점에만 읽음

운영 규칙:
- DV03-609H SVN에는 올리지 않는다.
- 기본 실행은 dry-run이다.
- 사용자가 직접 "테스트까지 직접해봐"라고 요청한 경우에만 `--live`를 붙인다.
- 비밀번호 원문은 KscTool/Git에 저장하지 않는다.

---

## svn — SVN 커밋 도구

```bash
scs    # SVN 커밋 (svn_commit.setting 기반)
```

---

## build — 빌드 도구

```bash
make V=s 2>&1 | bep          # 빌드 에러 파서
rbc                          # SVN 변경분 재빌드
rbc -d                       # dry-run
```

---

## 스크립트 추가 규칙

1. 기능별 폴더에 생성 (`ftd/`, `svn/`, `build/`, `tools/`)
2. `~/.bash_aliases` `#ksc_tools` 섹션에 alias 등록
3. SVN 미포함 → 컬러 효과 적극 사용
4. 완료 시 `git push`
