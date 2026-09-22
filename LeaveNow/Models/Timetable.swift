import Foundation
import Observation

/// 노선의 상·하행. 표시 이름은 역별 시간표 데이터에서 가져온다.
enum Direction: String, CaseIterable, Codable, Identifiable {
    case up
    case down

    var id: String { rawValue }
    var fallbackTitle: String { self == .up ? "상행" : "하행" }

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
    case saturday
    case holiday

    var title: String {
        switch self {
        case .weekday: return "평일"
        case .saturday: return "토요일"
        case .holiday: return "휴일"
        }
    }

    static func of(_ date: Date, calendar: Calendar = .current) -> DayType {
        switch calendar.component(.weekday, from: date) {
        case 1: return .holiday
        case 7: return .saturday
        default: return .weekday
        }
    }
}

struct Train: Identifiable, Hashable {
    let stationCode: String
    let direction: Direction
    let dayType: DayType
    let minutesOfDay: Int      // 자정 넘는 열차는 1440 이상일 수 있다
    let type: TrainType
    let note: String?          // 중간 종착 등 (예: "성수", "신논현")

    var id: String { "\(stationCode)-\(direction.rawValue)-\(dayType.rawValue)-\(minutesOfDay)-\(type.rawValue)" }

    var timeString: String { String(format: "%02d:%02d", (minutesOfDay / 60) % 24, minutesOfDay % 60) }

    func departure(on date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .minute, value: minutesOfDay, to: start) ?? start
    }
}

struct Station: Identifiable, Hashable, Codable {
    let code: String
    let name: String
    let express: Bool
    var id: String { code }
}

struct Line: Identifiable, Codable {
    let id: String          // "01" ... "09"
    let name: String        // "1호선"
    let realtimeId: String  // 실시간 API subwayId, "1001" ...
    let color: String
    let source: String      // "bundled" | "seoulMetroAPI"
    let stations: [Station]

    var isBundled: Bool { source == "bundled" }
}

private struct LinesFile: Codable {
    let lines: [Line]
}

/// 역 하나의 시간표. 1~8호선은 API에서 받아 이 형식으로 캐시하고, 9호선은 내장 파일에서 변환한다.
struct StationTimetable: Codable {
    struct Entry: Codable {
        let direction: String
        let dayType: String
        let time: String       // "HH:mm" (24 이상 가능)
        let type: String       // "일반" | "급행"
        let note: String?
    }
    let code: String
    let source: String
    let fetchedAt: Date?
    let directionTitles: [String: String]
    let entries: [Entry]

    func trains() -> [Train] {
        entries.compactMap { e -> Train? in
            guard let d = Direction(rawValue: e.direction),
                  let dt = DayType(rawValue: e.dayType),
                  let t = TrainType(rawValue: e.type) else { return nil }
            let parts = e.time.split(separator: ":").compactMap { Int($0) }
            guard parts.count >= 2 else { return nil }
            return Train(stationCode: code, direction: d, dayType: dt,
                         minutesOfDay: parts[0] * 60 + parts[1], type: t, note: e.note)
        }
        .sorted { $0.minutesOfDay < $1.minutesOfDay }
    }
}

/// 내장 9호선 파일(timetable_09.json) 형식
private struct BundledLineFile: Codable {
    struct Entry: Codable {
        let direction: String
        let dayType: String   // "weekday" | "weekend"
        let time: String
        let type: String
        let note: String?
    }
    struct StationEntry: Codable {
        let code: String
        let name: String
        let entries: [Entry]
    }
    let source: String
    let directions: [String: String]
    let stations: [StationEntry]
}

/// 노선·역 목록과 역별 시간표를 관리한다. 시간표는 필요할 때만 불러온다.
@Observable
final class TimetableStore {
    static let shared = TimetableStore()
    static let defaultStationCode = "4107"   // 가양 (예전 설치 호환용)

    let lines: [Line]
    private(set) var loaded: [String: [Train]] = [:]
    private(set) var meta: [String: StationTimetable] = [:]
    private(set) var loading: Set<String> = []
    private(set) var errors: [String: String] = [:]

    private var bundledCache: [String: BundledLineFile] = [:]

