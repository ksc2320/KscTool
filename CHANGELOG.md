# KscTool CHANGELOG

버전 형식: `MAJOR.MINOR.PATCH`  
각 도구별 독립 버전 관리 → 해당 도구명으로 섹션 구분.

---

## dvbuild (build/dvbuild.sh)

### [1.2.0] — 2026-08-28

#### 변경 내용
- **부분 빌드에 패키지 이름만 주면 된다.** 피드 경로는 `tmp/.packageinfo`에서 찾는다.
- 754 owrt 서브트리 부분 빌드 지원 추가. `turbox_build.sh`엔 패키지 단위 옵션이 없어서(`--ap-i`는 이미지 단위) make를 직접 건다.

#### 사용법
- `dvbuild 609h dvmgmt` / `dvbuild 754 dvmgmt` — 전체 경로 대신 이름만
- 전체 make 타겟(`package/.../compile`)을 주면 그대로 쓴다. 기존 방식도 그대로 동작.

#### Fixed / Changed
- **피드 디렉터리가 트리마다 다르다.** 609H는 `package/feeds/davo/dvmgmt`인데 754는 `package/feeds/tcatctl/dvmgmt`다. 754 안에서도 `dvdyngsp`만 `davo` 피드라 손으로 쓰면 틀린다 — 그래서 `.packageinfo`를 정본으로 삼는다.
- `kmod-*`처럼 `Package:` 이름이 디렉터리명과 다른 경우 디렉터리명으로 재시도한다(`dvdyngsp`가 이 경우).

---

### [1.0.0] — 2026-08-28

#### 변경 내용
- 신규 도구. **프로젝트별 빌드 명령을 기억해서 도커 안에서 대신 실행한다.** 호스트에서 make를 돌려 host/target 툴체인이 섞이는 사고를 원천 차단한다.
- 컨테이너가 꺼져 있으면 켜고, **켠 채로 둔다**(끄지 않는다 — 나중에 터미널 붙일 수 있으니).
- **이미 빌드 중이면 아무것도 하지 않고 종료(exit 3)한다.** 같은 트리를 동시에 빌드해 `build_dir`이 깨지던 문제를 막는다.
- 빌드는 **전용 새 터미널 창**에 띄운다. 열려있는 창에 키를 넣지 않으므로 키보드·한글 IME를 뺏지 않는다.

#### 사용법
- `dvbuild 609h` — 609H 전체 빌드 (`bear --append -- make -j6 V=s`)
- `dvbuild 609h package/feeds/davo/dvmgmt/compile` — 부분 빌드
- `dvbuild 754` — DVF-754 `./dvbuild_mode.sh 3` (ab). 인자로 모드 지정: 0 flat / 1 fastboot / 2 fota / 3 ab
- `dvbuild -n <proj>` — 새 창 없이 현재 셸에서. `dvbuild log` — 마지막 빌드 로그 tail -f
- 로그는 `~/.devtools/dvbuild/logs/` 에 남고 `latest` 심볼릭 링크가 항상 최근 것을 가리킨다.

#### 구현 메모
- `docker exec`에 **`-t` 필수**. `dvbuild_mode.sh`가 내부에서 `tee /dev/tty`를 쓰는데, pty가 없으면 `No such device or address`로 죽으면서 마지막 줄 판정이 깨져 **빌드 성공을 BUILD FAIL로 오판**한다.
- 754는 `-u $(id -u):$(id -g)`로 진입(컨테이너 내 `turbox`), 609H는 기본 사용자(`davo`) 그대로.

---

## scripts (scripts/backup_memory.sh)

### [1.0.0] — 2026-08-28

#### 변경 내용
- 신규. **Claude/Codex 공용 메모리 저장소가 아무 백업도 안 되고 있었다.** `.git` 은 있는데 커밋하는 게 아무것도 없어서 첫 커밋("Initialize Codex git baseline") 이후 4개월치 변경이 통째로 미커밋 상태였다.
- 원인: `~/memo/.auto_sync.sh` 는 `~/memo` 만 훑는데, 메모리는 심볼릭 링크로 걸려 있고 git 은 링크를 따라가지 않는다. KscTool·memo·dotfiles 는 각자 cron 이 있었지만 메모리만 빠져 있었다.
- cron 등록: `17 */4 * * *` (memo 의 `47 */4` 와 겹치지 않게 어긋냄)

#### 구현 메모
- 대상 경로는 `readlink -f ~/.codex/memories` 로 잡는다. 같은 폴더가 세 경로로 보이므로 실체를 찍어야 한다.
- 원격(origin)이 있으면 push 까지, 없으면 로컬 커밋만. **지금은 원격이 없어 로컬 커밋뿐이다** — 디스크가 죽으면 같이 죽는다.
- 메모리에는 사내 이슈·규격 내용이 있으므로 원격을 붙인다면 반드시 비공개 저장소로.

---

## notirun (noti/notirun.sh)

### [1.0.0] — 2026-08-28

