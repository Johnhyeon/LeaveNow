#!/bin/zsh
# 연결된 실제 아이폰에 앱을 빌드·설치·실행한다.
# 사전 조건: Xcode > Settings > Accounts 에 Apple ID 등록, 아이폰 케이블 연결 + 개발자 모드 켜기.
set -e
cd "$(dirname "$0")/.."

# 1) 팀 ID: project.yml 의 DEVELOPMENT_TEAM (Xcode > Settings > Accounts 의 Personal Team)
TEAM=$(grep -o 'DEVELOPMENT_TEAM: [A-Z0-9]*' project.yml | awk '{print $2}')
if [[ -z "$TEAM" ]]; then
  echo "❌ project.yml 에 DEVELOPMENT_TEAM 이 없습니다. Xcode > Settings > Accounts 에서 Apple ID를 추가한 뒤 팀 ID를 적어주세요."
  exit 1
fi
echo "✅ 팀 ID: $TEAM"

# 2) 연결된 실제 기기 UDID (이름이 비어 있을 수 있어 JSON에서 UDID를 읽는다)
UDID=$(xcrun devicectl list devices --json-output /tmp/devices.json >/dev/null 2>&1; python3 - <<'PY'
import json
d = json.load(open("/tmp/devices.json"))
for dev in d.get("result", {}).get("devices", []):
    hp = dev.get("hardwareProperties", {})
    cp = dev.get("connectionProperties", {})
    if hp.get("reality") == "physical" and cp.get("tunnelState") != "unavailable":
        print(hp.get("udid", "")); break
PY
)
if [[ -z "$UDID" ]]; then
  echo "❌ 연결된 아이폰이 없습니다. 케이블로 연결하고 아이폰에서 '신뢰'를 누르세요."
  xcrun devicectl list devices
  exit 1
fi
echo "✅ 기기 UDID: $UDID"

# 3) 빌드 (자동 서명, 프로비저닝 프로파일 자동 생성)
xcodebuild -project LeaveNow.xcodeproj -scheme LeaveNow \
  -destination "platform=iOS,id=$UDID" \
  -derivedDataPath build -configuration Debug \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" build \
  | grep -E "error:|warning: .*signing|BUILD (SUCCEEDED|FAILED)" || true

APP=build/Build/Products/Debug-iphoneos/LeaveNow.app
[[ -d "$APP" ]] || { echo "❌ 빌드 산출물이 없습니다."; exit 1; }

# 4) 설치 + 실행
xcrun devicectl device install app --device "$UDID" "$APP"
xcrun devicectl device process launch --device "$UDID" com.drimaes.LeaveNow
echo "🎉 설치 완료. 아이폰에서 '출발시각' 앱을 확인하세요."
