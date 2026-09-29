#!/usr/bin/env python3
"""서울 열린데이터광장 subwayStationMaster 로 수도권 역 목록(이름, 노선, 좌표)을 만들어 앱에 넣는다.
같은 이름의 역은 하나로 묶는다 (환승역). 사용법: python3 scripts/build_stations.py
"""
import json, pathlib, plistlib, urllib.request, collections
ROOT = pathlib.Path(__file__).resolve().parent.parent
KEY = plistlib.load(open(ROOT / "LeaveNow/Resources/Secrets.plist", "rb"))["SeoulOpenAPIKey"]
d = json.load(urllib.request.urlopen(f"http://openapi.seoul.go.kr:8088/{KEY}/json/subwayStationMaster/1/1000/", timeout=30))
rows = d["subwayStationMaster"]["row"]
by = collections.OrderedDict()
for r in rows:
    name = r["BLDN_NM"].strip()
    e = by.setdefault(name, {"name": name, "lines": [], "ids": [], "lat": [], "lon": []})
    route = r["ROUTE"].strip()
    if route not in e["lines"]:
        e["lines"].append(route)
    e["ids"].append(r["BLDN_ID"])
    try:
        e["lat"].append(float(r["LAT"])); e["lon"].append(float(r["LOT"]))
    except ValueError:
        pass
out = []
for e in by.values():
    if not e["lat"]:
        continue
    out.append({"name": e["name"], "query": e["name"].split("(")[0].strip(), "lines": e["lines"], "ids": e["ids"],
                "lat": round(sum(e["lat"]) / len(e["lat"]), 6), "lon": round(sum(e["lon"]) / len(e["lon"]), 6)})
out.sort(key=lambda x: x["name"])
path = ROOT / "LeaveNow/Resources/stations.json"
path.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"{len(rows)} rows → {len(out)} stations, {path.stat().st_size // 1024} KB")
print("괄호 있는 이름:", [x["name"] for x in out if "(" in x["name"]][:10])