#### 변경 내용
- 신규 도구. 오래 걸리는 명령을 감싸서 **끝나면 휴대폰으로 알린다.** 40분짜리 빌드를 걸어놓고 자리를 떠도, 끝났는지 보러 돌아올 필요가 없다. 빌드 전용이 아니라 아무 명령이나 감싼다.
- 성공은 `info`(디스코드 기록만), **실패는 `urgent`(폰이 울린다)**. 실패했을 때만 방해받는다.

#### 사용법
- `notirun make -j8` / `notirun -t "609H 전체빌드" make -j8` / `notirun -f aptest smoke --live`(실패만 알림)
- alias 두 개: `notirun`(본명)과 `ntr`(짧게). 같은 스크립트다.
- 화면 출력은 그대로 보이고(`tee`), **종료코드도 원래 명령 것을 그대로 돌려준다**(`PIPESTATUS`). 파이프·`&&` 체인에 그대로 끼워 쓸 수 있다.
- 로그는 `~/.devtools/noti/runs/` 에 남고 최근 50건만 유지. 알림 본문에 로그 경로가 들어간다.

#### 구현 메모
- 실패 알림에는 로그 끝 8줄이 아니라 `error|undefined reference|Traceback` 등이 걸린 줄을 뽑는다. 빌드 로그는 끝부분이 make 잡음이라 원인이 안 보인다.
- 그때 **첫 두 줄(실행한 명령 자체)은 건너뛴다.** 안 그러면 명령줄에 들어있는 단어를 에러로 잡는다.

---

## noti (noti/noti.sh)

### [1.2.0] — 2026-08-28 (dcbot 미검증)

#### 변경 내용
- **`dcbot.sh` 추가 — 세션이 안 떠 있어도 디스코드로 지시하고 답을 받는 상주 봇.** PC 가 켜져 있으면 항상 돌면서, 채널에 들어온 말을 `claude -p` 로 처리해 답을 채널에 되돌린다. 회사 밖에서도 된다.
- **겹침 방지**: 살아있는 세션이 `dclisten watch` 로 채널을 보고 있으면(60초 안에 `watcher.heartbeat` 갱신) 봇은 양보하고 손대지 않는다. 한 메시지에 두 번 답하는 걸 막는다. 메시지 앞에 `!` 를 붙이면 세션이 보고 있어도 봇이 처리한다.
- `dclisten watch` 가 심장박동 파일을 남기도록 수정 (위 양보 규칙의 근거).
- `dcsession.sh cwd <세션ID>` 추가 — 그 세션의 작업 폴더. 봇이 같은 폴더에서 돌기 위해 필요.

#### 세션 연결 방식
- 알림에 답장 → 그 세션 대화를 읽어 **맥락으로 넣고 새 봇 세션**에서 답한다. 살아있을 수 있는 세션을 헤드리스로 이어받으면 그쪽 기록이 꼬이므로 건드리지 않는다.
- 봇 답변에 답장 → `--resume` 으로 그 봇 세션을 이어간다 (봇이 `--session-id` 로 만든 세션이라 안전).
- 그냥 메시지 → 30분 안에 쓰던 봇 세션이 있으면 이어가고 없으면 새로 만든다.

#### 권한 (중요)
- 기본 `read` 모드 = `--allowedTools Read Grep Glob`. **Bash·수정 도구를 주지 않는다.** COMMON.md §14 "명령 이름만 보는 allowlist 는 만들지 않는다"(`find -delete`, `sed -n -i` 는 프리픽스로 못 거른다)를 그대로 따른 것.
- `NOTI_BOT_MODE=full` 이면 `bypassPermissions`. 폰에서 들어온 말이 그대로 PC 에서 실행된다는 뜻이라 기본값이 아니다.
- 화이트리스트 밖 사용자의 메시지는 처리하지 않는다. 봇 토큰은 `curl --config` 로 넘겨 `ps` 에 노출되지 않는다.

#### Fixed
- **`--allowedTools` 가 프롬프트를 삼키던 버그.** 값을 여러 개 받는 옵션이라 `--allowedTools Read Grep Glob "질문"` 이면 질문까지 도구 이름으로 먹고 `Input must be provided either through stdin or as a prompt argument` 로 죽는다. 쉼표 형식(`Read,Grep,Glob`)으로 바꾸고 **프롬프트는 표준입력으로** 넘긴다. 이걸 못 잡았으면 봇이 모든 질문에 실패했을 것.

#### 상태
- 서비스 기동·자동 실행 등록·세션 양보(heartbeat) 확인 완료. 헤드리스 `claude -p` 응답도 확인.
- 디스코드 실메시지 왕복은 사용자 시험 대기.

---

### [1.1.0] — 2026-08-28

#### 변경 내용
- **레벨이 곧 라우팅이 됐다.** 사용자가 디스코드 알림을 꺼두고 필요할 때만 보기로 해서, `info`/`warn`은 디스코드에 조용히 쌓고 폰(ntfy)은 `urgent`에서만 울린다. 완료 보고까지 폰을 울리면 정작 야간에 장비가 멈췄을 때 무시하게 된다.
- **디스코드 답장으로 지시를 받는다.** 알림을 보낼 때 `?wait=true`로 메시지ID를 받아 `메시지ID→세션ID→제목`을 `threads.tsv`에 적어둔다. 사용자가 그 알림에 "답장"하면 어느 질문에 대한 답인지 복원된다. 무인 시험 중 막혔을 때 물어보고 이어서 진행할 수 있다.
- 비밀값을 화면·대화 기록에 남기지 않는 `setkey` 추가. 봇 토큰을 채팅에 붙여넣지 않아도 된다.

