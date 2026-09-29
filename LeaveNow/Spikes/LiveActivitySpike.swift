import ActivityKit
import Foundation
import Observation

/// 0단계 위험 요소 3: 앱이 꺼져 있어도 잠금화면 카운트다운이 줄어드는지 확인한다.
/// minutes 뒤 열차가 떠나고 13분 뒤 도착하는 가짜 이동을 띄운다.
@Observable
final class LiveActivitySpike {
    static let shared = LiveActivitySpike()
    private(set) var message = ""

    var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var running: Bool { !Activity<DepartureActivityAttributes>.activities.isEmpty }

    func start(minutes: Double) {
        let now = Date.now
        let departure = now.addingTimeInterval(minutes * 60)
        let state = DepartureActivityAttributes.ContentState(
            windowStart: now,
            trainDeparture: departure,
            platformBy: departure.addingTimeInterval(-4 * 60),
            arrival: departure.addingTimeInterval(13 * 60),
            trainLabel: Fmt.time.string(from: departure) + " 급행",
            lineColorHex: "#BDB092")
        do {
            _ = try Activity.request(
                attributes: DepartureActivityAttributes(originName: "가양", destinationName: "강남"),
                content: ActivityContent(state: state, staleDate: departure),
                pushType: nil)
            message = "시작함 · \(Fmt.timeWithSeconds.string(from: now))"
        } catch {
            message = "실패: \(error.localizedDescription)"
        }
    }

    func endAll() async {
        for activity in Activity<DepartureActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        message = "모두 끝냄"
    }
}
