import SwiftUI

/// 계획을 노선도 칸들로 바꾼다
enum RouteStops {
    static func make(plan: TripPlan, origin: OriginInfo, placeName: String, walkFromStation: Int,
                     arriveEarly: Int, deadline: Date, now: Date = .now, includeNow: Bool = true) -> [RouteStop] {
        var stops: [RouteStop] = []
        let rides = plan.trip.rides
        guard let first = rides.first, let last = rides.last else { return [] }
        func t(_ d: Date) -> String { Fmt.time.string(from: d) }
        func mins(_ a: Date, _ b: Date) -> Double { max(1, b.timeIntervalSince(a) / 60) }

        if includeNow && now < plan.leaveBy {
            stops.append(.init(time: "지금", title: "지금", isNow: true, leg: .walk, minutes: mins(now, plan.leaveBy)))
        }
        let buffer = Int((first.departure.timeIntervalSince(plan.platformBy) / 60).rounded())
        stops.append(.init(time: t(plan.leaveBy), title: origin.label == "지금 여기" ? "출발" : origin.label,
                           detail: "\(origin.label) → 승강장 \(origin.toPlatformMinutes)분 · 여유 \(buffer)분",
                           leg: .walk, minutes: mins(plan.leaveBy, first.departure)))

        for (i, ride) in rides.enumerated() {
            let color = LineStyle.color(ride.line)
            stops.append(.init(time: t(ride.departure), title: ride.from,
                               detail: "\(ride.line)\(ride.express ? " 급행" : "") · \(ride.stops)정거장",
                               nodeColor: color, leg: .line(color), minutes: mins(ride.departure, ride.arrival)))
            if i + 1 < rides.count {
                let next = rides[i + 1]
                let walk = plan.trip.transfers.first { $0.station == ride.to }?.walkSeconds ?? 0
                stops.append(.init(time: t(ride.arrival), title: ride.to,
                                   detail: "환승 · 걸어서 \(max(1, walk / 60))분",
                                   nodeColor: color, leg: .walk, minutes: mins(ride.arrival, next.departure)))
            }
        }
        let arrive = last.arrival.addingTimeInterval(TimeInterval(walkFromStation * 60))
        let early = Int(deadline.timeIntervalSince(arrive) / 60)
        if walkFromStation > 0 {
            stops.append(.init(time: t(last.arrival), title: last.to, nodeColor: LineStyle.color(last.line),
                               leg: .walk, minutes: Double(walkFromStation)))
            stops.append(.init(time: t(arrive), title: placeName,
                               detail: early >= 0 ? "\(early)분 일찍" : "\(-early)분 늦음"))
        } else {
            stops.append(.init(time: t(last.arrival), title: last.to == placeName ? last.to : "\(last.to) · \(placeName)",
                               detail: early >= 0 ? "\(early)분 일찍" : "\(-early)분 늦음",
                               nodeColor: LineStyle.color(last.line)))
        }
        return stops
    }
}