#### 사용법
- `noti setkey <bot-token|webhook|ntfy-topic|tg-token>` — 숨김 입력
- `noti -s <세션ID>` — 답장 매핑에 쓸 세션 지정 (기본 `$CLAUDE_CODE_SESSION_ID`)
- 설정 `NOTI_ROUTE_INFO` / `NOTI_ROUTE_WARN` / `NOTI_ROUTE_URGENT` 로 레벨별 채널 지정

#### 신규 스크립트
- `dclisten.sh` — 디스코드 채널 폴링, 새 메시지를 한 줄씩 stdout 으로. Monitor 도구가 이벤트로 받는다. `check`(토큰·권한·본문 읽기 점검) / `once` / `watch` / `reset`
  - 화이트리스트(`NOTI_DISCORD_ALLOW_USER`) 밖의 메시지는 지시로 취급하지 않는다. 이 채널은 작업 PC에 명령을 넣는 입구라 필수.
  - 봇 토큰이 `ps` 목록에 노출되지 않도록 `curl --config` 로 헤더를 넘긴다.
- `dcsession.sh` — 알림을 보낸 그 세션의 대화를 읽는다. `list` / `ctx <세션ID> [턴수] [full]` / `path` / `last`
  - 사용자가 작업 도중 끼워 넣은 말은 `type=user`가 아니라 `queue-operation(enqueue)`로 저장된다. 그게 방향 전환인 경우가 많아 함께 읽는다.

#### Fixed
- ntfy 한글 제목 깨짐(모지바케). HTTP 헤더 방식 → JSON 발행 엔드포인트로 교체.
- 같은 메시지ID가 여러 줄일 때 답장 조회가 가장 오래된 항목을 잡던 문제 → 최근 항목 기준으로 변경.

---

### [1.0.0] — 2026-08-27

#### 변경 내용
- 신규 도구. 빌드·야간 무인 시험처럼 오래 걸리는 작업 결과를 휴대폰으로 바로 받는다. 자리를 비운 사이 끝났는지·막혔는지 확인하러 PC 로 돌아올 필요가 없다.
- 채널 3종(디스코드 웹훅 / ntfy / 텔레그램 봇)을 같은 명령으로 쓴다. 한 채널이 죽어도 다른 채널로 보내면 되므로 특정 서비스에 묶이지 않는다.

#### 사용법
- `noti init` — 설정 파일(`~/.devtools/noti/config`, 권한 600) 생성 + alias 등록
- `noti -t "제목" [-l info|warn|urgent] [-c discord,ntfy] "본문"` — 전송. 본문은 파이프로도 받는다
- `noti test` / `noti conf` (비밀값 마스킹) / `noti log [N]`
- `urgent` + `NOTI_DISCORD_MENTION` 이면 본인을 멘션해 채널 음소거를 뚫는다

#### 구현 메모
- 페이로드는 `jq` 로 만든다. 빌드 로그를 그대로 파이프해도 따옴표·개행·역슬래시가 깨지지 않는다.
- ntfy 는 HTTP 헤더에 한글을 실을 수 없어(모지바케) JSON 발행 엔드포인트를 쓴다.
- `curl -m 15`. 알림 실패가 호출한 쪽 작업을 막지 않도록 종료코드만 남기고 넘어간다.

---

## ttyusb (tools/ttyusb.sh)

### [1.1.0] — 2026-08-25

#### 변경 내용
- 신규 도구. 시리얼 어댑터를 어느 USB 포트에 꽂아도 권한·이름 문제 없이 바로 쓰게 만든다. `dv ap` 의 chown 수동 작업이 필요 없어진다.
- 어댑터마다 고정 이름을 붙일 수 있다. `/dev/ttyUSB0,1,2` 번호는 꽂는 순서·구멍마다 밀리지만 고정 이름은 안 바뀌므로, SecureCRT 세션이 엉뚱한 장비에 붙는 사고를 막는다.

#### 사용법
- `ttyusb` — 꽂혀 있는 포트 목록 (칩/시리얼번호/고정이름/권한/점유 프로세스)
- `ttyusb setup` — udev 규칙 설치. 한 번만 하면 된다
  - 권한 개방(0666, dialout) + ModemManager/brltty 가 새 포트를 붙잡지 못하게 차단
- `ttyusb name <포트> <이름>` — 그 어댑터에 고정 이름 부여 (예: `ttyusb name /dev/ttyUSB1 ttyAP2`)
  - 현재 할당: `ttyAP0`=FTDI A97FMUVA(609H 콘솔), `ttyAP1`=AB8ACZJA, `ttyAP2`=A505C34X, `ttyRELAY`=CH340 릴레이
  - 시리얼번호 없는 어댑터(CH340)는 칩 종류로만 잡으므로 같은 칩 2개면 이름이 겹친다 — 경고 출력
