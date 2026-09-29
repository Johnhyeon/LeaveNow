import Foundation
import SwiftData

/// 저장한 목적지. 이름은 처음엔 역 이름이고 나중에 "회사"처럼 바꿀 수 있다.
@Model
final class Place {
    var name: String
    var stationName: String
    /// 역에서 최종 목적지까지 걷는 시간 (분)
    var walkFromStation: Int
    /// 도착해야 하는 시각, 자정부터 분. 역만 등록하고 아직 가본 적 없으면 -1
    var deadlineMinutes: Int
    var createdAt: Date
    var lastUsedAt: Date
    /// 자주 가는 곳으로 직접 등록했는지
    var favorite: Bool = false

    init(name: String, stationName: String, walkFromStation: Int, deadlineMinutes: Int) {
        self.name = name
        self.stationName = stationName
        self.walkFromStation = walkFromStation
        self.deadlineMinutes = deadlineMinutes
        self.createdAt = .now
        self.lastUsedAt = .now
    }

    /// "9:00" 같은 도착 시각. 정해진 적 없으면 nil
    var deadlineText: String? {
        deadlineMinutes < 0 ? nil : String(format: "%d:%02d", deadlineMinutes / 60, deadlineMinutes % 60)
    }
}

/// 오늘(또는 가까운 날) 하기로 한 이동 하나와 그 계산 결과
@Model
final class PlannedTrip {
    var placeName: String
    var destinationStation: String
    var walkFromStation: Int
    var deadline: Date
    var originData: Data     // OriginInfo
    var planData: Data       // TripPlan
    var createdAt: Date
    var cancelled: Bool

    init(placeName: String, destinationStation: String, walkFromStation: Int, deadline: Date, origin: OriginInfo, plan: TripPlan) {
        self.placeName = placeName
        self.destinationStation = destinationStation
        self.walkFromStation = walkFromStation
        self.deadline = deadline
        self.originData = (try? JSONEncoder().encode(origin)) ?? Data()
        self.planData = (try? JSONEncoder().encode(plan)) ?? Data()
        self.createdAt = .now
        self.cancelled = false
    }

    var origin: OriginInfo? { try? JSONDecoder().decode(OriginInfo.self, from: originData) }
    var plan: TripPlan? { try? JSONDecoder().decode(TripPlan.self, from: planData) }

    func update(plan: TripPlan) {
        planData = (try? JSONEncoder().encode(plan)) ?? planData
    }

    /// 목적지 도착 예정 (역 도착 + 걸어서)
    var expectedArrival: Date? {
        plan.map { $0.trip.arrival.addingTimeInterval(TimeInterval(walkFromStation * 60)) }
    }
}
