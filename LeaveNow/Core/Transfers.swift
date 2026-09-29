import Foundation

/// 환승 데이터: 역별 환승 거리·시간과 빠른 칸 (scripts/build_transfers.py)
final class TransferData {
    static let shared = TransferData()

    struct Walk: Codable { let m: Int; let s: Int }
    struct Car: Codable {
        let st: String, from: String, dir: String, alight: String
        let to: String, toDir: String, board: String
    }
    private struct File: Codable { let walk: [String: Walk]; let cars: [Car] }

    private let walks: [String: Walk]
    private let cars: [Car]

    private init() {
        if let url = Bundle.main.url(forResource: "transfers", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let file = try? JSONDecoder().decode(File.self, from: data) {
            walks = file.walk
            cars = file.cars
        } else {
            walks = [:]
            cars = []
        }
    }

    /// 노선 이름을 짧은 키로 (build_transfers.py 의 norm_line 과 같은 규칙)
    static func lineKey(_ line: String) -> String {
        let s = line.trimmingCharacters(in: .whitespaces)
        if let first = s.first, first.isNumber, s.count <= 3 { return String(first) }
        let table: [(String, String)] = [("신분당", "신분당"), ("경의", "경의중앙"), ("분당", "수인분당"), ("수인", "수인분당"),
                                         ("공항", "공항철도"), ("우이", "우이신설"), ("의정부", "의정부"), ("용인", "에버라인"),
                                         ("에버", "에버라인"), ("신림", "신림"), ("서해", "서해"), ("경춘", "경춘"),
                                         ("김포", "김포골드"), ("인천1", "인천1"), ("인천2", "인천2"), ("경강", "경강")]
        return table.first { s.contains($0.0) }?.1 ?? s
    }

    static func baseName(_ name: String) -> String {
        name.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? name
    }

    /// 환승 거리(m)와 표준 시간(초). 파일에 없으면 nil
    func walk(station: String, fromLine: String, toLine: String) -> Walk? {
        let st = Self.baseName(station), a = Self.lineKey(fromLine), b = Self.lineKey(toLine)
        return walks["\(st)|\(a)|\(b)"] ?? walks["\(st)|\(b)|\(a)"]
    }

    /// 빠른 칸: 환승역에 도착할 때 탈 칸(alight)과 갈아탈 칸(board).
    /// prevStation 은 환승역 바로 앞 역(열차가 온 쪽), nextStation 은 갈아탄 열차의 다음 역.
    func fastCar(station: String, fromLine: String, prevStation: String?, toLine: String, nextStation: String?) -> (alight: String, board: String)? {
        let st = Self.baseName(station), a = Self.lineKey(fromLine), b = Self.lineKey(toLine)
        var rows = cars.filter { $0.st == st && $0.from == a && $0.to == b }
        if let prev = prevStation.map(Self.baseName) {
            // 방면은 열차가 가는 쪽 이웃 역이라, 온 쪽(prev)과 다른 방면이 맞다
            let heading = rows.filter { $0.dir != prev }
            if !heading.isEmpty { rows = heading }
        }
        if let next = nextStation.map(Self.baseName) {
            let toward = rows.filter { $0.toDir == next }
            if !toward.isEmpty { rows = toward }
        }
        guard let r = rows.first else { return nil }
        return (r.alight, r.board)
    }
}

/// 환승 여유 계산
/// 필요한 환승 시간 = 표준 환승 시간 × 내 걸음 배율 + 기본 여유.
/// 경로 API가 알려준 대기 시간이 '더 필요해진 시간'보다 짧으면 그 연결은 못 탄다고 본다.
enum TransferModel {
    /// 이 환승에 표준 시간 외로 더 필요한 초
    static func extraNeeded(_ t: RouteTrip.Transfer, at time: Date, walkFactor: Double = Profile.shared.walkFactor) -> Int {
        let file = TransferData.shared.walk(station: t.station, fromLine: t.fromLine, toLine: t.toLine)
        let standard = max(t.walkSeconds, file?.s ?? 0)
        // API 가 이미 셈한 걷는 시간보다 파일 시간이 길면 그 차이도 더 필요하다
        let fileGap = max(0, standard - t.walkSeconds)
        let personal = Int(Double(standard) * max(0, walkFactor - 1))
        let base: Int
        if standard == 0 {
            base = 30                                   // 같은 승강장 갈아타기
        } else {
            base = max(60, standard / 4)                // 긴 환승일수록 여유를 더
        }
        return fileGap + personal + base + (isRushHour(time) ? 30 : 0)
    }

    /// 대기 시간이 필요한 여유보다 짧은 환승이 하나라도 있으면 믿기 어려운 연결
    static func isReliable(_ trip: RouteTrip) -> Bool {
        let rides = trip.rides
        for (i, t) in trip.transfers.enumerated() {
            let at = i < rides.count ? rides[i].arrival : trip.departure
            if t.waitSeconds < extraNeeded(t, at: at) { return false }
        }
        return true
    }

    /// 사람에게 보여줄 환승 시간(분): 표준 시간 × 배율 + 기본 여유
    static func displayMinutes(_ t: RouteTrip.Transfer, at time: Date) -> (walk: Int, spare: Int) {
        let file = TransferData.shared.walk(station: t.station, fromLine: t.fromLine, toLine: t.toLine)
        let standard = max(t.walkSeconds, file?.s ?? 0)
        let walk = Int((Double(standard) * max(1, Profile.shared.walkFactor) / 60).rounded(.up))
        let spare = max(0, (t.waitSeconds - (standard - t.walkSeconds)) / 60)
        return (max(walk, standard == 0 ? 0 : 1), spare)
    }

    static func isRushHour(_ date: Date) -> Bool {
        let cal = Calendar.current
        let wd = cal.component(.weekday, from: date)
        guard (2...6).contains(wd) else { return false }
        let m = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        return (7 * 60...9 * 60 + 30).contains(m) || (17 * 60 + 30...19 * 60 + 30).contains(m)
    }
}
