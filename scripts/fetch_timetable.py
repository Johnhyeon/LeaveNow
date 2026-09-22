#!/usr/bin/env python3
"""서울시메트로9호선 공식 사이트에서 가양역 열차시각표를 받아 timetable.json 으로 변환한다.
사용법: python3 scripts/fetch_timetable.py
"""
import datetime, json, pathlib, re, urllib.parse, urllib.request

STATION_CODE = "4107"          # 가양역 (metro9.co.kr data-sbwy-no)
URL = "https://www.metro9.co.kr/prog/subwayTm/kor/sub01_02/subwayTmAjax.do"
OUT = pathlib.Path(__file__).resolve().parent.parent / "LeaveNow" / "Resources" / "timetable.json"

def fetch(tab):
    """tab: "DT" = 평일, "HD" = 토·공휴일"""
    data = urllib.parse.urlencode({"outsdStnCd": STATION_CODE, "tmTabSe": tab,
                                   "updwtDvsnCd": "1", "trnDateCd": "1"}).encode()
    req = urllib.request.Request(URL, data=data, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")

def panel(html, panel_id):
    start = html.index(f'id="{panel_id}"')
    end = html.find('class="tabpanel', start + 10)
    return html[start:end if end > 0 else len(html)]

def parse_table(html, day_type):
    entries = []
    rows = re.findall(r"<tr>\s*<th>(\d+)시</th>(.*?)</tr>", html, re.S)
    for hour, body in rows:
        cells = re.findall(r"<td>(.*?)</td>", body, re.S)
        for col, direction in zip(cells, ("중앙보훈병원행", "김포공항행")):
            for attrs, text in re.findall(r"<span([^>]*)>\s*([^<]*?)\s*</span>", col):
                m = re.match(r"\*?(\d+)분(?:\((.+?)\))?", text.strip())
                if not m:
                    continue
                minute, note = m.group(1), m.group(2)
                entry = {"direction": direction, "dayType": day_type,
                         "time": f"{int(hour):02d}:{int(minute):02d}",
                         "type": "급행" if "rapid" in attrs else "일반"}
                if note:
                    entry["note"] = note  # 중간 종착 (예: 신논현, 동작, 당산)
                entries.append(entry)
    return entries

entries = (parse_table(panel(fetch("DT"), "tab-panel1"), "weekday")
           + parse_table(panel(fetch("HD"), "tab-panel1"), "weekend"))
entries.sort(key=lambda e: (e["direction"], e["dayType"], e["time"]))
today = datetime.date.today().isoformat()
out = {"station": "가양역 (9호선)", "exit": "10번 출구",
       "source": f"서울시메트로9호선 공식 시각표 ({today} 조회)", "entries": entries}
OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
from collections import Counter
c = Counter((e["direction"], e["dayType"], e["type"]) for e in entries)
for k in sorted(c): print(f"{k[0]} {k[1]} {k[2]}: {c[k]}편")
print(f"wrote {len(entries)} entries -> {OUT}")
