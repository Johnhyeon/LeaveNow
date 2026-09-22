# 출발시각 (LeaveNow)

집에서 나서는 순간부터 지하철 탑승까지의 구간별 소요 시간을 직접 측정해, **몇 시에 집에서 나가야 하는지** 알려주는 iOS 앱.

- 9호선 전 역 공식 시각표 내장 (평일 / 토·공휴일, 일반 / 급행)
- 구간별 스톱워치 측정 → 평균 또는 안전(느린 날 기준) 추정으로 자동 전환
- 횡단보도 신호 주기 측정, 시계로 잰 값 직접 입력
- 열차별 1회 알림, 평일 출근 반복 알림

## 개발

- Xcode 27, Swift / SwiftUI / SwiftData, iOS 17+
- 프로젝트 파일은 [xcodegen](https://github.com/yonaskolb/XcodeGen)으로 `project.yml`에서 생성: `xcodegen generate`
- 시간표 갱신: `python3 scripts/fetch_timetable.py`
- 실기기 설치: `./scripts/install_device.sh` (Xcode에 Apple ID 등록, 아이폰 개발자 모드 필요)

## 로드맵

- 1~8호선 등 전 노선 시간표 (서울 열린데이터광장 API)
- 실시간 도착·지연 정보 반영
- 목적지 도착 시각 → 출발 시각 역산
