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

## spec (spec.sh)

### [2.0.0] — 2026-04-03

#### 추가

- `open` — 재검색 루프: 열기/미매칭 후 `"다시 검색 [키워드/Enter=종료]"` 프롬프트
- `path <키워드>` — 규격서 파일 경로 출력 (열기 X, stdout으로 경로 반환)
- `scan` — 등록 경로 스캔 → 문서명 기준 최신 버전 PDF를 `latest/` 심볼릭 링크로 등록
- `scan add <경로>` / `scan rm <경로>` / `scan dirs` — 스캔 경로 관리
- 스캔 설정: `~/.devtools/spec/scan_dirs`

#### 변경

- 명령어 `specver` → `spec` (파일명 `specver.sh` → `spec.sh`)
- 인자 없는 키워드 단축: `spec IPv6` → `open` 자동 처리 + 재검색 루프

### [1.0.1] — 2026-04-03

#### 수정 (simplify)

- `_sv_open()` find 괄호 누락 버그 수정 (심볼릭 링크 과다 반환)
- `echo|xargs` 트림 → bash param expansion (fork 제거)
- `basename`/`dirname|sed` → `${f##*/}` / param expansion
- `find|grep -i` → `find -iname` (grep 서브프로세스 제거)
- `_sv_check()` 확장자 블랙리스트 → `*.pdf` 화이트리스트
- 공통 헬퍼 추출: `_sv_need_latest`, `_sv_open_file`, `_sv_fzf_pick`

### [1.0.0] — 2026-04-03

#### 추가

- `(없음)` — INDEX.md 파싱, 규격서 버전 + 파일 존재 여부 한눈에 출력
- `list` — latest/ 최신본만 표시 (fzf picker 또는 텍스트 목록)
- `list all` — Document/ 전체 PDF 스캔, latest/ 연결 여부 + 버전 표시
- `check` — latest/ 심볼릭 링크 유효성 검사
- `open <키워드>` — 키워드로 규격서 찾아서 xdg-open

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

### [2.3.0] — 2026-04-03

#### Added
- `_ftd_find_crt_window()` — xdotool로 SecureCRT 창 자동 감지 (디바이스명 매칭 우선)
- `_ftd_crt_paste()` — SecureCRT 창에 명령 자동 붙여넣기 (Ctrl+Shift+V)
- `_ftd_upgrade_confirm()` — sysupgrade 확인 박스 top-level 함수
- scan 파일 목록에 리비전 컬럼 표시 (`r123`)

#### Changed
- `_ftd_transfer`: CRT 창 → 시리얼 → 클립보드 순 fallback
- `_ftd_detect_serial`: 고정 포트 목록 → `/dev/ttyUSB* /dev/ttyACM*` 와일드카드
- Python serial: `termios` HUPCL 비활성화 — 포트 종료 시 연결 단절 방지
- `_ftd_find_crt_window`: xdotool search 2회→1회, 타이틀 캐시

---

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
