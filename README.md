# 출발시각 (LeaveNow)

집에서 나서는 순간부터 지하철 탑승까지의 구간별 소요 시간을 직접 측정해, **몇 시에 집에서 나가야 하는지** 알려주는 iOS 앱.

- 서울 지하철 1~9호선 지원. 9호선은 공식 시각표 내장, 1~8호선은 고른 역의 시간표만 서울 열린데이터광장 API로 받아 기기에 저장
- 실시간 도착 정보(서울시 API)로 지연을 표시하고 출발 시각에 반영
- 첫 실행 시 노선·역·방향 설정 화면
- 구간별 스톱워치 측정 → 평균 또는 안전(느린 날 기준) 추정으로 자동 전환
- 횡단보도 신호 주기 측정, 시계로 잰 값 직접 입력
- 열차별 1회 알림, 평일 출근 반복 알림

## 개발

- Xcode 27, Swift / SwiftUI / SwiftData, iOS 17+
- 프로젝트 파일은 [xcodegen](https://github.com/yonaskolb/XcodeGen)으로 `project.yml`에서 생성: `xcodegen generate`
- 9호선 내장 시간표 갱신: `python3 scripts/fetch_timetable.py`
- API 키: `LeaveNow/Resources/Secrets.example.plist` 를 `Secrets.plist` 로 복사하고 서울 열린데이터광장 인증키 입력 (git 제외)
- 실기기 설치: `./scripts/install_device.sh` (Xcode에 Apple ID 등록, 아이폰 개발자 모드 필요)

## 로드맵

- 목적지 도착 시각 → 출발 시각 역산
- 공휴일 달력 반영 (현재는 일요일만 휴일 시간표)
- 위젯 / 잠금화면 표시
