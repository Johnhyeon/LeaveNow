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

/// 경로 API로 열차를 훑어 '마감에 맞는 가장 늦은 열차'를 찾는다.
/// 빠르게 하려고 (1) 여러 시각을 동시에 묻고 (2) 두 방식이 같은 경로면 한 번만 훑고
/// (3) 요일 종류별로 폰에 저장해 일주일 동안 다시 쓴다.
actor RoutePlanner {
    static let shared = RoutePlanner()
    private let store = RouteCache()

    // MARK: 계획

    /// 최단시간·최소환승 두 계획을 함께 만든다. 두 방식이 같은 경로면 한 번만 계산한다.
    func planBoth(origin: OriginInfo, destination: String, stationArrivalTarget: Date,
                  bufferMinutes: Int, now: Date = .now) async throws -> [RouteMode: TripPlan] {
        let from = Self.query(origin.station), to = Self.query(destination)
        async let fastProbe = probe(from: from, to: to, mode: .fastest, target: stationArrivalTarget)
        async let fewProbe = probe(from: from, to: to, mode: .fewestTransfers, target: stationArrivalTarget)
        let (a, b) = try await (fastProbe, fewProbe)

        if a.signature == b.signature {
            let trips = try await trips(from: from, to: to, mode: .fewestTransfers, target: stationArrivalTarget, probe: b)
            let plan = try await makePlan(trips: trips, from: from, to: to, mode: .fewestTransfers, origin: origin,
                                          target: stationArrivalTarget, bufferMinutes: bufferMinutes, now: now)
            let fast = TripPlan(mode: .fastest, trip: plan.trip, leaveBy: plan.leaveBy, platformBy: plan.platformBy,
                                stationArrivalTarget: plan.stationArrivalTarget, isLate: plan.isLate)
            return [.fastest: fast, .fewestTransfers: plan]
        }
        async let t1 = trips(from: from, to: to, mode: .fastest, target: stationArrivalTarget, probe: a)
        async let t2 = trips(from: from, to: to, mode: .fewestTransfers, target: stationArrivalTarget, probe: b)
        let (fastTrips, fewTrips) = try await (t1, t2)
        async let p1 = makePlan(trips: fastTrips, from: from, to: to, mode: .fastest, origin: origin,
                                target: stationArrivalTarget, bufferMinutes: bufferMinutes, now: now)
        async let p2 = makePlan(trips: fewTrips, from: from, to: to, mode: .fewestTransfers, origin: origin,
                                target: stationArrivalTarget, bufferMinutes: bufferMinutes, now: now)
        let (x, y) = try await (p1, p2)
        return [.fastest: x, .fewestTransfers: y]
    }

    /// 한 방식만 계산 (다시 계산하기 등)
    func plan(origin: OriginInfo, destination: String, stationArrivalTarget: Date,
              bufferMinutes: Int, mode: RouteMode, now: Date = .now) async throws -> TripPlan {
        let from = Self.query(origin.station), to = Self.query(destination)
        let p = try await probe(from: from, to: to, mode: mode, target: stationArrivalTarget)
        let list = try await trips(from: from, to: to, mode: mode, target: stationArrivalTarget, probe: p)
        return try await makePlan(trips: list, from: from, to: to, mode: mode, origin: origin,
                                  target: stationArrivalTarget, bufferMinutes: bufferMinutes, now: now)
    }

    private func makePlan(trips: [RouteTrip], from: String, to: String, mode: RouteMode, origin: OriginInfo,
                          target: Date, bufferMinutes: Int, now: Date) async throws -> TripPlan {
        let buffer = TimeInterval(bufferMinutes * 60)
        let toPlatform = TimeInterval(origin.toPlatformMinutes * 60)
        let readyAfter = now.addingTimeInterval(toPlatform + buffer)

        // 마감에 맞는 가장 늦은 열차
        if let best = Self.latestOnTime(trips, target: target), best.departure >= readyAfter {
            return TripPlan(mode: mode, trip: best,
                            leaveBy: best.departure.addingTimeInterval(-buffer - toPlatform),
                            platformBy: best.departure.addingTimeInterval(-buffer),
                            stationArrivalTarget: target, isLate: false)
        }
        // 이미 늦었으면: 지금 나가서 탈 수 있는 열차 중 가장 빨리 도착하는 것
        var candidates = trips.filter { $0.departure >= readyAfter }
        if candidates.count < 3 {
            let more = try await grid(from: from, to: to, mode: mode, start: readyAfter,
                                      end: readyAfter.addingTimeInterval(20 * 60))
            candidates = Self.merge(candidates, more).filter { $0.departure >= readyAfter }
        }
        // 늦었을 때도 빠듯한 연결은 피하되, 그것밖에 없으면 쓴다
        guard let fastest = candidates.filter({ !$0.isTight }).min(by: { $0.arrival < $1.arrival })
                ?? candidates.min(by: { $0.arrival < $1.arrival }) else { throw RouteError.noRoute }
        return TripPlan(mode: mode, trip: fastest,
                        leaveBy: fastest.departure.addingTimeInterval(-buffer - toPlatform),
                        platformBy: fastest.departure.addingTimeInterval(-buffer),
                        stationArrivalTarget: target, isLate: fastest.arrival > target)
    }

    // MARK: 열차 모으기

    /// 대략 걸리는 시간과 경로 모양을 알아보는 한 번의 조회. 저장된 표가 있으면 그걸 쓴다
    private func probe(from: String, to: String, mode: RouteMode, target: Date) async throws -> RouteTrip {
        if let cached = store.trips(from: from, to: to, mode: mode, target: target)?.first { return cached }
        if let p = try await RouteAPI.fetch(from: from, to: to, at: target.addingTimeInterval(-90 * 60), mode: mode) { return p }
        if let p = try await RouteAPI.fetch(from: from, to: to, at: target.addingTimeInterval(-180 * 60), mode: mode) { return p }
        throw RouteError.noRoute
    }

    /// target 도착에 맞출 만한 열차들
    private func trips(from: String, to: String, mode: RouteMode, target: Date, probe: RouteTrip) async throws -> [RouteTrip] {
        if let cached = store.trips(from: from, to: to, mode: mode, target: target) { return cached }
        let duration = probe.arrival.timeIntervalSince(probe.departure)
        let latestDeparture = target.addingTimeInterval(-duration)
        var list = try await grid(from: from, to: to, mode: mode,
                                  start: latestDeparture.addingTimeInterval(-14 * 60),
                                  end: latestDeparture.addingTimeInterval(6 * 60))
        // 마감에 맞는 열차가 하나도 없으면 더 앞쪽을 본다
        if Self.latestOnTime(list, target: target) == nil {
            let earlier = try await grid(from: from, to: to, mode: mode,
                                         start: latestDeparture.addingTimeInterval(-40 * 60),
                                         end: latestDeparture.addingTimeInterval(-14 * 60))
            list = Self.merge(list, earlier)
        }
        store.save(list, from: from, to: to, mode: mode, target: target)
        return list
    }

    /// start~end 를 90초 간격으로 나눠 동시에 조회한다
    private func grid(from: String, to: String, mode: RouteMode, start: Date, end: Date) async throws -> [RouteTrip] {
        var times: [Date] = []
        var t = start
        while t <= end { times.append(t); t = t.addingTimeInterval(90) }
        let found = try await withThrowingTaskGroup(of: RouteTrip?.self) { group in
            for time in times {
                group.addTask { try await RouteAPI.fetch(from: from, to: to, at: time, mode: mode) }
            }
            var all: [RouteTrip] = []
            for try await trip in group { if let trip { all.append(trip) } }
            return all
        }
        return Self.merge([], found)
    }

    private static func merge(_ a: [RouteTrip], _ b: [RouteTrip]) -> [RouteTrip] {
        var seen = Set<String>()
        return (a + b).filter { seen.insert($0.id).inserted }.sorted { $0.departure < $1.departure }
    }

    private static func query(_ station: String) -> String {
        StationDirectory.shared.station(named: station)?.query ?? station
    }

    /// 마감 안에 도착하는 열차 중 가장 늦게 떠나는 것.
    /// 먼저 오는 일반보다 뒤에 오는 급행이 빨리 도착할 수 있어, 출발 순서가 아니라 도착 시각으로 판단한다.
    /// 환승 여유가 모자란 '빠듯한' 연결은 조금만 늦어도 놓치므로 고르지 않는다. 그런 것밖에 없을 때만 쓴다.
    static func latestOnTime(_ trips: [RouteTrip], target: Date) -> RouteTrip? {
        let onTime = trips.filter { $0.arrival <= target }
        return onTime.filter { !$0.isTight }.max { $0.departure < $1.departure }
            ?? onTime.max { $0.departure < $1.departure }
    }
}

