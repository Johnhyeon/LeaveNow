#!/usr/bin/env python3
"""서울 열린데이터광장 getShtrmPath 품질 확인용. 키는 Secrets.plist 에서 읽고 출력하지 않는다.
사용법: python3 scripts/route_probe.py 가양 강남 "2026-09-30 08:50:00" duration
"""
import json, plistlib, sys, time, urllib.parse, urllib.request, pathlib
ROOT = pathlib.Path(__file__).resolve().parent.parent
KEY = plistlib.load(open(ROOT / "LeaveNow/Resources/Secrets.plist", "rb"))["SeoulOpenAPIKey"]

def call(dep, arr, dt, stype="duration"):
    parts = [KEY, "json", "getShtrmPath", "1", "50", dep, arr, dt, stype]
    url = "http://openapi.seoul.go.kr:8088/" + "/".join(urllib.parse.quote(p) for p in parts)
    t0 = time.time()
    with urllib.request.urlopen(url, timeout=30) as r:
        body = r.read().decode("utf-8")
    return json.loads(body), time.time() - t0

def summarize(d):
    svc = d.get("getShtrmPath") or d
    res = svc.get("RESULT") or d.get("RESULT")
    rows = svc.get("row") or []
    return res, rows

if __name__ == "__main__":
    dep, arr, dt = sys.argv[1], sys.argv[2], sys.argv[3]
    stype = sys.argv[4] if len(sys.argv) > 4 else "duration"
    d, sec = call(dep, arr, dt, stype)
    res, rows = summarize(d)
    print(f"== {dep}→{arr} {dt} {stype} | {sec:.2f}s | {res}")
    if not rows:
        print(json.dumps(d, ensure_ascii=False)[:800]); sys.exit()
    print("keys:", list(rows[0].keys()))
    for r in rows:
        print(json.dumps(r, ensure_ascii=False)[:600])
