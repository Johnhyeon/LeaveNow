import Foundation
import Observation

/// 서울시 지하철 실시간 도착정보 한 건
struct RealtimeArrival: Identifiable {
    let id: String
    let direction: Direction?
    let type: TrainType
    let destination: String      // 행선지 (예: 중앙보훈병원)
    let nextStation: String      // "OO방면"
    let secondsUntil: Int        // 이 역 도착까지 남은 초 (barvlDt)
    let message: String          // arvlMsg2 (예: "3분 후 (마곡나루)")
    let receivedAt: Date         // recptnDt

    /// 이 역 도착 예상 시각
    var expectedArrival: Date { receivedAt.addingTimeInterval(Double(secondsUntil)) }
}

/// 서울 열린데이터광장 실시간 도착정보 API 호출
@Observable
final class RealtimeService {
    static let shared = RealtimeService()

    private(set) var arrivals: [RealtimeArrival] = []
    private(set) var lastUpdated: Date?
    private(set) var errorText: String?
    private(set) var isLoading = false

    var isConfigured: Bool { Secrets.seoulOpenAPIKey != nil }

    private static let line9Id = "1009"
    private let receivedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.timeZone = TimeZone(identifier: "Asia/Seoul")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private init() {}

    @MainActor
    func refresh(stationName: String) async {
        guard let key = Secrets.seoulOpenAPIKey else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let encoded = stationName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? stationName
        guard let url = URL(string: "http://swopenapi.seoul.go.kr/api/subway/\(key)/json/realtimeStationArrival/0/30/\(encoded)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            if let err = decoded.errorMessage, err.status != 200 {
                errorText = err.message
                return
            }
            if decoded.realtimeArrivalList == nil, let msg = decoded.message {
                errorText = msg
                return
            }
            let now = Date.now
            arrivals = (decoded.realtimeArrivalList ?? [])
                .filter { $0.subwayId == Self.line9Id }
                .map { row in
                    let (destination, next) = Self.parseLineName(row.trainLineNm ?? "")
                    return RealtimeArrival(
                        id: "\(row.btrainNo ?? "")-\(row.statnId ?? "")-\(row.updnLine ?? "")",
                        direction: Self.direction(currentStation: stationName, nextStation: next, destination: destination, updnLine: row.updnLine),
                        type: (row.btrainSttus ?? "").contains("급행") ? .express : .local,
                        destination: destination,
                        nextStation: next,
                        secondsUntil: Int(row.barvlDt ?? "0") ?? 0,
                        message: row.arvlMsg2 ?? "",
                        receivedAt: row.recptnDt.flatMap { receivedFormatter.date(from: $0) } ?? now)
                }
                .sorted { $0.secondsUntil < $1.secondsUntil }
            lastUpdated = now
            errorText = nil
        } catch {
            errorText = "실시간 정보를 불러오지 못했습니다 (\(error.localizedDescription))"
        }
    }

    /// "중앙보훈병원행 - 증미방면 (급행)" → ("중앙보훈병원", "증미")
    static func parseLineName(_ text: String) -> (destination: String, next: String) {
        // 괄호 안 부가 정보("(급행)" 등) 제거
        let cleaned = text.replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression)
        let parts = cleaned.components(separatedBy: " - ")
        let dest = parts.first.map { $0.hasSuffix("행") ? String($0.dropLast()) : $0 }?.trimmingCharacters(in: .whitespaces) ?? ""
        let next = parts.count > 1
            ? parts[1].replacingOccurrences(of: "방면", with: "").trimmingCharacters(in: .whitespaces)
            : ""
        return (dest, next)
    }

    /// 방향 판별. API의 상행/하행 값을 우선 쓰고(9호선: 상행 = 중앙보훈병원 방면),
    /// 없으면 시간표의 역 순서(개화 → 중앙보훈병원)에서 다음 역 위치로 판단한다.
    static func direction(currentStation: String, nextStation: String, destination: String, updnLine: String? = nil) -> Direction? {
        if let updn = updnLine {
            if updn.contains("상행") { return .up }
            if updn.contains("하행") { return .down }
        }
        let names = Timetable.shared.stations.map(\.name)
        guard let cur = names.firstIndex(of: currentStation) else { return nil }
        if let next = names.firstIndex(of: nextStation) {
            return next > cur ? .up : .down
        }
        if let dest = names.firstIndex(of: destination) {
            return dest > cur ? .up : .down
        }
        return nil
    }

    // MARK: 응답 형식

    private struct Response: Decodable {
        struct ErrorMessage: Decodable {
            let status: Int
            let code: String
            let message: String
        }
        struct Row: Decodable {
            let subwayId: String?
            let updnLine: String?
            let trainLineNm: String?
            let statnId: String?
            let btrainSttus: String?
            let barvlDt: String?
            let btrainNo: String?
            let bstatnNm: String?
            let recptnDt: String?
            let arvlMsg2: String?
            let arvlCd: String?
        }
        let errorMessage: ErrorMessage?
        let realtimeArrivalList: [Row]?
        // 오류일 때는 최상위에 status/code/message 가 온다
        let status: Int?
        let code: String?
        let message: String?
    }
}

/// 실시간 도착 정보를 시간표 열차에 대응시켜 지연(초)을 구한다
enum RealtimeMatcher {
    /// 같은 방향·같은 종류의 시간표 열차 중 예상 도착 시각과 가장 가까운(±6분) 것에 매칭
    static func delays(options: [TrainOption], arrivals: [RealtimeArrival], direction: Direction) -> [String: TimeInterval] {
        var result: [String: TimeInterval] = [:]
        var used: Set<String> = []
        for arrival in arrivals where arrival.direction == direction {
            let candidates = options.filter { $0.train.type == arrival.type && !used.contains($0.id) }
            guard let best = candidates.min(by: {
                abs($0.departure.timeIntervalSince(arrival.expectedArrival)) < abs($1.departure.timeIntervalSince(arrival.expectedArrival))
            }) else { continue }
            let delay = arrival.expectedArrival.timeIntervalSince(best.departure)
            guard abs(delay) <= 6 * 60 else { continue }
            used.insert(best.id)
            result[best.id] = delay
        }
        return result
    }
}
