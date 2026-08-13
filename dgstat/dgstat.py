#!/usr/bin/env python3
"""DVF-754 다잉 개습(전원 차단 보고) 회차 통계 — S1ENTWIFI-2100

SecureCRT 시리얼 로그에서 전원 차단 회차를 찾아 통계를 낸다.
  - 알람부터 각 단계까지 걸린 시간 (콘솔 출력 비용 보정)
  - 어느 단계가 진행 중일 때 죽었는지 = 실패 원인 분류
  - 장비가 최소 얼마나 살아 있었는지 (콘솔 마지막 출력 기준 = 하한)
  - 구간별 소요시간 분포 (중앙값/최대) — 어디가 병목인지

사용:
    dgstat.py                  # 오늘 갱신된 로그
    dgstat.py --all            # 전체 로그
    dgstat.py <파일...>        # 지정 파일
    dgstat.py --raw            # 콘솔 출력 비용 보정 없이 원본 시각
    dgstat.py --chain          # 회차별 마커 체인까지 출력

콘솔 출력 비용: 115200bps 8N1 = 1문자 0.0868ms. 마커 한 줄이 그만큼 인터럽트를
막은 채 소모되므로, 구간 실측에서 앞선 마커들의 출력시간을 빼야 순수 처리시간이 된다.
"""
import datetime
import glob
import os
import re
import sys
import time

LOG_GLOB = "/hdd/ksc/securecrt_log/serial-Serial-ttyUSB2_*.log"
MS_PER_CHAR = 10.0 / 115200 * 1000  # 8N1 = 10비트/문자

# 닫는 괄호를 요구하지 않는다. 전원 붕괴 순간 "[ 810.864105" 뒤가 깨져도
# 시각은 살아 있으므로 회차 기준시각을 살릴 수 있다.
# 부트로더의 "[3720]" 같은 정수 표기는 \d+\.\d+ 에 걸리지 않아 오탐이 없다.
TS = re.compile(r"^\[\s*(\d+\.\d+)")
DG2 = re.compile(r"DG2\|([A-Z]{2})\|")
DG2T = re.compile(r"DG2T\|(\S+)")
# 전원 붕괴로 깨진 마커의 꼬리. 형식이 DG2|XX|cN|tNNN 이라 끝은 살아남곤 한다.
CORRUPT = re.compile(r"c\d\|t\d+")
KERNEL_DG = re.compile(r"dyinggasp detect\.\s*(.+?)\s*$")
# entlog syslog 줄에만 벽시계가 찍힌다: |2026/08/13|19:23:01.123|
WALL = re.compile(r"\|(\d{4}/\d{2}/\d{2})\|(\d{2}:\d{2}:\d{2})\.\d+\|")
COLD_BOOT = re.compile(r"Since Boot\(Power On Reset\)")
BANNER = re.compile(r"OpenWrt 22\.03|U-Boot|Format: Log Type")

STAGE = {
    "??": ("깨진 마커", "UART 가 깨져 단계 미상 — 전원 붕괴 순간"),
    "UE": ("사용자영역 수신", "커널→앱 전달 완료"),
    "IQ": ("큐 적재", "보고 대기열 등록 — 여기서 멈추면 본체 스레드 정체"),
    "QF": ("큐 적재 실패", "대기열 등록 실패"),
    "MF": ("메시지 전송 실패", "본체 깨우기 실패"),
    "CS": ("연결 시작", "서버 연결 착수 — 여기서 멈추면 연결 수립 중 전원 소진"),
    "CW": ("연결 재사용", "기존 연결 살아 있음 (0.9ms)"),
    "CR": ("새 연결(세션재사용)", "새 연결 수립 (75~160ms)"),
    "CH": ("새 연결(전체핸드셰이크)", "전체 핸드셰이크 (최대 1.68초)"),
    "CN": ("새 연결(암호화없음)", "평문 연결"),
    "CF": ("연결 실패", "서버 연결 실패"),
    "IS": ("송신 완료", "보고 내보냄 — 여기서 멈추면 서버 응답 대기 중 소진"),
    "IR": ("서버 응답 수신", "★ 서버가 받았음 = 성공 확정"),
    "IF": ("완료 통보", "커널에 완료 알림 → 리셋"),
    "RF": ("응답 등록 실패", "응답 처리 실패"),
}
ORDER = ["??", "UE", "IQ", "QF", "MF", "CS", "CW", "CR", "CH", "CN", "CF", "IS", "IR", "IF", "RF"]
SUCCESS = "IR"
SENT = "IS"
# 편도 지연 추정: 실측 왕복(IS→IR)의 절반. 왕복이 44~142ms 로 크게 흔들리므로 범위로 쓴다.
# 2026-08-13 실측: 44.1 / 61.5 / 142.4ms → 편도 22~71ms
ONEWAY_MIN_MS = 22.0
ONEWAY_MAX_MS = 71.0


