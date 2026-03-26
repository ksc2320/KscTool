# KscTool

개인 개발 자동화 도구 모음 (SVN 미포함, Git 관리)

## 폴더 구조

```
KscTool/
├── svn_commit.sh              # SVN 커밋 헬퍼 (alias: scs)
├── scripts/
│   ├── deploy/                # 배포 관련
│   │   └── fw_deploy.sh       # AP FW 자동 배포 (alias: fwd)
│   ├── build/                 # 빌드 관련 (docker 환경 적용 예정)
│   │   ├── build_error_parse.sh   # 빌드 에러 파서 (alias: bep)
│   │   └── rebuild_changed.sh     # SVN 변경분 재빌드 (alias: rbc)
│   └── claude_refresh.sh      # Claude Code 세션 초기화
└── README.md
```

## 스크립트 룰

- 새 스크립트는 **카테고리별 서브폴더**에 생성 (`deploy/`, `build/`, `debug/` 등)
- `~/.bash_aliases`의 `##ksc_scripts` 섹션에 alias 등록
- SVN 미포함 스크립트이므로 **컬러 효과 적극 사용**
- 완료 시 `git push`

---

## 스크립트 상세

### fwd — AP 펌웨어 자동 배포

```bash
fwd                    # $FW_NAME, $TFTP_PATH 환경변수 자동 사용
fwd 172.30.2.1         # 하위 AP IP 지정
fwd -n                 # 설정 초기화 업그레이드
fwd -p 80              # HTTP 포트 지정 (기본: 8080→80 자동 감지)
```

**자동 감지 항목:**
- FW 파일: `$FW_NAME` 환경변수 → tftpboot 내 최신 `.img`
- HTTP 포트: 8080 → 80 순서로 시도, 서버 없으면 **자동 시작**
- TFTP 경로: `$TFTP_PATH` → `/tftpboot`

**플로우:** HTTP 서버 확인(자동시작) → SSH 연결 → AP wget(크기 검증) → sysupgrade(확인) → 재부팅 대기+버전 표시

### bep — 빌드 에러 파서

```bash
make V=s 2>&1 | bep                    # 실시간 파싱
make V=s 2>&1 | tee build.log | bep    # 저장 + 파싱
bep build.log                          # 로그 파일 분석
```

에러(빨강)/경고(노랑)/패키지별 구분, 최종 카운트 요약.
*TODO: docker 빌드 환경 연동*

### rbc — SVN 변경분 재빌드

```bash
rbc        # 변경 패키지 감지 → clean+compile
rbc -d     # dry-run (목록만)
rbc -j4    # 병렬 빌드
```

`svn status` → feeds/davo, package 경로 매핑 → 해당 패키지만 빌드. build_dir 직접 수정 경고.
*TODO: docker 빌드 환경 연동*

---

## 프로젝트별 스크립트 (KscTool 외부)

| 스크립트 | 위치 | 용도 |
|----------|------|------|
| `ipv6_verify.sh` | `memo/10_projects/609h/ipv6_ap/` | IPv6 규격 검증 (14항목) |
| `ipv6_ap_apply.sh` | `memo/10_projects/609h/ipv6_ap/` | AP IPv6 설정 적용 |
| `ipv6_setup.sh` | `memo/10_projects/609h/ipv6_server/` | 테스트 서버 구축 |

---

## 환경

- 개발PC: Ubuntu (172.30.1.3, USB 이더넷)
- AP 접속: SSH root@172.30.1.x (하위 AP: 172.30.2.x~)
- HTTP 서버: `startserver` alias (python3 :8080, /tftpboot)
