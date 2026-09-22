import Foundation

/// 열차 하나에 대한 출발 계획
struct TrainOption: Identifiable {
    let train: Train
    let departure: Date
    /// 이 시각까지 집에서 나서야 한다
    let leaveBy: Date
    /// 승강장 도착 목표 시각 (열차 시각 - 여유)
    let platformArrival: Date
    /// 실시간 지연(초). 0이면 시간표 그대로
    var delay: TimeInterval = 0

    var id: String { train.id }

    /// 지연을 반영한 새 계획
    func applying(delay: TimeInterval) -> TrainOption {
        TrainOption(train: train,
                    departure: departure.addingTimeInterval(delay),
                    leaveBy: leaveBy.addingTimeInterval(delay),
                    platformArrival: platformArrival.addingTimeInterval(delay),
                    delay: delay)
    }

    func isCatchable(at now: Date) -> Bool { leaveBy >= now }
}

enum Planner {
    /// 출발 시각 = 열차 시각 - 승강장 여유 - 이동 시간
    static func options(now: Date,
                        stationCode: String,
                        direction: Direction,
                        bufferSeconds: Double,
                        travelSeconds: Double,
                        timetable: Timetable = .shared,
                        limit: Int = 8) -> [TrainOption] {
        let dayType = DayType.of(now)
        let calendar = Calendar.current
        // 새벽 3시 이전 열차는 전날 운행분이므로, 낮에 조회하면 다음 날짜로 붙인다
        let nextDay = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let afterThreeAM = calendar.component(.hour, from: now) >= 3
        return timetable.trains(stationCode: stationCode, direction: direction, dayType: dayType)
            .map { train -> TrainOption in
                let isLateNight = train.minutesOfDay < 180
                let departure = train.departure(on: isLateNight && afterThreeAM ? nextDay : now)
                let platform = departure.addingTimeInterval(-bufferSeconds)
                return TrainOption(train: train,
                                   departure: departure,
                                   leaveBy: platform.addingTimeInterval(-travelSeconds),
                                   platformArrival: platform)
            }
            .filter { $0.departure > now }
            .sorted { $0.departure < $1.departure }
            .prefix(limit)
            .map { $0 }
    }
}
