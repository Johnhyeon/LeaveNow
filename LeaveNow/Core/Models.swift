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
    /// 반복(루틴) 요일. 비트 1 << Calendar 요일(일=1 … 토=7). 0이면 반복 없음
    var repeatDays: Int = 0
    /// "오늘은 안 가요"를 누른 날 (yyyyMMdd)
    var skippedDay: String = ""

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

    /// 반복 일정이 켜져 있는지 (요일과 도착 시각이 모두 있어야 한다)
    var repeats: Bool { repeatDays != 0 && deadlineMinutes >= 0 }

    func repeats(on date: Date) -> Bool {
        repeats && repeatDays & (1 << Calendar.current.component(.weekday, from: date)) != 0
    }

    /// 그날의 도착 마감
    func deadline(on date: Date) -> Date? {
        guard deadlineMinutes >= 0 else { return nil }
        return Calendar.current.date(bySettingHour: deadlineMinutes / 60, minute: deadlineMinutes % 60, second: 0, of: date)
    }

    /// "평일", "주말", "매일", "월·수·금"
    var repeatText: String? { Place.daysText(repeatDays) }

    static func daysText(_ days: Int) -> String? {
        guard days != 0 else { return nil }
        let weekdays = (2...6).reduce(0) { $0 | 1 << $1 }, weekend = 1 << 1 | 1 << 7
        if days == weekdays | weekend { return "매일" }
        if days == weekdays { return "평일" }
        if days == weekend { return "주말" }
        return weekdayOrder.filter { days & 1 << $0 != 0 }.map { weekdayNames[$0] }.joined(separator: "·")
    }

    /// 월요일부터 (Calendar 요일 번호)
    static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    static let weekdayNames = ["", "일", "월", "화", "수", "목", "금", "토"]

    /// 칩에 쓰는 한 줄: "회사 · 평일 10:00", "헬스장"
    var chipText: String {
        guard let time = deadlineText else { return name }
        return [name, [repeatText, time].compactMap { $0 }.joined(separator: " ")].joined(separator: " · ")
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
    /// 출발 버튼을 누른 시각. 집에서 승강장까지 시간을 배우는 데도 쓴다
    var departedAt: Date? = nil

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