- `ttyusb free [포트]` — 포트를 물고 있는 프로세스 정리 + 묵은 락파일 제거. SecureCRT 는 탭 전체가 끊기므로 기본은 확인 프롬프트 (`-y` 로 생략)

#### Fixed / Changed
- 이름표를 `99-ttyusb-names.rules` 로 분리 — `setup` 을 다시 돌려도 붙여둔 이름이 안 날아간다
- 내부 sudo 를 `sudo -S`(stdin) 에서 `SUDO_ASKPASS` 방식으로 교체. `내용 | _t_sudo tee -a 파일` 패턴에서 sudo 가 그 내용을 비밀번호로 삼켜 append 가 조용히 실패했고, 반대로 비밀번호가 파일에 기록될 수 있는 구조였다

---

## dotfiles (.bash_functions)

### [1.1.0] — 2026-07-22

#### 변경 내용
- `dv td` 명령 추가 — JIRA에 나에게 할당된 미완료 이슈를 `~/memo/todo.md`의 `# TODO`에 자동 등록. 주중 09:00·13:15 cron으로도 자동 실행됨

#### 사용법
- `dv td` (별칭 `dv jr` / `dv jira` / `dv todo`) — 지금 바로 JIRA 내 업무를 todo.md에 갱신
- 안 할/묵힐 이슈는 todo.md `# 보류` 섹션으로 옮기면 재등록 안 됨

#### Fixed / Changed
- `davo_macro_tool` case에 `jr | jira | td | todo)` 추가, help(`dv help`)에 항목 추가
- 조회 스크립트 본체: `~/memo/.jira_todo.py` (외부 의존성 0, urllib). 자격증명은 `~/memo/.env`
- JQL에서 `SESUPPORT`(support) 프로젝트 제외 — 스크립트 상단 `EXCLUDE_PROJECTS` 로 조정

### [1.0.0] — 2026-07-14

#### 변경 내용
- `dv up` FW 파일 선택 목록이 최근 5개까지만 보이던 것을 15개로 확대 — 이전 버전으로 롤백할 때도 목록에서 바로 선택 가능

#### Fixed / Changed
- `_pick_file()` 내 `head -n 5`(fzf) / `head -n 3`(non-fzf select) → `head -n 15`로 통일

---

## aptest (aptest.sh)

### [1.4.0] — 2026-07-13

#### 변경

- 기본 `APTEST_SSH_OPTIONS`를 개발 AP용으로 변경: `StrictHostKeyChecking=no` + `UserKnownHostsFile=/dev/null`. 개발 AP는 재플래시할 때마다 호스트 키가 바뀌어 known_hosts가 매번 충돌(`Host key verification failed`)하는데, 검사해봐야 의미가 없어서 끈다. 인증은 SSH 공개키로만 한다.

#### 실기 검증

- **첫 --live 실기 6/6 PASS** (DV03-609H, 2026-07-13). 접속 3단 이슈 해소: dropbear OFF→콘솔 활성, 빈 비밀번호 dropbear 차단→공개키 인증, 재플래시 호스트키 변경→known_hosts 무시. 결과: `~/test/dv03_609h/ap_debug_smoke/RESULT.md`

### [1.3.0] — 2026-07-13

#### 추가

- `aptest ssh [원격명령...]` — AP로 SSH 접속하는 명령. 인자가 없으면 대화형 셸을 열고, 인자를 주면 원격 명령 한 번 실행 후 종료한다. 비밀번호는 기존 방식대로 개인 password 파일에서 실행 시점에만 읽어 환경변수(`SSHPASS`)로 sshpass에 전달하므로 프로세스 목록/화면에 노출되지 않는다.

#### 수정

- `login-file --enable-ssh`가 생성하는 uci 명령의 섹션명 오류 정정: `dropbear.main` → `dropbear.@dropbear[0]`. DV03-609H의 dropbear 설정 섹션은 이름 없는 섹션이라 기존 명령은 AP에서 Invalid argument로 실패한다.

### [1.2.0] — 2026-07-07

#### 추가

- `aptest login-file --enable-ssh` — 로그인 시퀀스 뒤에 dropbear enable/start uci 명령을 덧붙여, 콘솔/시리얼 붙여넣기 한 번으로 SSH를 켠다. DV03-609H KT 팩토리 기본값이 dropbear를 꺼두기 때문(재플래시/팩토리리셋마다 재발생). SVN 소스는 절대 수정하지 않아 다른 엔지니어의 빌드에 영향 없음.

#### 수정

- 기본 `APTEST_PORT`를 `22` → `6022`로 정정. DV03-609H KT dropbear 기본 `Port` 설정이 6022라서 기존 값으로는 SSH가 열려도 접속 실패.

### [1.1.0] — 2026-07-06

#### 추가

- DV03-609H 기본 모델을 KT 계열로 취급하고, `~/memo/personal/pswd/ap_pw.txt`를 런타임 비밀번호 소스로 참조
- `aptest credential` — 비밀번호를 출력하지 않고 모델/섹션/인덱스 해석 가능 여부만 확인
- `aptest login-file` — AP 콘솔/시리얼용 로그인 시퀀스 파일 생성
- `APTEST_CONSOLE_WAKE_ENTER=on` — AP 입력 전 Enter 한 번으로 프롬프트를 깨우는 흐름 반영

