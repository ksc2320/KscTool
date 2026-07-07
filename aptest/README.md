# aptest

AP 실기 디버그 테스트를 Codex/Claude가 같은 방식으로 실행하기 위한 KscTool 하네스다.

## 언제 쓰나

- 사용자가 직접 "테스트까지 직접해봐", "AP에 붙어서 돌려봐", "실기 테스트 실행해봐"라고 말했을 때
- 코드 리뷰/수정 뒤 실제 AP의 UCI, ifstatus, dmesg, logread 상태를 모아야 할 때
- SSH가 열려 있으면 SSH로 실행하고, SSH가 막힌 이미지는 AP 콘솔/시리얼용 스크립트를 생성한다.
- DV03-609H처럼 KT 계열 모델은 개인 비밀번호 파일을 참조해 실행 시점에만 비밀번호를 읽는다.

## 절대 규칙

- DV03-609H SVN에는 올리지 않는다. 이 도구는 `~/KscTool` Git 관리 대상이다.
- 기본 실행은 dry-run이다.
- Codex/Claude는 사용자의 명시적 실기 테스트 요청 없이는 `--live`를 붙이지 않는다.
- 비밀번호 원문은 KscTool/Git에 저장하지 않는다.
- 설정 변경, 재부팅, 서비스 재시작 같은 위험 동작은 기본 smoke suite에 넣지 않는다.

## 설치

```bash
~/KscTool/aptest/aptest.sh init
source ~/.bash_functions
source ~/.bash_aliases
```

AP 주소가 다르면:

```bash
aptest init --host 172.30.1.254 --user root --port 6022 --force
```

설정은 `~/.devtools/aptest/config`에 저장된다.
기본 모델은 `DV03-609H`, 기본 비밀번호 섹션은 `KT`다.
비밀번호 파일 기본값은 `~/memo/personal/pswd/ap_pw.txt`이며, 값은 화면에 출력하지 않는다.
기본 포트는 `6022`다 — DV03-609H KT 모델의 dropbear 기본 `Port` 설정이 22가 아니라 6022이기 때문(`davo/files/etc/ori.config/dropbear`).

## 사용

상태 확인:

```bash
aptest status
```

비밀번호 해석 가능 여부 확인:

```bash
aptest credential
```

비밀번호 값과 길이는 출력하지 않는다.

명령 미리보기:

```bash
aptest smoke
```

사용자가 명시적으로 실기 테스트를 요청한 경우:

```bash
aptest smoke --live
```

SSH가 막힌 경우:

```bash
aptest script
```

생성된 `/tmp/aptest_smoke.sh`를 AP 콘솔/시리얼에서 실행한 뒤 `/tmp/aptest_smoke.log`를 `fwdg /tmp/aptest_smoke.log` 또는 `fwd get /tmp/aptest_smoke.log`로 회수한다.

콘솔/시리얼 로그인 시퀀스 파일 생성:

```bash
aptest login-file
```

기본 출력은 `~/.devtools/aptest/console_login.txt`다.
`APTEST_CONSOLE_WAKE_ENTER=on`이면 첫 줄에 빈 Enter를 넣어 AP 프롬프트를 먼저 깨운다.
파일 권한은 `600`으로 생성한다.

### SSH가 매번 꺼져 있을 때 (`--enable-ssh`)

DV03-609H KT 모델은 팩토리 기본값(`davo/files/etc/ori.config`,`fac.config`의 `dropbear`)이
`enable '0'`이라 재플래시/팩토리리셋마다 SSH(dropbear)가 다시 꺼진다. 이 값은 여러 엔지니어가
공유하는 SVN 브랜치 소스이므로 **개인 편의를 위해 절대 수정하지 않는다** — 로컬에서만 켜두는
편법(주석, `svn changelist` 등)도 `svn commit`이 그대로 쓸어담을 수 있어 완전히 안전하지 않다.

대신 로그인 시퀀스에 활성화 명령을 덧붙여 콘솔/시리얼 붙여넣기 한 번으로 끝낸다:

```bash
aptest login-file --enable-ssh
```

생성된 파일을 AP 콘솔/시리얼에 붙여넣으면 로그인 후 `uci set dropbear.main.enable=1` →
`uci commit dropbear` → `/etc/init.d/dropbear enable` → `/etc/init.d/dropbear start`까지
자동 실행된다. SVN 워킹카피에는 어떤 diff도 남지 않으므로 다른 사람의 빌드/브랜치에
영향이 전혀 없다.

## suite 추가

`~/KscTool/aptest/suites/S1KTHOME-xxxx.json` 형식으로 추가한다.
기본 형식은 `suites/smoke.json`을 복사해서 시작한다.

필드:

- `name`: 단계 이름
- `command`: AP에서 실행할 shell 명령
- `expect_exit`: 기대 종료 코드
- `expect_regex`: 출력에 있어야 하는 정규식
- `reject_regex`: 출력에 있으면 실패 처리할 정규식
- `save_as`: artifacts에 저장할 파일명
- `critical`: `false`면 실패해도 다음 단계 계속

_작성: Codex / 작성일: 2026-07-06_
