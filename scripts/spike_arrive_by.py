#!/usr/bin/env python3
"""0단계 위험 요소 1: 마감 시각에서 거꾸로 가장 늦은 열차 찾기.

경로 API는 '출발 시각 이후' 검색만 되고 도착 기준 검색이 없다.
최소환승 모드는 조회 시각 이후 첫 열차를 돌려주므로, 열차 출발 시각 + 1초로 다시 조회하며
열차를 하나씩 훑어 출발→도착 표를 만든다. 최소시간 모드로 다른 경로가 더 빠른지도 함께 본다.
"""
import sys, time, datetime as D, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from route_probe import call

def fetch(dep, arr, t, mode):
    d, _ = call(dep, arr, t.strftime("%Y-%m-%d %H:%M:%S"), mode)
    b = d.get("body") or {}
    ps = b.get("paths") or []
    if not ps or not b.get("totalReqHr"):
        return None
    first_dep = ps[0].get("trainDptreTm")
    last_arr = next((p.get("trainArvlTm") for p in reversed(ps) if p.get("trainArvlTm")), None)
    def at(hms):
        h, m, s_ = map(int, hms.split(":"))
        base = D.datetime.combine(t.date(), D.time(0))
        x = base + D.timedelta(hours=h, minutes=m, seconds=s_)
        return x + D.timedelta(days=1) if x < t - D.timedelta(hours=6) else x
    lines = []
    for p in ps:
        ln = p["dptreStn"]["lineNm"]
        if not lines or lines[-1] != ln: lines.append(ln)
    return {"dep": at(first_dep), "arr": at(last_arr), "transfers": b.get("trsitNmtm"),
            "express": ps[0].get("etrnYn") == "Y", "lines": "→".join(lines)}

def build_table(dep, arr, start, end, mode="transfer"):
    """start~end 사이 출발역을 떠나는 열차를 모두 훑는다."""
    rows, t, calls = [], start, 0
    while t <= end:
        r = fetch(dep, arr, t, mode); calls += 1
        if not r: break
        rows.append(r)
        t = r["dep"] + D.timedelta(seconds=1)
    return rows, calls

def latest_ready_time(table, target_arrival):
    """승강장에 준비돼 있어야 하는 가장 늦은 시각. 그 시각 이후 탈 수 있는 열차 중
    가장 빨리 도착하는 열차가 목표 이내여야 한다 (먼저 오는 일반보다 뒤 급행이 빠를 수 있음)."""
    best = None
    for i, r in enumerate(table):
        # r 출발 직전에 준비됐을 때 가장 빨리 도착하는 열차
        earliest = min(x["arr"] for x in table[i:])
        if earliest <= target_arrival:
            best = (r, earliest)
    return best

if __name__ == "__main__":
    day = D.date(2026, 9, 30)
    origin, dest = "가양", "강남"
    deadline = D.datetime.combine(day, D.time(10, 0))
    early, walk_dest, buffer, home = 10, 5, 4, 9
    target = deadline - D.timedelta(minutes=early + walk_dest)   # 강남역 도착 마감 9:45
    t0 = time.time()
    table, calls = build_table(origin, dest, target - D.timedelta(minutes=80), target - D.timedelta(minutes=15))
    dur_table, calls2 = build_table(origin, dest, target - D.timedelta(minutes=80), target - D.timedelta(minutes=15), "duration")
    took = time.time() - t0
    print(f"표 만들기: 최소환승 {calls}회 + 최소시간 {calls2}회 조회, {took:.1f}초")
    merged = sorted({(r['dep'], r['arr']): r for r in table + dur_table}.values(), key=lambda r: r["dep"])
    for r in merged:
        print(f"  {r['dep']:%H:%M:%S} {'급행' if r['express'] else '일반'} → {r['arr']:%H:%M:%S}  환승 {r['transfers']}  {r['lines']}")
    pick = latest_ready_time(merged, target)
    r, arrive = pick
    ready = r["dep"]
    leave = ready - D.timedelta(minutes=buffer + home)
    print(f"\n강남역 도착 마감 {target:%H:%M} (회사 10:00, 역에서 5분, 일찍 10분)")
    print(f"승강장 준비 마감 {ready:%H:%M:%S} → 이 시각 이후 가장 빨리 도착하는 열차로 {arrive:%H:%M:%S} 도착")
    print(f"현관 출발 {leave:%H:%M} (승강장 여유 {buffer}분 + 집→승강장 {home}분)")
