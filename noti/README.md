# noti — 휴대폰 알림 · 원격 지시

## 왜 만들었나

빌드·야간 무인 시험처럼 오래 걸리는 작업을 걸어두고 자리를 비우면, 에이전트가 채팅에 결과를
적어도 사용자가 볼 수 없다. 끝났는지 확인하러 계속 돌아오거나, 막혀 있는 걸 몇 시간 뒤에
발견한다. `noti` 는 그 순간 휴대폰을 울리고, `dclisten` 은 그 답장을 받아 작업을 이어가게 한다.

```
  [작업 PC]                                   [휴대폰]
   noti  ──────  urgent: "opt60 값이 규격과 다름" ──────▶  ntfy 알림
                                                            │
   Monitor ◀──  dclisten (디스코드 폴링) ◀── "1번으로 가"  ◀┘ 디스코드 답장
     │
     └─ dcsession 으로 그 세션 맥락을 읽고 이어서 진행
```

## 구성

| 스크립트 | 역할 |
|----------|------|
| `noti.sh` | 알림 전송 (Discord / ntfy / Telegram). alias `noti` |
| `dclisten.sh` | 디스코드 채널 폴링 → 새 메시지를 한 줄씩 stdout. Monitor 도구가 이벤트로 받는다 |
| `dcsession.sh` | 알림을 보낸 그 세션의 대화 기록을 읽는다 |
| `dcbot.sh` | 상주 봇 — 세션이 안 떠 있어도 디스코드로 지시하고 답을 받는다 |
| `notirun.sh` | 오래 걸리는 명령을 감싸서 끝나면 알린다. alias `notirun` / `ntr` |

에이전트용 사용 규칙은 `~/.claude/skills/phone-notify/SKILL.md` (Codex 도 심볼릭 링크로 공유).

## 레벨이 곧 라우팅 (2026-08-28 결정)

| 레벨 | 쓸 때 | 디스코드 | ntfy(폰 울림) |
|------|-------|:--------:|:-------------:|
| `info` | 완료·정상 종료 | ○ | ✗ |
| `warn` | 실패했지만 진행 가능 | ○ | ✗ |
| `urgent` | 막힘·판단 필요 | ○ | **○** |

디스코드 알림은 꺼두고 보고 싶을 때만 본다. 그래서 디스코드는 마음껏 남겨도 되는 조용한
기록이고, 폰을 실제로 울리는 건 `urgent` 뿐이다. 설정의 `NOTI_ROUTE_*` 로 바꾼다.

`urgent` 는 여기에 더해 디스코드에서 사용자를 **@멘션**한다(`NOTI_DISCORD_MENTION`).
채널 알림을 꺼놔도 멘션은 뜨므로, 답장이 필요한 질문은 `urgent` 로 보낸다.

## 설치

```bash
~/KscTool/noti/noti.sh init      # 설정 파일 생성 + alias 등록
noti setkey webhook              # 디스코드 웹훅 URL (화면에 안 보임)
noti setkey ntfy-topic           # ntfy 토픽 (앱에서 구독한 이름)
noti test                        # info·urgent 각 1건 발송
```

### 디스코드 웹훅 (보내기)

채널 우클릭 → 채널 편집 → 연동 → 웹후크 → 새 웹후크 → URL 복사.
채널 ID는 웹훅 URL 을 GET 하면 응답의 `channel_id` 로 나온다 (따로 개발자 모드를 켤 필요 없음).

### 디스코드 봇 (받기)

1. https://discord.com/developers/applications → New Application
2. **봇(Bot)** 탭 → **토큰 재설정** → 복사 → `noti setkey bot-token`
3. 같은 탭 → **특권 게이트웨이 인텐트** → **메시지 콘텐츠 인텐트** ON
   (안 켜면 메시지 본문이 빈칸으로 들어온다)
4. 설치/OAuth2 → `bot` + `View Channels` + `Read Message History` 로 서버에 초대
5. `NOTI_DISCORD_ALLOW_USER` 에 본인 숫자 ID — **이게 없으면 채널에 들어온 누구의 말이든
   지시로 읽는다.** 반드시 지정.
6. `~/KscTool/noti/dclisten.sh check` 로 토큰·채널 권한·본문 읽기까지 점검

