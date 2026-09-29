import ActivityKit
import Foundation

/// 출발부터 도착까지 하나의 라이브 액티비티. 앱과 위젯 확장이 함께 쓴다.
/// 앱이 꺼져 있어도 바뀌도록 모든 시각을 처음에 넣어 둔다:
/// 열차 출발 전에는 열차까지, 열차가 떠나면(staleDate) 도착까지 센다.
struct DepartureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 출발 버튼을 누른 시각. 이때부터 열차 출발까지 물이 빠진다
        var windowStart: Date
        /// 탈 열차 출발 시각
        var trainDeparture: Date
        /// 승강장 도착 목표 (열차 출발 - 승강장 여유)
        var platformBy: Date
        /// 도착역 도착 시각
        var arrival: Date
        var trainLabel: String   // 예: "9:12 급행"
        var lineColorHex: String
    }

    var originName: String       // 예: "가양"
    var destinationName: String  // 예: "강남"
}
