#!/usr/bin/env python3
"""getShtrmPath 응답을 구간(같은 열차) 단위로 묶어 요약한다."""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from route_probe import call

def legs(body):
    out, cur = [], None
    for p in body.get("paths", []):
        if p.get("trsitYn") == "Y":
            if cur: out.append(cur); cur = None
            out.append({"walk": True, "from": p["dptreStn"]["stnNm"], "line": f'{p["dptreStn"]["lineNm"]}→{p["arvlStn"]["lineNm"]}',
                        "reqHr": p.get("reqHr"), "wtngHr": p.get("wtngHr")})
            continue
        key = p.get("trainno") or (p["dptreStn"]["lineNm"])
        if cur and cur["train"] == key:
            cur["to"] = p["arvlStn"]["stnNm"]; cur["n"] += 1; cur["arr"] = p.get("trainArvlTm") or cur["arr"]
            cur["last_dep"] = p.get("trainDptreTm")
        else:
            if cur: out.append(cur)
            cur = {"walk": False, "train": key, "line": p["dptreStn"]["lineNm"], "from": p["dptreStn"]["stnNm"],
                   "to": p["arvlStn"]["stnNm"], "dep": p.get("trainDptreTm"), "arr": p.get("trainArvlTm"),
                   "n": 1, "express": p.get("etrnYn"), "dir": p.get("upbdnbSe"), "tmnl": p.get("tmnlStnNm"),
                   "stops_nonstop": 0, "last_dep": p.get("trainDptreTm")}
        if p.get("nonstopYn") == "Y": cur["stops_nonstop"] += 1
    if cur: out.append(cur)
    return out

def show(dep, arr, dt, stype):
    d, sec = call(dep, arr, dt, stype)
    b = d.get("body") or {}
    if not b:
        print(f"== {dep}→{arr} {stype}: 실패 {str(d)[:200]}"); return
    print(f"== {dep}→{arr} [{stype}] {dt} | 응답 {sec:.2f}s | 총 {b['totalReqHr']//60}분 {b['totalReqHr']%60}초 | 환승 {b['trsitNmtm']}회")
    for L in legs(b):
        if L["walk"]:
            print(f"   ↳ 환승 {L['from']} ({L['line']}) reqHr={L['reqHr']}s wtngHr={L['wtngHr']}s")
        else:
            ex = " 급행" if L["express"] == "Y" else ""
            print(f"   {L['line']}{ex} {L['train']} {L['from']} {L['dep']} → {L['to']} 도착 {L['arr']} | {L['n']}구간(통과 {L['stops_nonstop']}) | {L['dir']} {L['tmnl']}행")

if __name__ == "__main__":
    dt = "2026-09-30 08:50:00"
    trips = [("가양","강남"),("가양","여의도"),("가양","시청"),("가양","샛강"),("신림","잠실")]
    for a,b in trips:
        for st in ("duration","transfer"):
            try: show(a,b,dt,st)
            except Exception as e: print(f"== {a}→{b} {st}: 오류 {e}")
