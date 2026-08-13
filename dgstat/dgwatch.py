#!/usr/bin/env python3
"""시리얼 로그를 따라가며 전원차단 회차를 하나씩 요약 출력한다 (Monitor 이벤트원).

회차 하나가 끝날 때(재부팅 배너 또는 마커 뒤 무출력 6초) 한 줄만 낸다.
SecureCRT 가 로그를 새로 열어도 최신 파일로 자동 전환한다.

전원이 끊기는 순간 UART 가 깨져 마커 글자가 유실되는 일이 있다(2026-08-13 실측).
첫 마커가 깨지면 회차 자체를 놓치므로, 깨진 마커도 `??` 로 잡고
**어떤 마커든** 회차를 열 수 있게 한다. 실패 회차를 조용히 버리지 않는 것이 중요하다.
"""
import glob
import os
import re
import sys
import time

GLOB = sys.argv[1] if len(sys.argv) > 1 else \
    "/hdd/ksc/securecrt_log/serial-Serial-ttyUSB2_*.log"
LEDGER = os.environ.get(
    "DGWATCH_LEDGER",
    "/home/ksc/test/dvf754/issue/S1ENTWIFI-2100/증거/온오프_회차기록.tsv")

# 닫는 괄호를 요구하지 않는다. 전원 붕괴 순간 "[ 810.864105" 뒤가 깨져도
# 시각은 살아 있으므로 회차 기준시각을 살릴 수 있다.
# 부트로더의 "[3720]" 같은 정수 표기는 \d+\.\d+ 에 걸리지 않아 오탐이 없다.
TS = re.compile(r"^\[\s*(\d+\.\d+)")
DG2 = re.compile(r"DG2\|([A-Z]{2})\|")
# 깨진 마커의 꼬리. 마커 형식이 DG2|XX|cN|tNNN 이라 끝부분은 살아남는 일이 많다.
CORRUPT = re.compile(r"c\d\|t\d+")
DG2T = re.compile(r"DG2T\|(\S+)")
KDG = re.compile(r"dyinggasp detect\.\s*(.+?)\s*$")
END = re.compile(r"Since Boot\(Power On Reset\)|U-Boot|Format: Log Type")
KNOWN = {"UE","IQ","QF","MF","CS","CW","CR","CH","CN","CF","IS","IR","IF","RF"}
MS_PER_CHAR = 10.0 / 115200 * 1000
IDLE_SEC = 6

n = 0
cur = None


def flush(reason):
    global cur, n
    if cur is None:
        return
    n += 1
    t0 = cur["st"][0][1]
    cost, run = 0.0, 0.0
    parts = []
    for s, t, ln in cur["st"]:
        run = max(run, (t - t0) * 1000 - cost)  # 보정값 역행 방지
        parts.append(f"{s}{run:.1f}")
        cost += ln * MS_PER_CHAR
    got = {s for s, _, _ in cur["st"]}
    v = "성공" if "IR" in got else ("보류(송신됨)" if "IS" in got else "실패")
    if cur["partial"]:
        v += "*"  # 첫 마커가 깨져 기준시각이 부정확하다
    wall = time.strftime("%m/%d %H:%M:%S")
    surv = (cur["last"] - t0) * 1000
    extra = ""
    if cur["kdg"]:
        extra += " ‖ 커널:" + ",".join(cur["kdg"])
    if cur["tm"]:
        extra += f" ‖ µs:{cur['tm']}"
    if cur["corrupt"]:
        extra += f" ‖ 깨진마커 {cur['corrupt']}개"
    print(f"[회차{n}] {wall} | {v} | 마지막={cur['st'][-1][0]} | 생존>={surv:.0f}ms | "
          f"{' '.join(parts)}{extra} | {reason}", flush=True)
    try:  # 기록 실패가 감시를 죽이지 않게
        with open(LEDGER, "a") as f:
            if f.tell() == 0:
                f.write("시각\t판정\t마지막단계\t생존하한ms\t마커체인\t커널\tµs\t종료사유\n")
            f.write(f"{wall}\t{v}\t{cur['st'][-1][0]}\t{surv:.0f}\t{' '.join(parts)}\t"
                    f"{','.join(cur['kdg'])}\t{cur['tm'] or ''}\t{reason}\n")
    except OSError as e:
        print(f"[경고] 기록 실패: {e}", flush=True)
    cur = None


def open_cycle(tag, up, ln, partial):
    global cur
    cur = {"st": [(tag, up, ln)], "last": up, "kdg": [], "tm": None,
           "partial": partial, "corrupt": 1 if partial else 0}


def newest():
    fs = glob.glob(GLOB)
    return max(fs, key=os.path.getmtime) if fs else None


def main():
    path = newest()
    if not path:
        print("로그 없음", file=sys.stderr)
        return 1
    fh = open(path, "rb")
    fh.seek(0, os.SEEK_END)
    buf = b""
    idle = time.time()
    while True:
        chunk = fh.read(65536)
        if not chunk:
            if cur is not None and time.time() - idle > IDLE_SEC:
                flush("무출력 6초 — 전원 소진")
            nxt = newest()
            if nxt != path:  # SecureCRT 가 새 로그를 열었다
                flush("로그 전환")
                fh.close()
                path, fh, buf = nxt, open(nxt, "rb"), b""
            time.sleep(1.0)
            continue
        buf += chunk
        *lines, buf = buf.split(b"\n")
        for rawline in lines:
            line = rawline.decode("utf-8", "replace").replace("\r", "")
            m = TS.match(line)
            up = float(m.group(1)) if m else None

            tag = None
            if up is not None:
                d = DG2.search(line)
                if d:
                    # 아는 단계만 받는다. UE→UG 처럼 깨져도 형식은 통과하므로,
                    # 그대로 세면 통계가 오염된다(IS→IR 로 깨지면 없는 성공이 잡힌다).
                    tag = d.group(1) if d.group(1) in KNOWN else "??"
                elif CORRUPT.search(line):
                    tag = "??"  # 전원 붕괴로 글자가 깨진 마커

            if tag == "UE":
                flush("다음 회차 시작")
                open_cycle("UE", up, len(line), False)
                idle = time.time()
                continue
            if cur is None:
                # UE 가 깨져 못 잡힌 회차. 첫 마커로 회차를 연다.
                if tag:
                    open_cycle(tag, up, len(line), True)
                    idle = time.time()
                continue

            if up is not None:
                cur["last"] = max(cur["last"], up)
                idle = time.time()
                if tag == "??":
                    cur["corrupt"] += 1
                elif tag:
                    cur["st"].append((tag, up, len(line)))
                k = KDG.search(line)
                if k:
                    cur["kdg"].append(k.group(1))
                t = DG2T.search(line)
                if t:
                    cur["tm"] = t.group(1)
            elif END.search(line):
                flush("재부팅 시작")


if __name__ == "__main__":
    sys.exit(main())
