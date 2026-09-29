import ActivityKit
import Foundation
import Observation

/// 0단계 위험 요소 3: 앱이 꺼져 있어도 잠금화면 카운트다운이 줄어드는지 확인한다.
@Observable
final class LiveActivitySpike {
    static let shared = LiveActivitySpike()
    private(set) var message = ""

    var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var running: Bool { !Activity<DepartureActivityAttributes>.activities.isEmpty }

    func start(minutes: Double) {
        let now = Date.now
        let state = DepartureActivityAttributes.ContentState(
            phase: .beforeLeaving,
            windowStart: now,
            target: now.addingTimeInterval(minutes * 60),
            trainDeparture: now.addingTimeInterval(minutes * 60 + 13 * 60),
            trainLabel: "9호선 급행",
            lineColorHex: "#BDB092")
        do {
            _ = try Activity.request(
                attributes: DepartureActivityAttributes(originName: "가양", destinationName: "강남"),
                content: ActivityContent(state: state, staleDate: now.addingTimeInterval(minutes * 60 + 30 * 60)),
                pushType: nil)
            message = "시작함 · \(Fmt.timeWithSeconds.string(from: now))"
        } catch {
            message = "실패: \(error.localizedDescription)"
        }
    }

    func advanceToPlatform() async {
        for activity in Activity<DepartureActivityAttributes>.activities {
            var s = activity.content.state
            s.phase = .toPlatform
            s.windowStart = .now
            s.target = s.trainDeparture.addingTimeInterval(-4 * 60)
            await activity.update(ActivityContent(state: s, staleDate: nil))
        }
        message = "승강장 단계로 바꿈"
    }

    func endAll() async {
        for activity in Activity<DepartureActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        message = "모두 끝냄"
    }
}
