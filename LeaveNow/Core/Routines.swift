import Foundation
import SwiftData
import UserNotifications

/// 반복 일정(루틴): "평일마다 회사 10:00까지".
/// 앱을 열 때마다 (1) 오늘 반복 일정이 있으면 이동을 만들어 홈에 띄우고
/// (2) 앞으로 7일 치 알림을 미리 걸어 둔다. 그래서 앱을 안 열어도 알림은 울린다.
@MainActor
enum Routines {
    private static var busy = false
    private static let lastScheduleKey = "v2.routineScheduledAt"

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 알림 이름표: routine.20260930.회사.lead
    private static func prefix(_ place: Place, _ date: Date) -> String { "routine.\(dayKey(date)).\(place.name)" }

    /// 앱을 열 때 부른다. 반복 설정이 그대로면 알림 다시 걸기는 한 시간에 한 번만
    static func refresh(context: ModelContext, force: Bool = false) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        await ensureToday(context: context)
        let d = UserDefaults.standard
        let last = d.object(forKey: lastScheduleKey) as? Date ?? .distantPast
        let signature = settingsSignature(context: context)
        if force || Date.now.timeIntervalSince(last) > 3600 || d.string(forKey: lastSignatureKey) != signature {
            await scheduleUpcoming(context: context)
            d.set(Date.now, forKey: lastScheduleKey)
            d.set(signature, forKey: lastSignatureKey)
        }
    }

    private static let lastSignatureKey = "v2.routineSignature"

    /// 반복 일정과 계산에 쓰는 설정을 한 줄로. 바뀌면 알림을 바로 다시 건다
    private static func settingsSignature(context: ModelContext) -> String {
        let p = Profile.shared
        let places = ((try? context.fetch(FetchDescriptor<Place>())) ?? []).filter(\.repeats)
            .map { "\($0.name)|\($0.stationName)|\($0.repeatDays)|\($0.deadlineMinutes)|\($0.walkFromStation)|\($0.skippedDay)" }
            .sorted()
        return (places + ["\(p.homeStation)|\(p.homeToPlatform)|\(p.platformBuffer)|\(p.arriveEarly)|\(p.leadMinutes)"])
            .joined(separator: ";")
    }

    /// 오늘 반복 일정이 있고 아직 이동이 없으면 계산해서 만든다. 진행 중인 다른 이동이 있으면 건드리지 않는다
    static func ensureToday(context: ModelContext) async {
        let now = Date.now
        let places = (try? context.fetch(FetchDescriptor<Place>())) ?? []
        let trips = (try? context.fetch(FetchDescriptor<PlannedTrip>())) ?? []
        if trips.contains(where: { !$0.cancelled && ($0.expectedArrival ?? $0.deadline) > now.addingTimeInterval(-10 * 60) }) { return }

        let today = dayKey(now)
        let due = places
            .filter { $0.repeats(on: now) && $0.skippedDay != today }
            .compactMap { p in p.deadline(on: now).map { (p, $0) } }
            .filter { $0.1 > now && !hasTrip(for: $0.0, on: now, in: trips) }
            .sorted { $0.1 < $1.1 }
        guard let (place, deadline) = due.first else { return }

        let profile = Profile.shared
        let origin = profile.homeOrigin
        let target = deadline.addingTimeInterval(TimeInterval(-(profile.arriveEarly + place.walkFromStation) * 60))
        guard let plan = try? await RoutePlanner.shared.planBoth(origin: origin, destination: place.stationName,
                                                                   stationArrivalTarget: target,
                                                                   bufferMinutes: profile.platformBuffer)[.fastest] else { return }
        context.insert(PlannedTrip(placeName: place.name, destinationStation: place.stationName,
                                   walkFromStation: place.walkFromStation, deadline: deadline, origin: origin, plan: plan))
        place.lastUsedAt = now
        try? context.save()
        // 오늘 몫으로 미리 걸어 둔 알림은 이동의 알림으로 바꾼다 (출발·취소가 한 곳에서 관리되게)
        let p = prefix(place, now)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(p).lead", "\(p).go"])
        TripNotifier.schedule(placeName: place.name, plan: plan, leadMinutes: profile.leadMinutes)
    }

    /// 앞으로 7일 치 반복 알림을 다시 건다. 오늘 이미 이동이 있거나 뺀 날은 건너뛴다
    static func scheduleUpcoming(context: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("routine.") }
        let places = ((try? context.fetch(FetchDescriptor<Place>())) ?? []).filter(\.repeats)
        guard !places.isEmpty else {
            center.removePendingNotificationRequests(withIdentifiers: pending)
            return
        }
        guard await TripNotifier.requestAuthorization() else { return }
        let trips = (try? context.fetch(FetchDescriptor<PlannedTrip>())) ?? []
        let profile = Profile.shared
        let cal = Calendar.current
        var fresh: [(prefix: String, place: Place, plan: TripPlan)] = []
        for offset in 0...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now)) else { continue }
            for place in places where place.repeats(on: day) {
                guard let deadline = place.deadline(on: day), deadline > .now else { continue }
                if offset == 0, place.skippedDay == dayKey(day) || hasTrip(for: place, on: day, in: trips) { continue }
                let target = deadline.addingTimeInterval(TimeInterval(-(profile.arriveEarly + place.walkFromStation) * 60))
                // 요일 종류별로 저장된 열차표를 쓰므로 같은 평일은 한 번만 실제로 조회한다
                guard let plan = try? await RoutePlanner.shared.planBoth(origin: profile.homeOrigin, destination: place.stationName,
                                                                           stationArrivalTarget: target,
                                                                           bufferMinutes: profile.platformBuffer)[.fastest] else { continue }
                fresh.append((prefix(place, day), place, plan))
            }
        }
        // 계산이 끝난 뒤에 한꺼번에 바꾼다. 계산이 실패해도 이전 알림은 남는다
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for item in fresh {
            TripNotifier.add(prefix: item.prefix, placeName: item.place.name, plan: item.plan, leadMinutes: profile.leadMinutes)
        }
    }

    /// "오늘은 안 가요": 오늘 이동과 알림을 끄고, 내일부터는 그대로
    static func skipToday(_ place: Place, context: ModelContext) {
        let now = Date.now
        place.skippedDay = dayKey(now)
        let trips = (try? context.fetch(FetchDescriptor<PlannedTrip>())) ?? []
        for trip in trips where isSame(trip, place) && Calendar.current.isDate(trip.deadline, inSameDayAs: now) && !trip.cancelled {
            trip.cancelled = true
            TripNotifier.cancelAll()
            TripActivity.endAll()
        }
        try? context.save()
        let p = prefix(place, now)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(p).lead", "\(p).go"])
    }

    /// 다음 반복 일정 (오늘 남은 것 포함)
    static func next(in places: [Place], after now: Date = .now) -> (place: Place, deadline: Date)? {
        let cal = Calendar.current
        for offset in 0...7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            let candidates = places
                .filter { $0.repeats(on: day) && !(offset == 0 && $0.skippedDay == dayKey(day)) }
                .compactMap { p in p.deadline(on: day).map { (p, $0) } }
                .filter { $0.1 > now }
                .sorted { $0.1 < $1.1 }
            if let first = candidates.first { return first }
        }
        return nil
    }

    /// 이 이동이 그 장소의 반복 일정에서 나온 것인지 (이름과 역이 같으면 같은 곳)
    static func isSame(_ trip: PlannedTrip, _ place: Place) -> Bool {
        trip.placeName == place.name && trip.destinationStation == place.stationName
    }

    private static func hasTrip(for place: Place, on day: Date, in trips: [PlannedTrip]) -> Bool {
        trips.contains { isSame($0, place) && Calendar.current.isDate($0.deadline, inSameDayAs: day) }
    }
}
