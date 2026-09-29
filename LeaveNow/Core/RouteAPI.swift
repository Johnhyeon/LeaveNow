import Foundation

enum RouteMode: String, Codable, CaseIterable, Identifiable {
    case fastest = "duration"          // 최단시간
    case fewestTransfers = "transfer"  // 최소환승
    var id: String { rawValue }
    var title: String { self == .fastest ? "최단시간" : "최소환승" }
}

/// 경로 API가 돌려준 한 번의 여정 (특정 열차들)
struct RouteTrip: Codable, Hashable, Identifiable {
    struct Ride: Codable, Hashable {
        let line: String
        let from: String
        let to: String
        let departure: Date
        let arrival: Date
        let express: Bool
        let stops: Int
        let towards: String?
        let trainNo: String?
    }
    struct Transfer: Codable, Hashable {
        let station: String
        let fromLine: String
        let toLine: String
        let walkSeconds: Int
        let waitSeconds: Int
    }
    enum Leg: Codable, Hashable {
        case ride(Ride)
        case transfer(Transfer)
    }

    let legs: [Leg]

    var rides: [Ride] { legs.compactMap { if case .ride(let r) = $0 { return r } else { return nil } } }
    var transfers: [Transfer] { legs.compactMap { if case .transfer(let t) = $0 { return t } else { return nil } } }
    var departure: Date { rides.first?.departure ?? .distantPast }
    var arrival: Date { rides.last?.arrival ?? .distantPast }
    /// 같은 노선을 같은 역에서 갈아타는 여정이면 같은 값 (급행·일반 차이는 무시)
    var signature: String { rides.map { "\($0.line):\($0.from)>\($0.to)" }.joined(separator: "|") }
    var id: String { "\(Int(departure.timeIntervalSince1970))|\(signature)" }
    var transferCount: Int { max(0, rides.count - 1) }
}

enum RouteError: LocalizedError {
    case noKey
    case stationNotFound
    case server(String)
    case noRoute

    var errorDescription: String? {
        switch self {
        case .noKey: return "API 키가 없습니다. Secrets.plist를 확인해 주세요."
        case .stationNotFound: return "역 이름을 경로 검색에서 찾지 못했습니다."
        case .server(let m): return "경로 검색 오류: \(m)"
        case .noRoute: return "이 시간대에 가는 열차가 없습니다."
        }
    }
}

/// 서울 열린데이터광장 '서울교통공사 지하철역 최단경로이동정보' (getShtrmPath)
enum RouteAPI {
    private static let searchFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    private static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    /// at 이후 출발하는 여정 하나. 운행이 끝나 경로가 없으면 nil
    static func fetch(from: String, to: String, at: Date, mode: RouteMode) async throws -> RouteTrip? {
        guard let key = Secrets.seoulOpenAPIKey else { throw RouteError.noKey }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        let parts = [key, "json", "getShtrmPath", "1", "80", from, to, searchFormatter.string(from: at), mode.rawValue]
        let path = parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
        guard let url = URL(string: "http://openapi.seoul.go.kr:8088/" + path) else { throw RouteError.server("주소 오류") }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RouteError.server("응답 형식")
        }
        if let header = root["header"] as? [String: Any], let code = header["resultCode"] as? String, code != "00" {
            if code == "10" { throw RouteError.stationNotFound }
            throw RouteError.server(header["resultMsg"] as? String ?? code)
        }
        if let result = root["RESULT"] as? [String: Any], let code = result["CODE"] as? String, code != "INFO-000" {
            if code == "INFO-200" { return nil }
            throw RouteError.server(result["MESSAGE"] as? String ?? code)
        }
        guard let body = root["body"] as? [String: Any],
              let paths = body["paths"] as? [[String: Any]], !paths.isEmpty else { return nil }
        let total = (body["totalReqHr"] as? Int) ?? (body["totalreqHr"] as? Int) ?? 0
        if total == 0 { return nil }
        return parse(paths: paths, searchedAt: at)
    }

    private static func parse(paths: [[String: Any]], searchedAt: Date) -> RouteTrip? {
        func stn(_ p: [String: Any], _ key: String) -> [String: Any] { p[key] as? [String: Any] ?? [:] }
        func time(_ s: String?) -> Date? {
            guard let s, s.count >= 5 else { return nil }
            let comps = s.split(separator: ":").compactMap { Int($0) }
            guard comps.count >= 2 else { return nil }
            let day = calendar.startOfDay(for: searchedAt)
            var d = day.addingTimeInterval(TimeInterval(comps[0] * 3600 + comps[1] * 60 + (comps.count > 2 ? comps[2] : 0)))
            if d < searchedAt.addingTimeInterval(-6 * 3600) { d = d.addingTimeInterval(86400) }
            return d
        }

        var legs: [RouteTrip.Leg] = []
        var group: [[String: Any]] = []

        func flush() {
            guard let first = group.first, let last = group.last else { return }
            let dep = time(first["trainDptreTm"] as? String) ?? searchedAt
            let seconds = group.reduce(0) { $0 + (($1["reqHr"] as? Int) ?? 0) }
            let arr = time(last["trainArvlTm"] as? String) ?? dep.addingTimeInterval(TimeInterval(seconds))
            let nonstop = group.filter { ($0["nonstopYn"] as? String) == "Y" }.count
            legs.append(.ride(.init(
                line: stn(first, "dptreStn")["lineNm"] as? String ?? "",
                from: stn(first, "dptreStn")["stnNm"] as? String ?? "",
                to: stn(last, "arvlStn")["stnNm"] as? String ?? "",
                departure: dep,
                arrival: max(arr, dep),
                express: (first["etrnYn"] as? String) == "Y",
                stops: max(1, group.count - nonstop),
                towards: first["tmnlStnNm"] as? String,
                trainNo: first["trainno"] as? String)))
            group = []
        }

        for p in paths {
            if (p["trsitYn"] as? String) == "Y" {
                flush()
                legs.append(.transfer(.init(
                    station: stn(p, "dptreStn")["stnNm"] as? String ?? "",
                    fromLine: stn(p, "dptreStn")["lineNm"] as? String ?? "",
                    toLine: stn(p, "arvlStn")["lineNm"] as? String ?? "",
                    walkSeconds: (p["reqHr"] as? Int) ?? 0,
                    waitSeconds: (p["wtngHr"] as? Int) ?? 0)))
                continue
            }
            let train = (p["trainno"] as? String) ?? (stn(p, "dptreStn")["lineNm"] as? String ?? "")
            if let prev = group.last {
                let prevTrain = (prev["trainno"] as? String) ?? (stn(prev, "dptreStn")["lineNm"] as? String ?? "")
                if prevTrain != train { flush() }
            }
            group.append(p)
        }
        flush()
        let trip = RouteTrip(legs: legs)
        return trip.rides.isEmpty ? nil : trip
    }
}
