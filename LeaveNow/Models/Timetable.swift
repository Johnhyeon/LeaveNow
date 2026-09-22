import Foundation

enum Direction: String, CaseIterable, Codable, Identifiable {
    case bohun = "중앙보훈병원행"
    case gimpo = "김포공항행"
    var id: String { rawValue }
}

enum TrainType: String, Codable {
    case local = "일반"
    case express = "급행"
}

enum DayType: String, Codable, CaseIterable {
    case weekday
    case weekend

    var title: String { self == .weekday ? "평일" : "주말·공휴일" }

    static func of(_ date: Date, calendar: Calendar = .current) -> DayType {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday == 1 || weekday == 7) ? .weekend : .weekday
    }
}

struct Train: Identifiable, Hashable {
    let direction: Direction
    let dayType: DayType
    let minutesOfDay: Int
    let type: TrainType
    let note: String?

    var id: String { "\(direction.rawValue)-\(dayType.rawValue)-\(minutesOfDay)-\(type.rawValue)" }

    var timeString: String { String(format: "%02d:%02d", minutesOfDay / 60, minutesOfDay % 60) }

    func departure(on date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: minutesOfDay, to: start) ?? start
    }
}

/// Resources/timetable.json 의 형식
struct TimetableFile: Codable {
    struct Entry: Codable {
        let direction: String
        let dayType: String
        let time: String   // "HH:mm"
        let type: String   // "일반" | "급행"
        let note: String?  // 중간 종착역 등 (예: "신논현")
    }
    let station: String
    let exit: String
    let source: String
    let entries: [Entry]
}

final class Timetable {
    static let shared = Timetable()

    let station: String
    let exit: String
    let source: String
    let trains: [Train]

    private init() {
        guard let url = Bundle.main.url(forResource: "timetable", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(TimetableFile.self, from: data) else {
            station = "?"
            exit = ""
            source = "시간표 파일을 읽지 못했습니다"
            trains = []
            return
        }
        station = file.station
        exit = file.exit
        source = file.source
        trains = file.entries.compactMap { e -> Train? in
            guard let d = Direction(rawValue: e.direction),
                  let dt = DayType(rawValue: e.dayType),
                  let t = TrainType(rawValue: e.type) else { return nil }
            let parts = e.time.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return Train(direction: d, dayType: dt, minutesOfDay: parts[0] * 60 + parts[1], type: t, note: e.note)
        }
        .sorted { $0.minutesOfDay < $1.minutesOfDay }
    }

    func trains(direction: Direction, dayType: DayType) -> [Train] {
        trains.filter { $0.direction == direction && $0.dayType == dayType }
    }
}
