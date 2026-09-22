#!/usr/bin/env python3
"""테스트용 가상 시간표 생성. 실제 9호선 시간표가 아니다.
실제 데이터가 준비되면 같은 형식의 JSON으로 교체하면 된다."""
import json, pathlib

def hhmm(m):
    return f"{m // 60:02d}:{m % 60:02d}"

def band(start, end, every, offset=0):
    t = start + offset
    while t < end:
        yield t
        t += every

def weekday():
    local, express = set(), set()
    local |= set(band(5*60+30, 7*60, 10))
    local |= set(band(7*60, 9*60, 5));          express |= set(band(7*60, 9*60, 10, 2))
    local |= set(band(9*60, 17*60, 7));         express |= set(band(9*60, 17*60, 14, 3))
    local |= set(band(17*60, 20*60, 5));        express |= set(band(17*60, 20*60, 10, 2))
    local |= set(band(20*60, 22*60, 9));        express |= set(band(20*60, 22*60, 18, 4))
    local |= set(band(22*60, 23*60+55, 10))
    return local, express

def weekend():
    local = set(band(5*60+40, 23*60+45, 8))
    express = set(band(7*60, 22*60, 16, 4))
    return local, express

entries = []
for direction, shift in (("중앙보훈병원행", 0), ("김포공항행", 1)):
    for day, fn in (("weekday", weekday), ("weekend", weekend)):
        local, express = fn()
        for m in sorted(local):
            entries.append({"direction": direction, "dayType": day, "time": hhmm(m + shift), "type": "일반"})
        for m in sorted(express):
            entries.append({"direction": direction, "dayType": day, "time": hhmm(m + shift), "type": "급행"})

entries.sort(key=lambda e: (e["direction"], e["dayType"], e["time"]))
out = {
    "station": "가양역 (9호선)",
    "exit": "10번 출구",
    "source": "테스트용 가상 시간표 (실제 아님)",
    "entries": entries,
}
path = pathlib.Path(__file__).resolve().parent.parent / "LeaveNow" / "Resources" / "timetable.json"
path.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"wrote {len(entries)} entries -> {path}")
