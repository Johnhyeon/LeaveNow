# 출발시각 (LeaveNow) 작업 규칙

## 화면을 바꾸면 와이어프레임도 같이
- 앱 화면·동작(문구, 버튼, 흐름, 새 화면)을 바꾸면 같은 작업 안에서 `docs/wireframes.html`의 해당 화면(M1, M7 등)과 메모, 흐름도를 고친다.
- 고친 뒤 커밋하고 아티팩트(https://claude.ai/artifact/V93Y6LhDQZUgrxXNa7x7xM)에 다시 올린다. 따로 묻지 않는다.
- 화면 번호는 와이어프레임을 따르고, 새 화면은 가장 가까운 레인에 새 번호로 넣는다.
- 로드맵 `docs/ROADMAP.md`의 체크 항목도 함께 갱신한다.

## 확인
- 시뮬레이터 확인은 iPhone 17 (`xcrun simctl`, 실행 인자 `-seedTrip`, `-sheetLarge`, `-departNow`, `-routePreview`, `-seedPlaces`, `-listNotifications`, `-editPlace` 등은 `LeaveNow/Views/ContentView.swift` 참고).
- 밝은 모드와 어두운 모드 둘 다 본다.
- 폰 설치는 `./scripts/install_device.sh`.

## 깃
- 작업 브랜치 `v2`. 커밋 작성자는 noreply 주소(저장소 설정됨). 푸시는 요청할 때만.
- API 키는 `LeaveNow/Resources/Secrets.plist`(깃 제외)에만. 출력하거나 붙여넣지 않는다.
