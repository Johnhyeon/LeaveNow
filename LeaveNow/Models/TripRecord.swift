import Foundation
import SwiftData

/// 측정 모드로 기록한 한 번의 이동
@Model
final class TripRecord {
    var date: Date
    var directionRaw: String
    /// SegmentKind.allCases 와 같은 순서, 같은 길이의 배열 (초)
    var durations: [Double]
    var note: String

    init(date: Date = .now, direction: Direction, durations: [Double], note: String = "") {
        self.date = date
        self.directionRaw = direction.rawValue
        self.durations = durations
        self.note = note
    }

    var direction: Direction { Direction.parse(directionRaw) }

    func duration(for kind: SegmentKind) -> Double? {
        guard let i = SegmentKind.allCases.firstIndex(of: kind), i < durations.count else { return nil }
        return durations[i]
    }

    /// 승강장 대기를 뺀 이동 시간 합계
    var travelTotal: Double {
        SegmentKind.travelSegments.compactMap { duration(for: $0) }.reduce(0, +)
    }

    var total: Double { durations.reduce(0, +) }
}