### ntfy

앱 설치 후 아무 토픽이나 구독하면 끝 (가입 불필요). **토픽 이름이 곧 비밀키**이므로
`ksc-dv-<무작위 16자>` 처럼 남이 못 맞출 이름을 쓴다.

## 사용법

```bash
noti -t "빌드 완료" "609H 전체 빌드 성공"
noti -t "시험 중단" -l urgent "AP SSH 응답 없음 — 판단 필요"
tail -5 build.log | noti -t "빌드 실패" -l warn       # 파이프 입력
noti -c ntfy "라우팅 무시하고 채널 직접 지정"
noti conf / noti log 50 / noti help

~/KscTool/noti/dclisten.sh reset     # "읽은 위치"를 지금으로 (과거 메시지 오인 방지)
~/KscTool/noti/dclisten.sh once      # 한 번 확인
~/KscTool/noti/dclisten.sh watch     # 계속 폴링 (Monitor 로 감시)

~/KscTool/noti/dcsession.sh list             # 최근 세션 목록
~/KscTool/noti/dcsession.sh ctx 3f2a1b8c 12  # 그 세션 최근 12턴
```

## 답장 라우팅

`noti` 는 디스코드로 보낼 때 `?wait=true` 로 방금 보낸 메시지 ID를 받아
`~/.devtools/noti/threads.tsv` 에 `메시지ID → 세션ID → 레벨 → 제목` 을 기록한다.
사용자가 그 알림에 **답장(reply)** 하면 원본 메시지 ID가 함께 오므로,
`dclisten` 이 어느 질문에 대한 답인지 복원해서 이렇게 알려준다.

```
📩 답장["S1KTHOME-1440 야간시험 중단" · 이 세션] 1번으로 진행해
📩 답장["609H 빌드 실패" · 세션 3f2a1b8c] 그건 놔두고 커밋만 해
📩 새메시지 AP 재부팅해봐
⛔ 허용되지 않은 사용자(mallory/998877)의 메시지 무시
```

다른 세션 것이면 `dcsession.sh ctx <세션ID>` 로 그쪽 대화를 읽고 판단한다.

### 전달자 모드 — 살아있는 세션에 그대로 넘기기

```bash
noti -t "판단 필요" -l urgent -n memo-6b "opt60 값이 규격과 다릅니다. 진행할까요?"
                              ↑ 이 세션 이름 (ListAgents 첫 줄에 나온다)
```

`-n` 이 붙은 알림에 사용자가 답장하면, 봇은 답하지 않고 **그 세션에 넘긴다.**

```
폰 답장 → dcbot(PC) → threads.tsv 에서 세션이름 조회
        → claude -p 전달자 → SendMessage → 그 세션이 맥락 그대로 이어받음
```

- 세션 UUID 로는 다른 세션을 못 부른다. 이름(`memo-6b`)이 필요한데 `폴더명-무작위2자` 라
  UUID 에서 계산이 안 된다. 그래서 보낼 때 적어 `threads.tsv` 6열에 남긴다.
- 봇은 셸이라 `SendMessage`(Claude 도구)를 못 쓴다. 그래서 전달자를 한 번 띄운다.
- 세션이 죽었으면 자동으로 봇이 읽기 전용으로 답한다. `NOTI_BOT_FORWARD=off` 로 끌 수 있다.

## notirun — 명령 감싸기 (짧게 `ntr`)

```bash
notirun make -j8                        # 걸어놓고 자리 뜨기
notirun -t "609H 전체빌드" make -j8     # 제목 붙이기 (알림에 그대로 뜬다)
notirun -f aptest smoke --live          # 실패했을 때만 알림
ntr make -j8                            # ntr 은 notirun 의 짧은 별칭
```

성공하면 `info`(디스코드 기록만), **실패하면 `urgent`(폰이 울린다)**. 화면 출력은 그대로
보이고 종료코드도 원래 명령 것을 돌려주므로 `&&` 체인에 그냥 끼워 쓰면 된다.

실패 알림에는 로그 끝부분이 아니라 `error`·`undefined reference` 같은 게 걸린 줄을 뽑아
넣는다 — 빌드 로그는 끝이 make 잡음이라 원인이 안 보이기 때문이다.
로그는 `~/.devtools/noti/runs/` 에 최근 50건 남는다.

