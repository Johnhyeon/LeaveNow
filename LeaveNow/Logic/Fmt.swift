import Foundation

enum Fmt {
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        if m == 0 { return "\(s)초" }
        if s == 0 { return "\(m)분" }
        return "\(m)분 \(s)초"
    }

    /// 스톱워치용 m:ss.s
    static func stopwatch(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = seconds - Double(m * 60)
        return String(format: "%d:%04.1f", m, s)
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let timeWithSeconds: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M월 d일 (E) HH:mm"
        return f
    }()

    static func relative(_ target: Date, from now: Date) -> String {
        let diff = target.timeIntervalSince(now)
        if diff < -30 { return "놓침" }
        if diff < 60 { return "지금 출발" }
        let minutes = Int(diff / 60)
        if minutes >= 60 { return "\(minutes / 60)시간 \(minutes % 60)분 후 출발" }
        return "\(minutes)분 후 출발"
    }
}
