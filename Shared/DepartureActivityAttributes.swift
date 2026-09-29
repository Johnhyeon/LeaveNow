import ActivityKit
import Foundation

/// 출발부터 도착까지 하나의 라이브 액티비티. 앱과 위젯 확장이 함께 쓴다.
struct DepartureActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case beforeLeaving   // 현관까지 카운트다운
            case toPlatform      // 승강장 목표까지 카운트다운
            case done
        }
        var phase: Phase
        /// 물이 가득 찬 상태로 시작한 시각. 이때부터 target 까지 물이 빠진다
        var windowStart: Date
        /// 지금 단계의 목표 시각 (현관 출발 또는 승강장 도착)
        var target: Date
        /// 탈 열차 출발 시각
        var trainDeparture: Date
        var trainLabel: String   // 예: "9호선 급행"
        var lineColorHex: String
    }

    var originName: String       // 예: "가양"
    var destinationName: String  // 예: "강남"
}
