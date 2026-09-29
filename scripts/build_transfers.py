#!/usr/bin/env python3
"""서울교통공사 환승 데이터 두 파일을 앱용 transfers.json 으로 만든다.
- scripts/data/transfer_distance.csv : 환승역거리 소요시간 정보 (OA-13290)
- scripts/data/transfer_cars.csv     : 수도권 도시철도 환승 데이터 (OA-22521, 내릴 칸·갈아탈 칸)
파일은 data.seoul.go.kr 에서 받는다 (README 참고). 사용법: python3 scripts/build_transfers.py
"""
import csv, io, json, pathlib, re
ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "scripts" / "data"

def load(name):
    raw = (DATA / name).read_bytes()
    for enc in ("utf-8-sig", "cp949"):
        try:
            return list(csv.DictReader(io.StringIO(raw.decode(enc))))
        except UnicodeDecodeError:
            pass
    raise SystemExit(f"{name}: 인코딩을 알 수 없음")

def norm_line(s):
    """노선 이름을 앱과 같은 짧은 키로. RouteAPI 의 lineNm 도 같은 규칙(Transfers.swift)으로 바꾼다."""
    s = (s or "").strip()
    m = re.fullmatch(r"(\d)(호선)?", s)
    if m: return m.group(1)
    table = [("신분당", "신분당"), ("경의", "경의중앙"), ("분당", "수인분당"), ("수인", "수인분당"), ("공항", "공항철도"),
             ("우이", "우이신설"), ("의정부", "의정부"), ("용인", "에버라인"), ("에버", "에버라인"), ("신림", "신림"),
             ("서해", "서해"), ("경춘", "경춘"), ("김포", "김포골드"), ("인천1", "인천1"), ("인천2", "인천2"), ("경강", "경강")]
    for k, v in table:
        if k in s: return v
    return s

def base(name):
    return (name or "").split("(")[0].replace(" 방면", "").strip()

def secs(t):
    m, s = (t or "0:0").split(":")[:2]
    return int(m) * 60 + int(s)

walk = {}
for r in load("transfer_distance.csv"):
    key = f"{base(r['환승역명'])}|{norm_line(r['호선'])}|{norm_line(r['환승노선'])}"
    walk[key] = {"m": int(r["환승거리"]), "s": secs(r["환승소요시간"])}

cars = []
for r in load("transfer_cars.csv"):
    cars.append({
        "st": base(r["환승시작역"]),
        "from": norm_line(r["환승시작 호선"]),
        "dir": base(r["하차 열차 방면"]),
        "alight": f"{r['하차위치(호차)']}-{r['하차위치(문)']}",
        "to": norm_line(r["환승종료 호선"]),
        "toDir": base(r["환승 열차 방면"]),
        "board": f"{r['환승 승차위치(호차)']}-{r['환승 승차위치(문)']}",
    })

out = {"source": "서울교통공사 환승역거리 소요시간 정보(OA-13290), 수도권 도시철도 환승 데이터(OA-22521)",
       "walk": walk, "cars": cars}
path = ROOT / "LeaveNow" / "Resources" / "transfers.json"
path.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"환승 거리 {len(walk)}개, 빠른 칸 {len(cars)}개 → {path} ({path.stat().st_size // 1024} KB)")
