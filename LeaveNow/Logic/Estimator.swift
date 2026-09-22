import Foundation

enum EstimateMode: String, CaseIterable, Identifiable {
    case mean = "평균"
    case safe = "안전"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .mean: return "측정값의 평균으로 계산"
        case .safe: return "측정값 상위 90% (느린 날 기준)로 계산"
        }
    }
}

struct SegmentEstimate: Identifiable {
    let kind: SegmentKind
    let seconds: Double
    let sampleCount: Int

    var id: SegmentKind { kind }
    var isMeasured: Bool { sampleCount >= Estimator.minimumSamples }
}

enum Estimator {
    /// 이 횟수 이상 측정된 구간부터 실측값을 쓴다
    static let minimumSamples = 3

    static func estimates(records: [TripRecord], mode: EstimateMode) -> [SegmentEstimate] {
        let defaults = SegmentDefaults.load()
        return SegmentKind.allCases.map { kind in
            let values = records.compactMap { $0.duration(for: kind) }.filter { $0 > 0 }
            if values.count >= minimumSamples {
                return SegmentEstimate(kind: kind, seconds: aggregate(values, mode: mode), sampleCount: values.count)
            }
            if kind == .crosswalk, let fromSignal = crosswalkFromSignal(mode: mode) {
                return SegmentEstimate(kind: kind, seconds: fromSignal, sampleCount: values.count)
            }
            return SegmentEstimate(kind: kind,
                                   seconds: defaults[kind] ?? kind.testDefaultSeconds,
                                   sampleCount: values.count)
        }
    }

    /// 신호 주기를 쟀다면: 안전 모드는 빨간불 전체 길이(최악), 평균 모드는 그 절반
    static func crosswalkFromSignal(mode: EstimateMode) -> Double? {
        let red = UserDefaults.standard.double(forKey: "crosswalkRedSeconds")
        guard red > 0 else { return nil }
        return mode == .safe ? red : red / 2
    }

    static func aggregate(_ values: [Double], mode: EstimateMode) -> Double {
        guard !values.isEmpty else { return 0 }
        switch mode {
        case .mean:
            return values.reduce(0, +) / Double(values.count)
        case .safe:
            let sorted = values.sorted()
            let rank = Int((0.9 * Double(sorted.count)).rounded(.up)) - 1
            return sorted[max(0, min(sorted.count - 1, rank))]
        }
    }

    static func travelSeconds(_ estimates: [SegmentEstimate], includePrep: Bool) -> Double {
        estimates
            .filter { $0.kind.countsTowardTravel && (includePrep || $0.kind != .prep) }
            .map(\.seconds)
            .reduce(0, +)
    }
}