def verdict(c):
    """확정 성공 / 판정 보류 / 확정 실패 로 3분류.

    IS(송신 완료)까지 갔는데 IR(서버 응답)을 못 받은 회차는 실패가 아니다.
    보고 패킷은 이미 나갔고 서버가 받았을 수 있다. 응답이 돌아올 때까지
    장비가 못 버틴 것일 뿐이므로 NMS 기록으로만 갈린다.
    """
    seen = {s for s, _, _ in c["stages"]}
    if SUCCESS in seen:
        return "성공", "서버 응답 수신"
    if SENT in seen:
        return "보류", "송신됨 · 서버 수신 여부는 NMS 확인 필요"
    return "실패", "보고가 나가지 못함"


def parse(paths):
    cycles, cur = [], None
    # 벽시계 환산 앵커. syslog 줄에는 업타임이 없으므로 직전 커널 업타임과 짝지어
    # (업타임, 벽시계) 를 잡아두고, 회차 업타임과의 차이로 환산한다.
    # 재부팅하면 업타임이 리셋되므로 앵커를 버린다.
    anchor, seen_up = None, None

    def close():
        nonlocal cur
        if cur:
            cycles.append(cur)
        cur = None

    def wall_of(up):
        if anchor is None:
            return None
        return (anchor[1] + datetime.timedelta(seconds=up - anchor[0])) \
            .strftime("%m/%d %H:%M:%S")

    for path in paths:
        with open(path, "rb") as fh:
            text = fh.read().decode("utf-8", errors="replace").replace("\r", "")
        for line in text.split("\n"):
            m = TS.match(line)
            up = float(m.group(1)) if m else None
            if up is not None:
                if seen_up is not None and up < seen_up - 5:
                    anchor = None  # 재부팅 — 앵커 무효
                seen_up = up
            w = WALL.search(line)
            if w and seen_up is not None:
                anchor = (seen_up, datetime.datetime.strptime(
                    f"{w.group(1)} {w.group(2)}", "%Y/%m/%d %H:%M:%S"))

            tag = None
            if up is not None:
                d = DG2.search(line)
                if d:
                    # 아는 단계만 받는다. UART 가 깨져 UE→UG 처럼 바뀌어도 형식은
                    # 그대로라 정규식은 통과한다. 그걸 실제 단계로 세면 통계가 오염되고,
                    # 최악의 경우 IS→IR 로 깨져 없는 성공이 잡힌다.
                    tag = d.group(1) if d.group(1) in STAGE else "??"
                elif CORRUPT.search(line):
                    tag = "??"  # 전원 붕괴로 글자가 깨진 마커

            def new_cycle(t, partial):
                return {"log": os.path.basename(path), "t0": up, "last_up": up,
                        "wall": wall_of(up), "stages": [(t, up, len(line))],
                        "kernel": [], "cold": False, "timing": None,
                        "partial": partial, "corrupt": 1 if partial else 0}

            if tag == "UE":
                close()
                cur = new_cycle("UE", False)
                continue
            if cur is None:
                # UE 가 깨져 못 잡힌 회차. 첫 마커로 회차를 연다.
                if tag:
                    cur = new_cycle(tag, True)
                continue
            if up is not None and up < cur["last_up"] - 5:
                close()
                continue

            if up is not None:
                cur["last_up"] = max(cur["last_up"], up)
                if tag == "??":
                    cur["corrupt"] += 1
                elif tag:
                    cur["stages"].append((tag, up, len(line)))
                k = KERNEL_DG.search(line)
                if k:
                    cur["kernel"].append(k.group(1))
                t = DG2T.search(line)
                if t:
                    cur["timing"] = t.group(1)
            elif COLD_BOOT.search(line):
                cur["cold"] = True
                close()
            elif BANNER.search(line):
                close()
    close()
    return cycles


