#!/usr/bin/env python3
"""서울시메트로9호선 공식 사이트에서 9호선 전 역 열차시각표를 받아 timetable.json 으로 변환한다.
사용법: python3 scripts/fetch_timetable.py
"""
import datetime, json, pathlib, re, sys, urllib.parse, urllib.request

LIST_URL = "https://www.metro9.co.kr/prog/subwayTm/kor/sub01_02/list.do"
AJAX_URL = "https://www.metro9.co.kr/prog/subwayTm/kor/sub01_02/subwayTmAjax.do"
OUT = pathlib.Path(__file__).resolve().parent.parent / "LeaveNow" / "Resources" / "timetable_09.json"
UA = {"User-Agent": "Mozilla/5.0"}

def get(url, data=None):
    req = urllib.request.Request(url, data=data, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")

def stations():
    html = get(LIST_URL)
    found = re.findall(r'data-sbwy-no="(\d+)"\s+class="([^"]*)"\s*>\s*<button>([^<]+)</button>', html)
    seen, out = set(), []
    for code, cls, name in found:
        if code in seen:
            continue
        seen.add(code)
        out.append({"code": code, "name": name.strip(), "express": "express" in cls, "transfer": "transfer" in cls})
    return out

def panel(html, panel_id):
    start = html.index(f'id="{panel_id}"')
    end = html.find('class="tabpanel', start + 10)
    return html[start:end if end > 0 else len(html)]

def parse_table(html, day_type):
    entries = []
    rows = re.findall(r"<tr>\s*<th>(\d+)시</th>(.*?)</tr>", html, re.S)
    for hour, body in rows:
        cells = re.findall(r"<td>(.*?)</td>", body, re.S)
        for col, direction in zip(cells, ("up", "down")):   # up = 중앙보훈병원 방면, down = 개화 방면
            for attrs, text in re.findall(r"<span([^>]*)>\s*([^<]*?)\s*</span>", col):
                m = re.match(r"\*?(\d+)분(?:\((.+?)\))?", text.strip())
                if not m:
                    continue
                entry = {"direction": direction, "dayType": day_type,
                         "time": f"{int(hour):02d}:{int(m.group(1)):02d}",
                         "type": "급행" if "rapid" in attrs else "일반"}
                if m.group(2):
                    entry["note"] = m.group(2)  # 중간 종착 (예: 신논현, 동작, 당산)
                entries.append(entry)
    return entries

def fetch_station(code):
    out = []
    for tab, day in (("DT", "weekday"), ("HD", "weekend")):
        data = urllib.parse.urlencode({"outsdStnCd": code, "tmTabSe": tab,
                                       "updwtDvsnCd": "1", "trnDateCd": "1"}).encode()
        out += parse_table(panel(get(AJAX_URL, data), "tab-panel1"), day)
    out.sort(key=lambda e: (e["direction"], e["dayType"], e["time"]))
    return out

sts = stations()
print(f"{len(sts)}개 역", file=sys.stderr)
for s in sts:
    s["entries"] = fetch_station(s["code"])
    print(f"  {s['name']}: {len(s['entries'])}편", file=sys.stderr)

out = {
    "line": "9호선",
    "source": f"서울시메트로9호선 공식 시각표 ({datetime.date.today().isoformat()} 조회)",
    "directions": {"up": "중앙보훈병원 방면", "down": "개화·김포공항 방면"},
    "stations": sts,
}
OUT.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"wrote {sum(len(s['entries']) for s in sts)} entries -> {OUT} ({OUT.stat().st_size // 1024} KB)")
