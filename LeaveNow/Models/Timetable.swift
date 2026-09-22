import Foundation

/// 노선의 상·하행. 표시 이름은 시간표 파일의 directions 에서 가져온다.
enum Direction: String, CaseIterable, Codable, Identifiable {
    case up
    case down

    var id: String { rawValue }

    var title: String { Timetable.shared.directionTitles[rawValue] ?? rawValue }

    /// 예전 저장값("중앙보훈병원행", "김포공항행")도 읽을 수 있게 한다
    static func parse(_ raw: String?) -> Direction {
        switch raw {
        case "up", "중앙보훈병원행": return .up
        case "down", "김포공항행": return .down
        default: return .up
        }
    }
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
    let stationCode: String
    let direction: Direction
    let dayType: DayType
    let minutesOfDay: Int
    let type: TrainType
    let note: String?

    var id: String { "\(stationCode)-\(direction.rawValue)-\(dayType.rawValue)-\(minutesOfDay)-\(type.rawValue)" }

    var timeString: String { String(format: "%02d:%02d", minutesOfDay / 60, minutesOfDay % 60) }

    func departure(on date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: minutesOfDay, to: start) ?? start
    }
}

struct Station: Identifiable, Hashable {
    let code: String
    let name: String
    let isExpressStop: Bool
    let isTransfer: Bool
    let trains: [Train]

    var id: String { code }
}

/// Resources/timetable.json 의 형식
struct TimetableFile: Codable {
    struct Entry: Codable {
        let direction: String  // "up" | "down"
        let dayType: String    // "weekday" | "weekend"
        let time: String       // "HH:mm"
        let type: String       // "일반" | "급행"
        let note: String?      // 중간 종착역 등
    }
    struct StationEntry: Codable {
        let code: String
        let name: String
        let express: Bool
        let transfer: Bool
        let entries: [Entry]
    }
    let line: String
    let source: String
    let directions: [String: String]
    let stations: [StationEntry]
}

final class Timetable {
    static let shared = Timetable()
    static let defaultStationCode = "4107"   // 가양

    let line: String
    let source: String
    let directionTitles: [String: String]
    let stations: [Station]

    private init() {
        guard let url = Bundle.main.url(forResource: "timetable", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(TimetableFile.self, from: data) else {
            line = "?"
            source = "시간표 파일을 읽지 못했습니다"
            directionTitles = [:]
            stations = []
            return
        }
        line = file.line
        source = file.source
        directionTitles = file.directions
        stations = file.stations.map { st in
            let trains = st.entries.compactMap { e -> Train? in
                guard let d = Direction(rawValue: e.direction),
                      let dt = DayType(rawValue: e.dayType),
                      let t = TrainType(rawValue: e.type) else { return nil }
                let parts = e.time.split(separator: ":").compactMap { Int($0) }
                guard parts.count == 2 else { return nil }
                return Train(stationCode: st.code, direction: d, dayType: dt,
                             minutesOfDay: parts[0] * 60 + parts[1], type: t, note: e.note)
            }
            .sorted { $0.minutesOfDay < $1.minutesOfDay }
            return Station(code: st.code, name: st.name, isExpressStop: st.express, isTransfer: st.transfer, trains: trains)
        }
    }

    func station(code: String) -> Station? {
        stations.first { $0.code == code } ?? stations.first { $0.code == Self.defaultStationCode } ?? stations.first
    }

    func trains(stationCode: String, direction: Direction, dayType: DayType) -> [Train] {
        station(code: stationCode)?.trains.filter { $0.direction == direction && $0.dayType == dayType } ?? []
    }
}
