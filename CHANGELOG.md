# KscTool CHANGELOG

버전 형식: `MAJOR.MINOR.PATCH`  
각 도구별 독립 버전 관리 → 해당 도구명으로 섹션 구분.

---

## ucisnap (ucisnap.sh)

### [1.0.0] — 2026-04-03

#### 추가

- `save [레이블]` — UCI export 스냅샷 저장 (타임스탬프 + 레이블)
- `list` — 저장된 스냅샷 목록 (최신순, 레이블 컬러 표시)
- `diff [n1] [n2]` — unified diff (red/green 컬러, 기본: 최신 2개)
- `show [n]` — 스냅샷 내용 출력
- `restore [n]` — UCI 복원 (실행 전 자동 백업)
- `clean [n]` — 오래된 스냅샷 정리 (기본 30개 초과분)

---

## specver (specver.sh)

### [1.0.0] — 2026-04-03

#### 추가

- `(없음)` — INDEX.md 파싱, 규격서 버전 + 파일 존재 여부 한눈에 출력
- `list` — Document/ 전체 PDF 버전 스캔, latest/ 연결 여부 표시
- `check` — latest/ 심볼릭 링크 유효성 검사
- `open <키워드>` — 키워드로 규격서 찾아서 xdg-open
- 인자 없는 키워드도 `open` 단축으로 처리

---

## dvwatch (dvwatch.sh)

### [1.0.0] — 2026-04-03

#### 추가

- SSH / 시리얼 / 로컬 파일 소스 자동 전환 (`--serial`, `--ssh`, `-f`)
- 패턴 하이라이팅 `-p` (여러 개 가능, 컬러 순환). `[ksc]` 태그 항상 빨간색
- 세션 저장 `-s` / 패턴 감지 시 자동 저장 `--save-on-match`
- 마커 삽입 `Ctrl+\` — `─── MARK HH:MM:SS ───`
- 알림 `--notify` — notify-send / 터미널 벨
- `sessions` 서브 명령 — 저장 세션 목록
- ftd config 재활용 (AP IP, 시리얼 설정, 계정)

---

## dvcon (dvcon.sh)

### [1.0.0] — 2026-04-03

#### 추가

- ftd config 기반 AP SSH 자동 연결
- 인자로 IP 직접 지정 가능 (`dvcon 192.168.1.254`)
- sshpass 지원 (FTD_LOGIN_PASS 설정 시)

---

## ftd (file_to_dev.sh)

### [2.2.0] — 2026-04-03

#### 추가

- `_banner()` — ok/fail/warn 컬러 박스 (경과 시간 선택 표시)
- `_ftd_print_header()` — 단계 흐름 표시 `[1] 복사 ▸ [2] HTTP ▸ [3] wget (▸ [4] upgrade)`
- `_ftd_ping_check()` — 3회 재시도 + 점 애니메이션, 실패 시 계속 여부 확인
- `_ftd_wait_boot()` — `\r` 실시간 경과 타이머 + `_banner ok/warn` 결과 박스

#### 변경

- sysupgrade 확인 프롬프트 → 빨간 경고 박스 + 취소 시 `_banner warn`
- 파일 전송 완료 → `_banner ok`, 부팅 대기 완료 → `_banner ok (경과시간)`

---

### [2.1.0] — 2026-04-03

#### 추가

- scan 모드 `FTD_SCAN_DIRS` 설정 (공백 구분 다중 경로, 팀원 커스텀 가능)
- `_ftd_scan_fw_files` — build_dir/.git/.svn/node_modules 제외 탐색
- `_ftd_fzf_scan` — 날짜+크기+경로 표시 fzf picker
- `_ftd_detect_serial` EPERM/EBUSY 구분 → 클립보드 모드 시 이유 표시
- `ftd doctor` dialout 그룹 체크 + 포트별 권한/잠김 상태 표시
- `FTD_FW_NAME=''` 빈 문자열 = 원본명 유지 (`dv cp` 동일 동작)

#### 수정

- `${upgrade_n:+"-n"}` 항상 `-n` 전달되던 버그 (0 = non-empty 문제)
- scan 모드 `xargs ls -t` 다중 배치 정렬 깨짐 → `stat + sort -rn` 교체
- dv 모드 `send_file_to_tftp fw` → `FTD_FW_NAME` 불일치 "파일 없음" 오류
- fzf preview `awk "\$NF"` 이스케이프 오류 → ANSI-C 쿼팅 적용
- init wizard FTD_FW_NAME 기본값 `firmware.img` 하드코딩 → 빈 문자열

#### 변경

- `_ftd_do_copy(src, dst)` → `_ftd_do_copy(src, dst_dir)` + stdout으로 파일명 반환
- `send_file_to_tftp fw` → `send_file_to_tftp` (인자 없음, 원본명 유지)
- scan 모드 다중 루트 결과 전체 단일 sort (루트 간 mtime 비교 정확)
- `_ftd_scan_fw_files` `du`+`stat` 2회 → stat 단일 호출로 통합

---

### [2.0.0] — 2026-04-03 (초기 구현)

#### 추가

- `file_to_dev.sh` 단일 파일 통합 (source/직접실행 자동 분기)
- `init` 마법사 8단계 (패키지·FW모드·TFTP·IP·HTTP·시리얼·로그인·alias)
- FW 복사 모드 3가지: `dv` / `path` / `scan`
- `up`, `up s`, `up -n`, `up dry`, `file`, `cp`, `cmd`, `reboot`, `clean`, `set`, `log`, `doctor` 명령
- 시리얼 자동 감지 + SecureCRT 점유 시 클립보드 모드 자동 전환
- `dv up` / `dv file` 통합 (`_dv_extended_ftd`)
- `~/.config/ftd/config` (chmod 600, git 미포함)
- KscTool 폴더 구조 재편 (`ftd/` `svn/` `build/` `tools/`)

---

## cpbak (cpbak.sh)

### [1.0.0] — 2026-04-03

#### 추가

- SVN/Git 수정 파일 백업 & 원복 도구 초기 구현

---

## svn (svn_commit.sh)

### [1.x] — (버전 추적 시작 전)

---

## build

### bep (build_error_parse.sh) — 1.x

### rbc (rebuild_changed.sh) — 1.x

---

_이 파일은 KscTool에 새 기능/수정이 추가될 때마다 업데이트한다._