/// 요일 종류(평일·토요일·휴일)별로 열차 표를 폰에 저장한다. 같은 요일 종류면 날짜만 바꿔 일주일 동안 다시 쓴다.
final class RouteCache: @unchecked Sendable {
    private struct Entry: Codable {
        let savedAt: Date
        let trips: [RouteTrip]
        let dayStart: Date
    }
    private var entries: [String: Entry] = [:]
    private let url: URL
    private let lock = NSLock()
    private static let validFor: TimeInterval = 7 * 86400

    init() {
        url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("routes.json")
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved.filter { Date.now.timeIntervalSince($0.value.savedAt) < Self.validFor }
        }
    }

    private static func key(from: String, to: String, mode: RouteMode, target: Date) -> String {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: target)
        let kind = weekday == 1 ? "holiday" : (weekday == 7 ? "saturday" : "weekday")
        let minutes = cal.component(.hour, from: target) * 60 + cal.component(.minute, from: target)
        return "\(from)|\(to)|\(mode.rawValue)|\(kind)|\(minutes / 10)"
    }

    func trips(from: String, to: String, mode: RouteMode, target: Date) -> [RouteTrip]? {
        lock.lock(); defer { lock.unlock() }
        guard let e = entries[Self.key(from: from, to: to, mode: mode, target: target)],
              Date.now.timeIntervalSince(e.savedAt) < Self.validFor else { return nil }
        let shift = Calendar.current.startOfDay(for: target).timeIntervalSince(e.dayStart)
        return e.trips.map { $0.shifted(by: shift) }
    }

    func save(_ trips: [RouteTrip], from: String, to: String, mode: RouteMode, target: Date) {
        guard !trips.isEmpty else { return }
        lock.lock()
        entries[Self.key(from: from, to: to, mode: mode, target: target)] =
            Entry(savedAt: .now, trips: trips, dayStart: Calendar.current.startOfDay(for: target))
        let snapshot = entries
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }
}

extension RouteTrip {
    /// 환승 여유가 모자란 연결이 있으면 빠듯하다 (TransferModel)
    var isTight: Bool { !TransferModel.isReliable(self) }

    /// 모든 시각을 shift 초만큼 옮긴 같은 여정
    func shifted(by shift: TimeInterval) -> RouteTrip {
        guard shift != 0 else { return self }
        return RouteTrip(legs: legs.map { leg in
            switch leg {
            case .ride(let r):
                return .ride(.init(line: r.line, from: r.from, to: r.to,
                                   departure: r.departure.addingTimeInterval(shift),
                                   arrival: r.arrival.addingTimeInterval(shift),
                                   express: r.express, stops: r.stops, towards: r.towards, trainNo: r.trainNo,
                                   secondStation: r.secondStation, penultimateStation: r.penultimateStation))
            case .transfer:
                return leg
            }
        })
    }
}