#### 보안

- 비밀번호 값은 KscTool/Git에 저장하지 않음
- SSH password 사용 시 Python 인자가 아니라 환경변수로만 전달

### [1.0.0] — 2026-07-06

#### 추가

- `aptest status` — 대상 AP, 설정 파일, 결과 저장 위치, live 실행 가드 확인
- `aptest smoke` — 기본 read-only smoke suite 미리보기(dry-run)
- `aptest smoke --live` — 사용자가 명시적으로 실기 테스트를 요청한 경우 AP SSH 테스트 실행
- `aptest script` — SSH가 막힌 이미지용 AP 콘솔/시리얼 실행 스크립트 생성
- `suites/smoke.json` — shell 응답, kernel/uptime, UCI network, ifstatus, dmesg/logread 수집

#### 운영 규칙

- DV03-609H SVN이 아니라 `~/KscTool`에서 관리
- Codex/Claude는 명시적 실기 테스트 요청이 없으면 live 실행 금지

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

### [1.0.1] — 2026-08-25

#### Fixed / Changed
- `--serial auto` 후보 목록을 glob(`/dev/ttyUSB*`)으로 교체 (ftd 2.14.1과 동일 이유). 스크립트 자체는 여전히 미검증·사용 금지 상태

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

### [2.14.1] — 2026-08-25

#### Fixed / Changed
- 시리얼 포트 탐색 목록을 `ttyUSB0/1/2` 하드코딩에서 glob(`/dev/ttyUSB*`)으로 교체 — 어댑터를 3개 이상 꽂으면 `ttyUSB3` 이상이 생기는데 목록에 안 떠서 선택할 수 없었다. `doctor` 진단 목록도 동일

### [2.14.0] — 2026-08-20

#### 변경 내용
- `dv up` / `dv file` / `dv dbg` 가 AP에 보내는 다운로드 명령에 **busybox tftp 폴백** 추가 — 901(DV01-901H)처럼 wget이 없는 기종에서 `wget: not found` 로 멈추던 것 해결
- `dv get`(fwdg)도 `tftp` 링크가 없는 기종을 위해 `busybox tftp -p` 폴백 추가

#### 배경 (901 조사 결과)
- 901 busybox 빌드 설정: `# CONFIG_WGET is not set` → wget 애플릿 자체가 컴파일 안 됨 (`nm busybox_unstripped`에 `wget_main` 없음)
- `package/Makefile:114-115` 가 이미지 생성 시 `/usr/bin/tftp`, `/usr/bin/ftpget` 링크를 삭제 → 링크만 없고 애플릿(`tftp_main`, `ftpgetput_main`)은 바이너리에 남아 있다
- 그래서 `busybox tftp` 직접 호출이 901에서 유일하게 되는 다운로드 경로. curl·uclient-fetch·dropbear 전부 미포함

#### Fixed / Changed
- `_ftd_fetch_cmd()` 신설 — `wget URL -O F || busybox tftp -g -r F IP` 한 줄 생성. 명령 생성 지점 2곳(`_ftd_transfer`, `_ftd_dbg`)이 이 함수만 사용
- 폴백은 wget 있는 기종(609H 등)에서 `||` 뒤가 실행되지 않으므로 동작 변화 없음
- 제약: busybox tftp 는 blksize 미지원(512B 고정) → **32MB 이상 파일은 tftp 경로로 못 받는다**. 901 이미지 23MB 는 문제 없음. 호스트 tftpd(`tftpd-hpa`, 루트 `/tftpboot`)가 떠 있어야 폴백이 동작

### [2.13.0] — 2026-08-19

#### 변경 내용
- AP를 `ping` 응답만으로 판정하던 것을 **MAC 앞 3바이트(다볼링크 `00:08:52`)까지 확인**하도록 변경 — 공인망 게이트웨이가 하필 `.254`라 AP로 오인되던 사고 해결
- AP를 MAC으로 확정하지 못하면 전송 헤더의 AP 줄에 `⚠ AP 미확인` 경고를 띄운다. IP 직접 지정(`dv up 172.30.1.254`)도 같은 기준으로 표시

#### 배경 (2026-08-19 실제 사고)
- USB 랜카드 2장 중 공인망 쪽(`220.120.246.233`)이 `ip -4 -o addr show` 목록에서 먼저 나왔고, 그 서브넷 게이트웨이 `220.120.246.254`가 ping에 응답
- 609H FW 2회분이 AP(`172.30.1.254`) 대신 게이트웨이 IP로 나갔다 (`history.log` 11:46 / 12:00). HTTP 서버 IP도 220 대역으로 맞춰져 AP는 `wget` 자체를 못 받음

#### Fixed / Changed
- `_ftd_is_ap_mac()` 추가 — `ip neigh` ARP 항목의 `lladdr` 앞 3바이트를 `FTD_AP_OUI`와 대조
- `_ftd_detect_network()` — ping 응답 후 OUI 확인까지 통과해야 확정. 확정 실패 시 **첫 ping 응답자**(기존 동작) → **첫 enx** 순으로 폴백하므로 회귀 없음
- `_DETECTED_AP_VERIFIED` 플래그 신설, `_ftd_print_header()`에서 경고 표시에 사용
- IP 직접 지정 경로에서 `_DETECTED_ENX_IF`가 갱신되지 않아 헤더에 엉뚱한 인터페이스명이 뜨던 것도 같이 수정
- `FTD_AP_OUI` 기본값 `00:08:52`. 다른 OUI 장비를 쓰면 `~/.devtools/ftd/config`에 공백 구분으로 추가

