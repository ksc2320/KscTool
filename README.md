# KscTool

개인 개발 자동화 도구 모음 (SVN 미포함, Git 관리)

---

## 스크립트 목록

### 빌드 & 배포

| 스크립트 | alias | 설명 |
|----------|-------|------|
| `svn_commit.sh` | `scs` | SVN 커밋 헬퍼 (대화형 커밋 도구) |
| `scripts/fw_deploy.sh` | `fwd` | **AP 펌웨어 자동 배포** — `dv cp fw` 후 실행. SSH로 AP 접속 → wget 다운로드(크기 검증) → sysupgrade 실행. HTTP 서버 자동 시작, 재부팅 완료 대기까지 지원 |
| `scripts/rebuild_changed.sh` | `rbc` | **SVN 변경분 자동 재빌드** — `svn status`로 변경 파일 감지 → feeds/davo, package 등 경로별 패키지 매핑 → 해당 패키지만 clean+compile. `-d`로 dry-run |
| `scripts/build_error_parse.sh` | `bep` | **빌드 에러 파서** — `make V=s 2>&1 \| bep` 형태로 사용. 에러(빨강)/경고(노랑)/패키지별 구분, 최종 카운트 요약 |

### 디버깅 & 검증

| 스크립트 | alias | 설명 |
|----------|-------|------|
| `scripts/ipv6_verify.sh` | `v6chk` | **IPv6 규격 검증** — AP SSH 접속 후 14개 항목 자동 테스트 (wan6 DHCPv6, LAN PD/SLAAC, RA 플래그, firewall, ICMPv6, DNS). 컬러 PASS/FAIL 리포트. `-v`로 상세 |
| `scripts/ap_monitor/ap_log.sh` | `aplog` | **AP 로그 실시간 모니터** — `logread -f` 스트리밍 + 컬러 필터링. `[ksc]`(시안), 에러(빨강), 경고(노랑), 네트워크(초록) 자동 분류. 추가 필터/저장 모드 지원 |

### 유틸리티

| 스크립트 | 설명 |
|----------|------|
| `scripts/claude_refresh.sh` | Claude Code 세션 초기화 |

---

## 사용법

### fw_deploy.sh — AP 펌웨어 자동 배포

```bash
fwd              # 기본 AP (172.30.1.1)
fwd 172.30.2.1   # AP IP 지정
fwd -n           # 설정 초기화 업그레이드
fwd 172.30.2.1 -n
```

**플로우**: 로컬 FW 파일 확인 → HTTP 서버 체크 → SSH 연결 → AP wget(크기 검증) → sysupgrade(확인 후) → 재부팅 대기

### ipv6_verify.sh — IPv6 규격 검증

```bash
v6chk              # 기본 AP
v6chk 172.30.2.1   # AP IP 지정
v6chk -v           # 상세 출력
```

### build_error_parse.sh — 빌드 에러 파서

```bash
make V=s 2>&1 | bep                          # 실시간 파싱
make V=s 2>&1 | tee build.log | bep          # 저장 + 파싱
bep build.log                                # 로그 파일 분석
```

### rebuild_changed.sh — SVN 변경분 재빌드

```bash
rbc        # 변경 패키지 감지 → 빌드
rbc -d     # dry-run (빌드 안하고 목록만)
rbc -j4    # 병렬 빌드
```

### ap_log.sh — AP 로그 모니터

```bash
aplog                       # 기본 (에러/경고/[ksc] 필터)
aplog 172.30.2.1            # AP IP 지정
aplog 172.30.1.1 dhcp       # dhcp 관련만
aplog -a                    # 전체 로그 (컬러만)
aplog -s                    # 파일 저장 병행
```

---

## 설정

각 스크립트 상단의 기본값 수정:

```bash
DEFAULT_AP_IP="172.30.1.1"   # AP IP (기종/환경별 변경)
HOST_IP="172.30.1.3"         # 개발PC USB이더넷 고정 IP
HTTP_PORT="8080"             # python3 http.server 포트
```

---

## 환경

- 개발PC: Ubuntu (172.30.1.3, USB 이더넷)
- AP 접속: SSH root@172.30.1.x
- HTTP 서버: `startserver` alias (python3 :8080, /tftpboot)