    private init() {
        if let url = Bundle.main.url(forResource: "lines", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(LinesFile.self, from: data) {
            lines = file.lines
        } else {
            lines = []
        }
    }

    // MARK: 조회

    func line(id: String) -> Line? { lines.first { $0.id == id } }

    func line(ofStation code: String) -> Line? {
        lines.first { $0.stations.contains { $0.code == code } }
    }

    func station(code: String) -> Station? {
        for line in lines {
            if let s = line.stations.first(where: { $0.code == code }) { return s }
        }
        return nil
    }

    func stationName(_ code: String) -> String { station(code: code)?.name ?? "?" }

    func isLoaded(_ code: String) -> Bool { loaded[code] != nil }

    func trains(stationCode: String, direction: Direction, dayType: DayType) -> [Train] {
        guard let all = loaded[stationCode] else { return [] }
        let exact = all.filter { $0.direction == direction && $0.dayType == dayType }
        if !exact.isEmpty { return exact }
        // 토요일 시간표가 따로 없으면 휴일 시간표를 쓴다 (9호선 등)
        if dayType == .saturday {
            return all.filter { $0.direction == direction && $0.dayType == .holiday }
        }
        return exact
    }

    func directionTitle(stationCode: String, direction: Direction) -> String {
        meta[stationCode]?.directionTitles[direction.rawValue] ?? direction.fallbackTitle
    }

    /// 30일 지난 API 시간표는 갱신 대상
    func isStale(_ code: String) -> Bool {
        guard let line = line(ofStation: code), !line.isBundled,
              let fetched = meta[code]?.fetchedAt else { return false }
        return Date.now.timeIntervalSince(fetched) > 30 * 86400
    }

    // MARK: 불러오기

    @MainActor
    func ensureLoaded(stationCode code: String) async {
        guard !code.isEmpty, loaded[code] == nil, !loading.contains(code) else { return }
        guard let line = line(ofStation: code) else { return }
        loading.insert(code)
        defer { loading.remove(code) }

        if line.isBundled {
            if let tt = bundledTimetable(lineId: line.id, code: code) { apply(tt) }
            return
        }
        if let cached = readCache(code) {
            apply(cached)
            if isStale(code) { await fetchAndStore(code: code, line: line) }
            return
        }
        await fetchAndStore(code: code, line: line)
    }

    /// API 시간표를 강제로 다시 받는다 (1~8호선)
    @MainActor
    func refresh(stationCode code: String) async {
        guard let line = line(ofStation: code), !line.isBundled, !loading.contains(code) else { return }
        loading.insert(code)
        defer { loading.remove(code) }
        await fetchAndStore(code: code, line: line)
    }

    @MainActor
    private func fetchAndStore(code: String, line: Line) async {
        guard let key = Secrets.seoulOpenAPIKey else {
            errors[code] = "API 키가 없어 시간표를 받을 수 없습니다. 설정의 안내를 확인하세요."
            return
        }
        do {
            let tt = try await SeoulMetroAPI.fetchStation(code: code, lineId: line.id, apiKey: key)
            apply(tt)
            writeCache(tt)
            errors[code] = nil
        } catch {
            errors[code] = "시간표를 받지 못했습니다 (\(error.localizedDescription))"
        }
    }

    private func apply(_ tt: StationTimetable) {
        meta[tt.code] = tt
        loaded[tt.code] = tt.trains()
    }

    // MARK: 내장 9호선

    private func bundledTimetable(lineId: String, code: String) -> StationTimetable? {
        let file: BundledLineFile
        if let cached = bundledCache[lineId] {
            file = cached
        } else {
            guard let url = Bundle.main.url(forResource: "timetable_\(lineId)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let decoded = try? JSONDecoder().decode(BundledLineFile.self, from: data) else { return nil }
            bundledCache[lineId] = decoded
            file = decoded
        }
        guard let st = file.stations.first(where: { $0.code == code }) else { return nil }
        let entries = st.entries.map {
            StationTimetable.Entry(direction: $0.direction,
                                   dayType: $0.dayType == "weekend" ? "holiday" : $0.dayType,
                                   time: $0.time, type: $0.type, note: $0.note)
        }
        return StationTimetable(code: code, source: file.source, fetchedAt: nil,
                                directionTitles: file.directions, entries: entries)
    }

    // MARK: 캐시 파일

    private var cacheDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("timetables", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func readCache(_ code: String) -> StationTimetable? {
        let url = cacheDir.appendingPathComponent("\(code).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StationTimetable.self, from: data)
    }

    private func writeCache(_ tt: StationTimetable) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(tt) {
            try? data.write(to: cacheDir.appendingPathComponent("\(tt.code).json"), options: .atomic)
        }
    }
}
