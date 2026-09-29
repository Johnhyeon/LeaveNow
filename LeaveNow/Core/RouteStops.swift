import SwiftUI

/// 계획을 노선도 칸들로 바꾼다
enum RouteStops {
    /// 첫 환승을 위한 빠른 칸: (탈 역, 칸, 환승역)
    static func fastCar(_ plan: TripPlan) -> (station: String, car: String, transfer: String)? {
        let rides = plan.trip.rides
        guard rides.count >= 2 else { return nil }
        let a = rides[0], b = rides[1]
        guard let car = TransferData.shared.fastCar(station: a.to, fromLine: a.line, prevStation: a.penultimateStation,
                                                    toLine: b.line, nextStation: b.secondStation) else { return nil }
        return (a.from, car.alight, a.to)
    }

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
            var detail = "\(ride.line)\(ride.express ? " 급행" : "") · \(ride.stops)정거장"
            var nextRide: RouteTrip.Ride? = nil
            if i + 1 < rides.count {
                let next = rides[i + 1]
                nextRide = next
                if let car = TransferData.shared.fastCar(station: ride.to, fromLine: ride.line, prevStation: ride.penultimateStation,
                                                          toLine: next.line, nextStation: next.secondStation) {
                    detail += " · \(car.alight)칸 타면 환승 가까워요"
                }
            }
            stops.append(.init(time: t(ride.departure), title: ride.from, detail: detail,
                               nodeColor: color, leg: .line(color), minutes: mins(ride.departure, ride.arrival)))
            if let next = nextRide {
                let transfer = plan.trip.transfers.first { TransferData.baseName($0.station) == TransferData.baseName(ride.to) }
                var text = "환승"
                if let transfer {
                    let shown = TransferModel.displayMinutes(transfer, at: ride.arrival)
                    text += shown.walk == 0 ? " · 같은 승강장" : " · 걸어서 \(shown.walk)분"
                    text += " · 여유 \(shown.spare)분"
                }
                stops.append(.init(time: t(ride.arrival), title: ride.to, detail: text,
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
