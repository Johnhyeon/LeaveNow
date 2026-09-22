#!/bin/zsh
# 연결된 실제 아이폰에 앱을 빌드·설치·실행한다.
# 사전 조건: Xcode > Settings > Accounts 에 Apple ID 등록, 아이폰 케이블 연결 + 개발자 모드 켜기.
set -e
cd "$(dirname "$0")/.."

# 1) 팀 ID: 개발용 인증서 이름 "Apple Development: 이름 (팀ID)" 에서 추출
TEAM=$(security find-identity -v -p codesigning | grep "Apple Development" | grep -o '([A-Z0-9]\{10\})' | head -1 | tr -d '()')
if [[ -z "$TEAM" ]]; then
  echo "❌ 개발용 서명 인증서가 없습니다. Xcode > Settings > Accounts 에서 Apple ID를 추가하세요."
  exit 1
fi
echo "✅ 팀 ID: $TEAM"

# 2) 연결된 실제 기기 이름
NAME=$(xcrun devicectl list devices 2>/dev/null | awk '$0 ~ /physical/ && $0 ~ /connected|available/ {sub(/ +[a-zA-Z0-9.-]* +[0-9A-F-]{36}.*$/, ""); print; exit}')
if [[ -z "$NAME" ]]; then
  echo "❌ 연결된 아이폰이 없습니다. 케이블로 연결하고 아이폰에서 '신뢰'를 누르세요."
  xcrun devicectl list devices
  exit 1
fi
echo "✅ 기기: $NAME"

# 3) 빌드 (자동 서명, 프로비저닝 프로파일 자동 생성)
xcodebuild -project LeaveNow.xcodeproj -scheme LeaveNow \
  -destination "platform=iOS,name=$NAME" \
  -derivedDataPath build -configuration Debug \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" build \
  | grep -E "error:|warning: .*signing|BUILD (SUCCEEDED|FAILED)" || true

APP=build/Build/Products/Debug-iphoneos/LeaveNow.app
[[ -d "$APP" ]] || { echo "❌ 빌드 산출물이 없습니다."; exit 1; }

# 4) 설치 + 실행
UDID=$(xcrun devicectl list devices 2>/dev/null | grep physical | grep -o '[0-9A-F-]\{36\}' | head -1)
xcrun devicectl device install app --device "$UDID" "$APP"
xcrun devicectl device process launch --device "$UDID" com.drimaes.LeaveNow
echo "🎉 설치 완료. 아이폰에서 '출발시각' 앱을 확인하세요."
