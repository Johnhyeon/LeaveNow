import Foundation

/// 서울 열린데이터광장 "서울교통공사 역코드로 지하철 열차 시간표 검색" API
enum SeoulMetroAPI {
    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private struct Row: Decodable {
        let ARRIVETIME: String?
        let LEFTTIME: String?
        let DESTSTATION: String?
        let SUBWAYENAME: String?
        let EXPRESS_YN: String?
    }
    private struct Service: Decodable {
        struct Result: Decodable { let CODE: String; let MESSAGE: String }
        let RESULT: Result?
        let row: [Row]?
    }
    private struct Response: Decodable {
        let SearchSTNTimeTableByIDService: Service?
        let RESULT: Service.Result?
    }

    private static let dayTags: [(tag: String, dayType: DayType)] = [("1", .weekday), ("2", .saturday), ("3", .holiday)]
    private static let dirTags: [(tag: String, direction: Direction)] = [("1", .up), ("2", .down)]

    /// 역 하나의 시간표를 요일 3종 × 방향 2종 = 6번 요청으로 받아 하나로 합친다
    static func fetchStation(code: String, lineId: String, apiKey: String) async throws -> StationTimetable {
        var entries: [StationTimetable.Entry] = []
        var destCount: [Direction: [String: Int]] = [.up: [:], .down: [:]]

        for day in dayTags {
            for dir in dirTags {
                let rows = try await fetchRows(code: code, dayTag: day.tag, dirTag: dir.tag, apiKey: apiKey)
                for row in rows {
                    // 이 역에서 종착하는 열차(출발 시각 없음)는 탈 수 없으니 제외
                    guard let left = row.LEFTTIME, left != "00:00:00", row.DESTSTATION != code else { continue }
                    let hhmm = String(left.prefix(5))
                    let dest = row.SUBWAYENAME ?? ""
                    destCount[dir.direction, default: [:]][dest, default: 0] += 1
                    entries.append(.init(direction: dir.direction.rawValue,
                                         dayType: day.dayType.rawValue,
                                         time: hhmm,
                                         type: row.EXPRESS_YN == "D" ? TrainType.express.rawValue : TrainType.local.rawValue,
                                         note: dest))
                }
            }
        }
        guard !entries.isEmpty else {
            throw APIError(message: "이 역의 시간표 데이터가 없습니다")
        }

        // 방향 이름: 가장 흔한 종착역 기준. 2호선은 순환선이라 내선/외선으로 표기
        var titles: [String: String] = [:]
        var mainDest: [Direction: String] = [:]
        for dir in Direction.allCases {
            let top = destCount[dir]?.max { $0.value < $1.value }?.key ?? ""
            mainDest[dir] = top
            if lineId == "02" {
                titles[dir.rawValue] = dir == .up ? "내선순환" : "외선순환"
            } else {
                titles[dir.rawValue] = top.isEmpty ? dir.fallbackTitle : "\(top) 방면"
            }
        }
        // 주 종착역과 같은 열차는 note 를 비우고, 다른 곳에서 끊기는 열차만 표시
        let cleaned = entries.map { e -> StationTimetable.Entry in
            let dir = Direction(rawValue: e.direction) ?? .up
            let note = (e.note == mainDest[dir] || (e.note ?? "").isEmpty) ? nil : e.note
            return .init(direction: e.direction, dayType: e.dayType, time: e.time, type: e.type, note: note)
        }
        return StationTimetable(code: code, source: "서울교통공사 (서울 열린데이터광장)", fetchedAt: .now,
                                directionTitles: titles, entries: cleaned)
    }

    private static func fetchRows(code: String, dayTag: String, dirTag: String, apiKey: String) async throws -> [Row] {
        let urlString = "http://openapi.seoul.go.kr:8088/\(apiKey)/json/SearchSTNTimeTableByIDService/1/1000/\(code)/\(dayTag)/\(dirTag)/"
        guard let url = URL(string: urlString) else { throw APIError(message: "잘못된 주소") }
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        if let svc = decoded.SearchSTNTimeTableByIDService {
            return svc.row ?? []
        }
        if let result = decoded.RESULT {
            if result.CODE == "INFO-200" { return [] }   // 데이터 없음
            throw APIError(message: "\(result.CODE) \(result.MESSAGE)")
        }
        throw APIError(message: "알 수 없는 응답")
    }
}
