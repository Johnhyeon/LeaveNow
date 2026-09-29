import ActivityKit
import Foundation

/// 출발 버튼을 누르면 잠금화면과 다이내믹 아일랜드에 띄우는 이동 표시 (C1).
/// 열차 출발 시각을 staleDate 로 넣어 두면, 앱이 꺼져 있어도 그때부터 도착까지 세는 화면으로 바뀐다.
enum TripActivity {
    static var isRunning: Bool { !Activity<DepartureActivityAttributes>.activities.isEmpty }

    static func start(plan: TripPlan, origin: OriginInfo, destinationName: String, startedAt: Date = .now) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endAll()
        let ride = plan.trip.rides.first
        let state = DepartureActivityAttributes.ContentState(
            windowStart: startedAt,
            trainDeparture: plan.trip.departure,
            platformBy: plan.platformBy,
            arrival: plan.trip.arrival,
            trainLabel: TripNotifier.shortTrainLabel(plan),
            lineColorHex: LineStyle.hex(ride?.line ?? ""))
        _ = try? Activity.request(
            attributes: DepartureActivityAttributes(originName: origin.station, destinationName: destinationName),
            content: ActivityContent(state: state, staleDate: plan.trip.departure),
            pushType: nil)
    }

    static func endAll() {
        for activity in Activity<DepartureActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
