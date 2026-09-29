import CoreLocation
import SwiftUI

/// 수도권 역 하나. 같은 이름의 환승역은 하나로 묶여 있다 (scripts/build_stations.py)
struct Station: Codable, Identifiable, Hashable {
    let name: String       // 화면에 보이는 이름, 예: "경복궁(정부서울청사)"
    let query: String      // 경로 API에 보내는 이름, 예: "경복궁"
    let lines: [String]
    let ids: [String]
    let lat: Double
    let lon: Double

    var id: String { name }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

final class StationDirectory {
    static let shared = StationDirectory()
    let all: [Station]
    private let byName: [String: Station]

    private init() {
        if let url = Bundle.main.url(forResource: "stations", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([Station].self, from: data) {
            all = list
        } else {
            all = []
        }
        var map: [String: Station] = [:]
        for s in all {
            map[s.name] = s
            if map[s.query] == nil { map[s.query] = s }
        }
        byName = map
    }

    func station(named name: String) -> Station? { byName[name] }

    /// 앞글자가 맞는 역을 먼저, 그다음 이름에 들어 있는 역
    func search(_ text: String, limit: Int = 30) -> [Station] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let prefix = all.filter { $0.name.hasPrefix(q) }
        let contains = all.filter { !$0.name.hasPrefix(q) && $0.name.contains(q) }
        return Array((prefix + contains).prefix(limit))
    }

    func nearest(to location: CLLocation, limit: Int = 3) -> [(station: Station, meters: CLLocationDistance)] {
        all.map { ($0, $0.location.distance(from: location)) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { (station: $0.0, meters: $0.1) }
    }
}

/// 노선 이름 → 공식 색과 짧은 표기
enum LineStyle {
    private static let table: [(key: String, hex: String, short: String)] = [
        ("신분당", "#D4003B", "신분당"),
        ("공항철도", "#0090D2", "공항"),
        ("경의중앙", "#77C4A3", "경의중앙"),
        ("수인분당", "#F5A200", "수인분당"),
        ("분당", "#F5A200", "수인분당"),
        ("수인", "#F5A200", "수인분당"),
        ("경춘", "#0C8E72", "경춘"),
        ("우이신설", "#B0CE18", "우이신설"),
        ("신림", "#6789CA", "신림"),
        ("서해", "#81A914", "서해"),
        ("김포골드", "#A17E46", "김포"),
        ("에버라인", "#56AD2D", "에버라인"),
        ("의정부", "#FDA600", "의정부"),
        ("인천1", "#7CA8D5", "인천1"),
        ("인천2", "#ED8B00", "인천2"),
        ("광역급행", "#9A6292", "GTX"),
        ("GTX", "#9A6292", "GTX"),
        ("경강", "#0054A6", "경강"),
        ("1호선", "#0052A4", "1"), ("2호선", "#00A84D", "2"), ("3호선", "#EF7C1C", "3"),
        ("4호선", "#00A5DE", "4"), ("5호선", "#996CAC", "5"), ("6호선", "#CD7C2F", "6"),
        ("7호선", "#747F00", "7"), ("8호선", "#E6186C", "8"), ("9호선", "#BDB092", "9"),
    ]

    static func color(_ line: String) -> Color {
        Color(hex: hex(line))
    }

    static func hex(_ line: String) -> String {
        table.first { line.contains($0.key) }?.hex ?? "#8A94A3"
    }

    static func short(_ line: String) -> String {
        table.first { line.contains($0.key) }?.short ?? line
    }
}
