# KscTool

개인 개발 자동화 도구 모음 (Git 관리, SVN 미포함)

## 폴더 구조

```
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
├── tools/                      # 기타 유틸리티
│   ├── obs.sh                  # OBS 제어 (alias: obs)
│   ├── gen_index.sh            # 인덱스 생성
│   └── claude_refresh.sh       # Claude Code 세션 초기화
└── README.md
```

## alias 등록 위치 (`~/.bash_aliases`)

| alias | 경로 | 설명 |
|-------|------|------|
| `fwd` / `ftd` | `ftd/file_to_dev.sh` | AP 파일 전송 |
| `scs` | `svn/svn_commit.sh` | SVN 커밋 |
| `bep` | `build/build_error_parse.sh` | 빌드 에러 파서 |
| `rbc` | `build/rebuild_changed.sh` | 변경분 재빌드 |
| `obs` | `tools/obs.sh` | OBS 제어 |

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
