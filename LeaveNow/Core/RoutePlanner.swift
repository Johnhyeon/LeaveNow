import Foundation

/// 출발지에서 승강장까지의 정보
struct OriginInfo: Codable, Hashable {
    var label: String          // "집", "회사", "지금 여기"
    var station: String        // 역 표시 이름
    var toPlatformMinutes: Int // 문을 나서서 승강장까지
}

/// 한 번의 이동 계획
struct TripPlan: Codable, Hashable {
    let mode: RouteMode
    let trip: RouteTrip
    let leaveBy: Date            // 현관(출발지)을 나설 시각
    let platformBy: Date         // 승강장 도착 목표
    let stationArrivalTarget: Date
    let isLate: Bool
}

/// 경로 API로 열차를 훑어 '마감에 맞는 가장 늦은 열차'를 찾는다. (0단계 scripts/spike_arrive_by.py 와 같은 방식)
actor RoutePlanner {
    static let shared = RoutePlanner()
    private var cache: [String: (trips: [RouteTrip], at: Date)] = [:]

    /// target 도착에 맞출 만한 시간대의 열차들
    func trips(from: String, to: String, mode: RouteMode, arrivingAround target: Date) async throws -> [RouteTrip] {
        let key = "\(from)|\(to)|\(mode.rawValue)|\(Int(target.timeIntervalSince1970 / 600))"
        if let hit = cache[key], Date.now.timeIntervalSince(hit.at) < 6 * 3600 { return hit.trips }

        // 1) 대략 걸리는 시간을 한 번 알아본다
        var probe = try await RouteAPI.fetch(from: from, to: to, at: target.addingTimeInterval(-90 * 60), mode: mode)
        if probe == nil {
            probe = try await RouteAPI.fetch(from: from, to: to, at: target.addingTimeInterval(-180 * 60), mode: mode)
        }
        guard let probe else { throw RouteError.noRoute }
        let duration = probe.arrival.timeIntervalSince(probe.departure)
        let latestDeparture = target.addingTimeInterval(-duration)

        // 2) 그 앞뒤로 열차를 하나씩 훑는다
        let trips = try await scan(from: from, to: to, mode: mode,
                                   start: latestDeparture.addingTimeInterval(-35 * 60),
                                   end: latestDeparture.addingTimeInterval(8 * 60))
        cache[key] = (trips, .now)
        return trips
    }

    /// start 이후 출발 열차를 end 까지 차례로 조회
    func scan(from: String, to: String, mode: RouteMode, start: Date, end: Date, maxCalls: Int = 18) async throws -> [RouteTrip] {
        var result: [RouteTrip] = []
        var t = start
        var calls = 0
        while t <= end, calls < maxCalls {
            calls += 1
            guard let trip = try await RouteAPI.fetch(from: from, to: to, at: t, mode: mode) else { break }
            if !result.contains(where: { $0.id == trip.id }) { result.append(trip) }
            t = max(trip.departure, t).addingTimeInterval(1)
        }
        return result.sorted { $0.departure < $1.departure }
    }

    /// 계획 세우기. readyAfter 는 지금 나가면 승강장에 닿는 시각
    func plan(origin: OriginInfo, destination: String, stationArrivalTarget: Date,
              bufferMinutes: Int, mode: RouteMode, now: Date = .now) async throws -> TripPlan {
        let fromQuery = StationDirectory.shared.station(named: origin.station)?.query ?? origin.station
        let toQuery = StationDirectory.shared.station(named: destination)?.query ?? destination
        let buffer = TimeInterval(bufferMinutes * 60)
        let toPlatform = TimeInterval(origin.toPlatformMinutes * 60)
        let readyAfter = now.addingTimeInterval(toPlatform + buffer)

        var trips = try await trips(from: fromQuery, to: toQuery, mode: mode, arrivingAround: stationArrivalTarget)

        // 마감에 맞는 가장 늦은 열차
        if let best = Self.latestOnTime(trips, target: stationArrivalTarget), best.departure >= readyAfter {
            return TripPlan(mode: mode, trip: best,
                            leaveBy: best.departure.addingTimeInterval(-buffer - toPlatform),
                            platformBy: best.departure.addingTimeInterval(-buffer),
                            stationArrivalTarget: stationArrivalTarget, isLate: false)
        }

        // 이미 늦었으면: 지금 나가서 탈 수 있는 열차 중 가장 빨리 도착하는 것
        var candidates = trips.filter { $0.departure >= readyAfter }
        if candidates.count < 3 {
            let more = try await scan(from: fromQuery, to: toQuery, mode: mode,
                                      start: readyAfter, end: readyAfter.addingTimeInterval(30 * 60), maxCalls: 6)
            trips = (trips + more).sorted { $0.departure < $1.departure }
            candidates = trips.filter { $0.departure >= readyAfter }
        }
        guard let fastest = candidates.min(by: { $0.arrival < $1.arrival }) else { throw RouteError.noRoute }
        return TripPlan(mode: mode, trip: fastest,
                        leaveBy: fastest.departure.addingTimeInterval(-buffer - toPlatform),
                        platformBy: fastest.departure.addingTimeInterval(-buffer),
                        stationArrivalTarget: stationArrivalTarget,
                        isLate: fastest.arrival > stationArrivalTarget)
    }

    /// 승강장에 늦게 나타날수록 좋지만, 그 뒤로 탈 수 있는 열차 중 가장 빨리 도착하는 게 마감 안이어야 한다.
    /// 먼저 오는 일반보다 뒤에 오는 급행이 빠를 수 있어서 '뒤쪽 최소 도착'으로 판단한다.
    static func latestOnTime(_ trips: [RouteTrip], target: Date) -> RouteTrip? {
        let sorted = trips.sorted { $0.departure < $1.departure }
        var best: RouteTrip?
        var suffixMin = Date.distantFuture
        for trip in sorted.reversed() {
            suffixMin = min(suffixMin, trip.arrival)
            if suffixMin <= target && best == nil && trip.arrival <= target {
                best = trip
            }
        }
        return best
    }
}