### [2.12.0] — 2026-08-06

#### 변경 내용
- SecureCRT 창을 고를 때 **어느 장비에 붙어 있는지(호스트명)** 를 같이 보여준다 — 창 제목은 `ttyUSB0/2` 뿐이라 제품 구분이 안 됐다
- 창마다 다른 장비가 붙어 있으면 **기본값(Enter) 없이 번호를 요구**한다. 미입력이면 전송하지 않고 중단 — 엉뚱한 AP에 명령이 들어가는 사고 방지

#### 사용법
- `fwd who` — 창별 접속 장비 확인. 시험/명령 전송 전에 대상 확정용
  ```
  1) Serial-ttyUSB2 - SecureCRT   smartair
  2) serial-ttyusb0 - SecureCRT   DV03-609H
  ```
- `fwdc` / `fwdg` / `fwd dbg` 등 CRT 경유 명령의 창 선택 목록에도 호스트명이 함께 뜬다

#### Fixed / Changed
- `_ftd_crt_list()` 분리 — 창 열거·중복 제거 로직을 `_ftd_find_crt_window()`와 `fwd who`가 공유
- `_ftd_crt_host()` 추가 — SecureCRT 세션 로그(`$FTD_CRT_LOG_DIR`, 기본 `/hdd/ksc/securecrt_log`) 끝부분의 `root@호스트` 프롬프트 또는 로그인 배너에서 장비명 추출
- 기존 기본값은 `FTD_SERIAL_DEV` 힌트(`ttyusb`) 첫 매칭이라 ttyUSB2가 먼저 걸렸다 — 장비가 섞여 있으면 이 기본값을 쓰지 않는다

### [2.11.0] — 2026-07-27

#### 변경 내용
- `dv up` 이 AP IP를 배포할 FW 종류로 알아서 가른다 — DVF-754(`.zip`)는 `192.168.1.1`, 그 외 기종(`.img`)은 해당 서브넷의 `.254`. 754와 다른 기종 AP를 동시에 꽂아둬도 맞는 쪽으로 간다
- USB 랜카드가 2장 이상일 때 AP와 HTTP 서버 IP가 서로 다른 서브넷으로 잡혀 AP가 `wget` 을 못 받던 문제 해결 — 이제 한 짝으로 고른다

#### 사용법
- `dv up` — FW가 `.zip`이면 754 AP(`.1`), `.img`면 `.254`로 자동. `dv set` 프로젝트명과 무관
- `dv up 192.168.1.x` — 직접 지정도 그대로. 이때 HTTP 서버 IP도 같은 서브넷 enx로 맞춰짐
- 고정하고 싶으면 `fwd set` 에서 `FTD_AP_IP` 를 IP로 지정 (auto 해제)

#### Fixed / Changed
- `_ftd_ap_octet_for_fw()` 추가 — `.zip`=1 / 그 외=254. `_ftd_deploy` 의 `davo_upgrade`/`sysupgrade` 분기와 같은 기준이라 어긋나지 않음
- `_ftd_enx_list()` 추가, `_ftd_detect_network()` 가 후보 옥텟을 인자로 받아 ping 응답하는 (enx, 호스트IP, AP IP) 한 짝을 확정. 인자 없으면 `254 → 1` 순서 (cmd/ssh/reboot 용)
- 판단 근거로 `NOW_PROJECT`(`dv set`)를 쓰지 않음 — 최신화가 보장되지 않아 잘못된 기종으로 flash 될 위험이 있음
- `up` 은 옥텟을 하나로 고정해 탐색 (다른 기종 AP로 넘어가지 않게), 전부 무응답이면 첫 enx 기준 폴백 (기존 동작 유지)
- 검증: `_ftd_detect_network` 자체 테스트 — ping/enx 스텁으로 6케이스 (754 단독·혼재·FW 없음·전부 무응답) 통과

### [2.10.0] — 2026-07-22

#### 변경 내용
- `dv up <파일명>` 으로 배포할 FW를 직접 지정 가능 — 선택 목록/자동선택을 건너뛰고 그 파일로 바로 배포
- `.zip` 파일은 DVF-754 방식(`davo_upgrade`)으로 자동 전환 — `.img` 는 기존대로 `sysupgrade`

#### 사용법
- `dv up fw.img` — 경로/파일명 직접 지정 (없는 이름이면 scan 경로에서 찾음)
- `dv up DVF-754X_..._r243.zip` — wget 으로 AP에 받은 뒤 `davo_upgrade /tmp/<파일>` 로 업데이트