## 상주 봇 (dcbot)

세션이 안 떠 있어도, 회사 밖에서도 디스코드로 물어보면 PC 에서 `claude -p` 를 돌려 답을
채널에 되돌린다.

```bash
~/KscTool/noti/dcbot.sh status      # 상태
~/KscTool/noti/dcbot.sh logs 30     # 처리 이력
~/KscTool/noti/dcbot.sh start|stop  # 수동 실행/중지
~/KscTool/noti/dcbot.sh install     # 부팅 시 자동 실행 (systemd 사용자 서비스)
```

**B(세션 감시)와 겹치지 않는다.** 살아있는 세션이 `dclisten watch` 로 채널을 보고 있으면
(60초 안에 `watcher.heartbeat` 갱신) 봇은 양보한다. 앞에 `!` 를 붙이면 그래도 봇이 처리한다.

| 들어온 말 | 어디로 |
|---|---|
| **`-n` 붙은 알림에 답장** | **그 세션에 그대로 전달** (살아있으면). 맥락 그대로 이어받는다 |
| 알림에 답장 (`-n` 없음/세션 죽음) | 그 세션 대화를 읽어 맥락으로 넣고 **새 봇 세션**에서 답 |
| 봇 답변에 답장 | 그 봇 세션을 `--resume` 으로 이어감 |
| 그냥 메시지 | 30분 안에 쓰던 봇 세션이 있으면 이어가고, 없으면 새로 |

**권한** — 기본 `read` 모드는 `Read`/`Grep`/`Glob` 만 준다. **Bash·수정 도구는 없다.**
COMMON.md §14 "명령 이름만 보는 allowlist 는 만들지 않는다"를 따른 것이다
(`find -delete`, `sed -n -i` 처럼 프리픽스로는 못 거른다).
`NOTI_BOT_MODE=full` 은 `bypassPermissions` 라 폰에서 들어온 말이 그대로 PC 에서 실행된다.
바꾸려면 그 뜻을 알고 바꿔야 한다.

설정 항목: `NOTI_BOT_MODE`(read|full) `NOTI_BOT_CWD` `NOTI_BOT_INTERVAL`(기본 20초)
`NOTI_BOT_TIMEOUT`(기본 600초) `NOTI_BOT_SESSION_IDLE`(기본 1800초) `NOTI_BOT_CTX_TURNS`(기본 12)

## 내부 동작

- 설정 `~/.devtools/noti/config` (권한 600). 웹훅·토큰이 들어가므로 **커밋 금지**.
- 이력 `~/.devtools/noti/history.log` / 답장 매핑 `threads.tsv` (최근 500건 유지)
- 페이로드는 `jq` 로 만든다. 따옴표·개행·역슬래시가 섞인 빌드 로그를 그대로 파이프해도 안 깨진다.
- ntfy 는 HTTP 헤더에 한글을 실을 수 없어(모지바케) **JSON 발행 엔드포인트**를 쓴다.
- 디스코드 본문은 1900자에서 자른다 (API 상한 2000자).
- `curl -m 15`. 알림 실패가 호출한 쪽 작업을 막지 않는다.
- 봇 토큰은 `curl --config` 로 넘겨 `ps` 목록에 노출되지 않게 한다.
- 사용자가 작업 도중 끼워 넣은 말은 대화 기록에 `type=user` 가 아니라
  `queue-operation(enqueue)` 로 남는다. `dcsession` 은 그것도 읽는다.

## 주의

- 알림 본문에 비밀번호·키를 넣지 말 것. 외부 서비스에 그대로 전송된다.
- 디스코드 채널은 **작업 PC에 명령을 넣는 입구**다. 화이트리스트를 반드시 채우고,
  파괴적 작업(커밋·푸시·sysupgrade·삭제)은 디스코드 지시만으로 실행하지 않는다.
- ntfy 공용 서버의 토픽은 이름을 아는 사람이면 누구나 구독할 수 있다.

---
_작성: Claude (Opus 5) / 작성일: 2026-08-27 / 최종 갱신: 2026-08-28 (v1.1.0)_
