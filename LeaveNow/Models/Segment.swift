import Foundation

/// 집에서 열차 탑승까지의 구간. 배열 순서가 곧 측정 순서다.
enum SegmentKind: String, CaseIterable, Codable, Identifiable {
    case prep
    case elevator
    case walkToCrosswalk
    case crosswalk
    case toPlatform
    case platformWait

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prep: return "준비 (옷·신발)"
        case .elevator: return "엘리베이터 대기"
        case .walkToCrosswalk: return "횡단보도까지 이동"
        case .crosswalk: return "횡단보도 대기"
        case .toPlatform: return "승강장까지 이동"
        case .platformWait: return "승강장 대기"
        }
    }

    var subtitle: String {
        switch self {
        case .prep: return "옷 입고 신발 신고 현관을 나설 때까지"
        case .elevator: return "버튼 누른 뒤 엘리베이터가 올 때까지"
        case .walkToCrosswalk: return "엘리베이터 타고 내려가 횡단보도 앞까지"
        case .crosswalk: return "초록불이 켜질 때까지"
        case .toPlatform: return "길 건너 에스컬레이터로 승강장까지"
        case .platformWait: return "승강장에서 열차가 올 때까지"
        }
    }

    /// 측정 화면에서 이 구간이 끝났음을 알리는 버튼 문구
    var finishLabel: String {
        switch self {
        case .prep: return "현관 나섬"
        case .elevator: return "엘리베이터 탑승"
        case .walkToCrosswalk: return "횡단보도 앞 도착"
        case .crosswalk: return "초록불 켜짐"
        case .toPlatform: return "승강장 도착"
        case .platformWait: return "열차 탑승"
        }
    }

    var systemImage: String {
        switch self {
        case .prep: return "door.left.hand.open"
        case .elevator: return "arrow.up.arrow.down.square"
        case .walkToCrosswalk: return "figure.walk"
        case .crosswalk: return "light.beacon.max"
        case .toPlatform: return "arrow.down.right.circle"
        case .platformWait: return "tram"
        }
    }

    /// 통제할 수 없어 날마다 달라지는 구간
    var isVariable: Bool { self == .elevator || self == .crosswalk }

    /// 출발 시각 계산에 포함되는 구간인지. 승강장 대기는 여유 시간(버퍼)으로 따로 다룬다.
    var countsTowardTravel: Bool { self != .platformWait }

    /// 실측 전에 쓰는 테스트 값 (초)
    var testDefaultSeconds: Double {
        switch self {
        case .prep: return 180
        case .elevator: return 60
        case .walkToCrosswalk: return 120
        case .crosswalk: return 60
        case .toPlatform: return 150
        case .platformWait: return 240
        }
    }

    static var travelSegments: [SegmentKind] { allCases.filter(\.countsTowardTravel) }
}

/// 사용자가 설정 화면에서 바꾼 테스트 값 저장소
enum SegmentDefaults {
    private static let key = "segmentDefaultSeconds"

    static func load() -> [SegmentKind: Double] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        var out: [SegmentKind: Double] = [:]
        for (k, v) in dict {
            if let kind = SegmentKind(rawValue: k) { out[kind] = v }
        }
        return out
    }

    static func save(_ values: [SegmentKind: Double]) {
        var dict: [String: Double] = [:]
        for (k, v) in values { dict[k.rawValue] = v }
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func value(for kind: SegmentKind) -> Double {
        load()[kind] ?? kind.testDefaultSeconds
    }
}