#### Fixed / Changed
- `_ftd_up`: 인자 파싱에 `*.img|*.zip|*/*` → `fw_override` 추가, 지정 시 모드(dv/path/scan) 무시하고 해당 파일 복사
- `_ftd_transfer`: 파일 확장자로 upgrade 명령 분기(`sysupgrade`/`davo_upgrade`), 확인·dry-run 메시지도 실제 명령을 표시
- `_ftd_upgrade_confirm`/`_ftd_print_dry` 시그니처를 명령 문자열 기반으로 변경

### [2.9.1] — 2026-07-15

#### Fixed
- SecureCRT 창 선택 프롬프트가 실제 세션 수보다 부풀려 표시되던 문제 수정. `xdotool search --name SecureCRT`는 세션 하나당 frame/wrapper/내부 terminal-widget이 겹쳐 잡히는데(제목이 같은 창 반복 + 제목 없는 위젯), 이를 그대로 나열해 세션 2개가 6개로 보였음. 제목 기준 중복 제거 + 이름 붙은 창이 있으면 제목 없는 순수 "SecureCRT" 위젯은 선택지에서 제외하도록 수정.

### [2.9.0] — 2026-07-15

#### 추가

- `fwdc`(`ftd cmd`)/`fwdg`(`ftd get`)/`dv up`/`dv file`가 공유하는 `_ftd_find_crt_window`에도 동일한 선택 프롬프트 적용. SecureCRT 창이 2개 이상 열려 있으면 번호 선택 프롬프트를 띄우고, Enter는 디바이스 힌트에 매칭된 창(없으면 1번)을 기본 선택. 이전에는 여러 창이 열려 있어도 `xdotool search` 결과의 첫 번째 창을 조용히 골랐음.

### [2.8.0] — 2026-07-15

#### 추가

- `dv up`/`ftd up` 시리얼 자동 감지(`FTD_SERIAL_DEV=auto`)에서 정상 응답하는 ttyUSB/ttyACM 포트가 2개 이상이면 번호 선택 프롬프트 표시. Enter는 1번(보통 ttyUSB0)을 기본 선택하고, 다른 번호를 입력하면 해당 포트로 전송. 이전에는 여러 대가 붙어 있어도 항상 첫 번째로 응답하는 포트를 조용히 골라 다른 포트로 보낼 방법이 없었음.

### [2.7.0] — 2026-07-13

#### 추가

- `dv ssh [원격명령...]` / `dv smoke [--live]` — aptest 위임 명령 추가 (`ftd ssh`/`ftd smoke`도 동일). 비밀번호 해석·포트(6022)·실기 가드 로직은 aptest가 소유하고 ftd는 진입점만 제공한다. aptest 미설치 환경에서는 안내 후 종료.

### [2.6.2] — 2026-07-02

### 변경 내용
- 셸을 켠 뒤 USB 랜카드를 꽂거나 인터페이스 IP가 나중에 할당/변경돼도 `dv up`/`ftd`가 AP·서버 IP를 매번 새로 감지 — 더 이상 낡은 `192.168.1.254` / `127.0.0.1`로 멈추지 않음

### Fixed
- `_ftd_detect_network`가 source 시점(셸 시작 시)에 딱 1회만 실행돼 캐시되던 문제 → `_ftd_main` 진입 시마다 재감지하도록 변경
  - 증상: enx가 `172.30.1.3`인데도 헤더가 `AP 192.168.1.254 (enx...)`, `Host 127.0.0.1:80`으로 뜨고 AP ping이 무한 대기
  - 원인: 셸 시작 시 enx에 IPv4가 없어 `_DETECTED_*`가 빈 값으로 캐시 → 이후 IP가 붙어도 폴백값을 계속 사용

### [2.6.1] — 2026-07-02

### 변경 내용
- USB 랜카드가 2개 이상일 때 `dv up`/`ftd`가 엉뚱한 enx 인터페이스를 골라 AP ping이 실패하던 문제 수정

### Fixed
- `_ftd_detect_network`: 인터페이스 이름을 `ip link`의 첫 enx로 뽑던 것을 → **IPv4 주소를 실제로 가진 enx**로 변경. 이름과 감지 IP(HOST/AP)가 항상 일치하도록 함
  - 증상: 헤더에 `AP 172.30.1.254 (enxb0386cf16748)`처럼 IP 없는 인터페이스가 표시되고 AP 응답 없음
  - 원인: `_DETECTED_ENX_IF`는 인덱스 순 첫 enx, `_DETECTED_HOST_IP`는 inet 가진 enx → 불일치

### [2.6.0] — 2026-04-15

#### Added
- `fwd get <remote> [local]` / `fwdg` — AP→host 파일 회수 (AP-initiated tftp put). BusyBox `tftp -p`로 host tftpd(`/tftpboot`)에 push, 30s size-stable 폴링. 기존 파일은 `.bak` 자동 백업
  - 배경: dropbear 비활성 이미지에서 scp 대체 경로 필요. `/tftpboot` 인프라 재활용
  - 주의: tftpd `--create` 옵션 필수, `-r`는 tftpd 루트 기준 상대경로

---

### [2.5.10] — 2026-04-06

#### Fixed
- `_ftd_crt_paste`: 기본값 `type` 복귀, delay 20ms → 1ms — clip(ctrl+v)은 SecureCRT에서 동작 안 함, type이 범용적이며 delay 줄여서 체감 속도 문제 해결
- `_ftd_find_crt_window`: child 창 탐색 유지 (type 모드 정상 동작에 필요)