def elapsed(c, idx, raw):
    """회차 c 의 idx 번째 단계까지 걸린 시간(ms). raw=False 면 콘솔 출력비용 차감.

    보정값이 앞 단계보다 작아지는(역행) 경우가 없도록 단조 증가로 묶는다.
    마커 간격이 출력비용보다 짧으면 산술적으로 역행할 수 있다.
    """
    if raw:
        return (c["stages"][idx][1] - c["t0"]) * 1000.0
    run, cost = 0.0, 0.0
    for j in range(idx + 1):
        v = (c["stages"][j][1] - c["t0"]) * 1000.0 - cost
        run = max(run, v)
        cost += c["stages"][j][2] * MS_PER_CHAR
    return run


def pct(k, n):
    return f"{k*100.0/n:.0f}%" if n else "—"


def med(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if xs else None


def report(cycles, raw=False, chain=False):
    o, n = [], len(cycles)
    o.append(f"# 다잉 개습 회차 통계 — {n}회")
    o.append(f"\n_집계: {time.strftime('%Y-%m-%d %H:%M')}"
             f" / 시각은 {'원본' if raw else '콘솔 출력비용 차감'} 기준_\n")

    # ── 1. 회차별
    o.append("## 1. 회차별 결과\n")
    o.append("| # | 시각 | 판정 | 마지막 단계 | 도달시각 | 서버도달 추정 | 최소 생존 | 여유 |")
    o.append("|---|---|---|---|---|---|---|---|")
    mark = {"성공": "**성공**", "보류": "△ 보류", "실패": "✗ 실패"}
    for i, c in enumerate(cycles, 1):
        li = len(c["stages"]) - 1
        st = c["stages"][li][0]
        v, why = verdict(c)
        surv = (c["last_up"] - c["t0"]) * 1000
        # 송신 완료 시각 + 편도 지연 = 서버가 받았을 시각 추정
        si = next((j for j, (s, _, _) in enumerate(c["stages"]) if s == SENT), None)
        if si is None:
            arrive, slack = "미송신", "—"
        else:
            lo = elapsed(c, si, raw) + ONEWAY_MIN_MS
            a = elapsed(c, si, raw) + ONEWAY_MAX_MS
            arrive = f"{lo:.0f}~{a:.0f}ms"
            # 콘솔 마지막 줄이 곧 마지막 마커면 생존 하한이 그 마커 시각과 같다.
            # 이때 여유값은 계산 인공물일 뿐 정보가 없다.
            if abs(surv - (c["stages"][li][1] - c["t0"]) * 1000) < 1.0:
                slack = "판단불가"
            else:
                slack = f"{surv - a:+.0f}ms"
        o.append(
            f"| {i} | {c.get('wall') or '—'} | {mark[v]} | {st} {STAGE.get(st,('?',''))[0]} "
            f"| {elapsed(c, li, raw):.1f}ms | {arrive} | {surv:.1f}ms | {slack} |")
    o.append("\n> **서버도달 추정** = 송신 완료 + 편도지연 22~71ms (실측 왕복 44~142ms 의 절반). "
             "**여유**는 최악(편도 71ms) 기준이다. 양수면 서버가 받았을 가능성이 높지만 "
             "추정치이므로 NMS 기록으로 확정해야 한다.")

    if chain:
        o.append("\n### 회차별 마커 체인\n")
        for i, c in enumerate(cycles, 1):
            seq = " → ".join(f"{s}{elapsed(c,j,raw):.1f}"
                             for j, (s, _, _) in enumerate(c["stages"]))
            o.append(f"- **{i}**: {seq}"
                     + (f"  ‖ 커널: {', '.join(c['kernel'])}" if c["kernel"] else "")
                     + (f"  ‖ µs실측: `{c['timing']}`" if c["timing"] else ""))

    # ── 2. 어디서 멈추나
    o.append("\n## 2. 어느 단계에서 죽는가\n")
    reach, stop = {}, {}
    for c in cycles:
        for s, _, _ in c["stages"]:
            reach[s] = reach.get(s, 0) + 1
        last = c["stages"][-1][0]
        stop[last] = stop.get(last, 0) + 1
    o.append("| 단계 | 도달 | 도달률 | **여기서 멈춤** | 의미 |")
    o.append("|---|---|---|---|---|")
    for s in ORDER:
        if s in reach or s in stop:
            k = stop.get(s, 0)
            o.append(f"| {s} {STAGE[s][0]} | {reach.get(s,0)} | {pct(reach.get(s,0),n)} "
                     f"| {'**'+str(k)+'회**' if k else '—'} | {STAGE[s][1]} |")

    # ── 3. 구간별 소요시간
    o.append("\n## 3. 구간별 소요시간 — 어디가 병목인가\n")
    segs = {}
    for c in cycles:
        for j in range(1, len(c["stages"])):
            key = f"{c['stages'][j-1][0]}→{c['stages'][j][0]}"
            segs.setdefault(key, []).append(elapsed(c, j, raw) - elapsed(c, j - 1, raw))
    o.append("| 구간 | 표본 | 최소 | 중앙값 | 최대 |")
    o.append("|---|---|---|---|---|")
    for k, v in sorted(segs.items(), key=lambda kv: -med(kv[1])):
        o.append(f"| {k} | {len(v)} | {min(v):.2f}ms | **{med(v):.2f}ms** | {max(v):.2f}ms |")

    # ── 4. 생존시간
    o.append("\n## 4. 전원이 얼마나 버티나 (콘솔 마지막 출력 = 하한)\n")
    sv = sorted((c["last_up"] - c["t0"]) * 1000.0 for c in cycles)
    o.append("| 항목 | 값 |")
    o.append("|---|---|")
    o.append(f"| 표본 | {len(sv)}회 |")
    for lbl, v in (("최소", sv[0]), ("중앙값", med(sv)), ("최대", sv[-1])):
        o.append(f"| {lbl} | {v:.1f}ms |")
    o.append("")
    o.append("| 필요시간 기준 | 못 버틴 회차 |")
    o.append("|---|---|")
    for th, why in ((6, "연결 재사용 6ms"), (33, "HW 보장 33ms"),
                    (80, "새 연결 최선 79ms"), (165, "새 연결 최악 165ms"),
                    (1680, "전체 핸드셰이크 1.68초")):
        k = sum(1 for s in sv if s < th)
        o.append(f"| {th}ms — {why} | {k}회 ({pct(k,len(sv))}) |")
    o.append("\n> 주의: 콘솔이 끊긴 시점 ≠ 장비가 멈춘 시점. 위 값은 모두 **하한**이다.")

    # ── 5. 성공률
    vs = [verdict(c)[0] for c in cycles]
    o.append("\n## 5. 판정 종합\n")
    o.append("| 판정 | 회차 | 비율 | 뜻 |")
    o.append("|---|---|---|---|")
    for k, desc in (("성공", "서버 응답까지 받음 — 확정"),
                    ("보류", "송신은 됐으나 응답 전 전원 소진 — NMS 확인 필요"),
                    ("실패", "보고가 나가지도 못함 — 확정 실패")):
        c_ = vs.count(k)
        o.append(f"| {k} | {c_}회 | {pct(c_,n)} | {desc} |")
    o.append(f"\n- 최악 기준 성공률(보류를 실패로 봄): **{pct(vs.count('성공'),n)}**")
    o.append(f"- 최선 기준 성공률(보류를 성공으로 봄): "
             f"**{pct(vs.count('성공')+vs.count('보류'),n)}**")
    o.append("- 기존 에이징 실패율 8.81%(159회 중 14회)와 비교할 값이다.")
    if n < 30:
        o.append(f"- ⚠ 표본 {n}회로는 8.81% 수준의 차이를 판정할 수 없다 (30회 이상 필요).")
    return "\n".join(o)


def main():
    argv = sys.argv[1:]
    raw = "--raw" in argv
    chain = "--chain" in argv
    files = [a for a in argv if not a.startswith("-")]
    if not files:
        allf = sorted(glob.glob(LOG_GLOB), key=os.path.getmtime)
        if "--all" in argv:
            files = allf
        else:  # 오늘 갱신된 것만
            today = time.strftime("%Y-%m-%d")
            files = [f for f in allf
                     if time.strftime("%Y-%m-%d", time.localtime(os.path.getmtime(f))) == today]
            files = files or allf[-1:]
    if not files:
        print("로그 없음", file=sys.stderr)
        return 1
    cycles = parse(files)
    if not cycles:
        print(f"전원 차단 회차 없음 (로그 {len(files)}개). "
              f"`dyngsp_trace=1` 이어야 단계 마커가 남는다.")
        return 0
    print(report(cycles, raw, chain))
    print(f"\n_로그: {', '.join(os.path.basename(f) for f in files)}_")
    return 0


if __name__ == "__main__":
    sys.exit(main())