---

### [2.5.9] — 2026-04-06

#### Fixed
- `_ftd_crt_paste`: `ctrl+shift+v` → `ctrl+v` 수정 — SecureCRT는 Ctrl+V 붙여넣기 사용
- `_ftd_find_crt_window`: clip 모드도 child 창 탐색 복구 — child로 보내야 키 입력 동작

---

### [2.5.8] — 2026-04-03

#### Fixed
- `_ftd_find_crt_window`: `grep -oP '0x[0-9a-f]+'` 가 한 줄에서 복수 hex 추출 → `printf` 실패 버그
  - xwininfo 출력에 `0x<wid> ... 1 child: 0x<child>` 형태로 두 값이 포함될 때 발생
  - `grep -m1 -oP` 로 수정 — 첫 번째 매치만 취득

---

### [2.5.7] — 2026-04-03

#### Added
- `_ftd_clip_write()` — xclip/xsel 클립보드 쓰기 헬퍼 (4곳 중복 제거, printf 안전 처리)

#### Changed
- `FTD_CRT_PASTE_MODE` 기본값 `type` → `clip` — clip이 속도·일관성 모두 우월
- `_ftd_crt_paste`: 80자 임계값 자동전환 제거 → 모드로만 통일 (y 확인 후 느린 문제 해결)
- `_ftd_crt_paste`: `windowraise` 제거 — `windowfocus --sync`이 raise 포함, 중복 서브프로세스 불필요
- `_ftd_crt_paste`: `windowfocus --sync` + `sleep 0.2` if/else 밖으로 이동 (DRY)

#### Fixed
- `_ftd_transfer`: sysupgrade 명령 전송 후 터미널 포커스 복귀 누락 수정
- `_ftd_transfer`: wget 명령 전송 후 터미널 포커스 복귀 — "wget 완료 후 Enter..." 시 CRT 포커스 빼앗기 문제 해결

---

### [2.5.6] — 2026-04-03

#### Added
- `FTD_CRT_PASTE_MODE` — CRT 명령 전송 방식 선택: `type` (xdotool 직접 입력, 기본) / `clip` (클립보드 + Ctrl+Shift+V, Plan B)
- `init` [7/9] 스텝: 전송 방식 선택 → config에 자동 저장

#### Changed
- `_ftd_find_crt_window`: `clip` 모드 시 xwininfo child 탐색 스킵 (parent 창으로 충분)
- `_ftd_find_crt_window`: `resolved_wid` 중간 변수로 루프 변수 재할당 제거 (simplify)
- `_ftd_find_crt_window`: `grep -m1` 으로 head -1 서브프로세스 제거 (simplify)
- `_ftd_crt_paste`: `clip` 모드 시 xclip/xsel → Ctrl+Shift+V 경로 분기

---

### [2.5.2] — 2026-04-03

#### Added
- `_ftd_crt_key()` — 키 이벤트 전송 (Ctrl+C 등)
- `ap c` / `ap ctrl-c` — SecureCRT에 Ctrl+C 전송
- `~/.devtools/ftd/presets` 초기 상용구: login, rf, passwd (ap.sh 동일)

---

### [2.5.1] — 2026-04-03

#### Fixed
- CRT paste 후 포커스가 SecureCRT에 머물던 문제 — `getactivewindow` 저장 후 완료 시 복귀
- `ap preset` 명령이 AP에 전송되던 문제 — `ap()` 함수로 변경 (preset → `fwd preset`, 나머지 → `fwd cmd`)
- `.bash_aliases`의 `ap` alias → `file_to_dev.sh _ftd_register()` 내 함수로 이동

---

### [2.5.0] — 2026-04-03

#### Added
- preset 시스템 (`~/.devtools/ftd/presets`) — `fwd preset set/rm/list`
- `ap` alias — `fwd cmd` 단축어
- `_ftd_cmd`: 다단계 명령 지원 (`cmd1|cmd2|cmd3`)
- `_ftd_cmd`: xdotool 미설치 시 명확한 오류 및 설치 힌트 출력
- doctor/init: xdotool 패키지 체크 추가

---

### [2.4.1] — 2026-04-03

#### Fixed
- `_ftd_cmd`: 시리얼 fallback 완전 제거 — 포트를 열지 않으므로 HUPCL SecureCRT 재연결 원천 차단
- `_ftd_detect_serial` probe: HUPCL 비활성화 후 close — `fwd up` 등 시리얼 감지 시에도 재연결 방지
- `_ftd_crt_paste`: `windowraise` 추가 + `--clearmodifiers` (ap.sh 동작 방식과 통일)

---

### [2.4.0] — 2026-04-03

#### Added
- `fwdc` alias — `fwd cmd` 단축어 (`.bash_aliases`)

#### Changed
- `_ftd_cmd`: CRT 창 → 시리얼 → 클립보드 순 감지 (시리얼 미감지 시 SecureCRT reconnect 방지)
- `_ftd_cmd`: 명령 박스 항상 상단 출력 후 전송 결과 표시로 UX 통일

---

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
