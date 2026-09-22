import Foundation
import Observation
import UserNotifications

/// 로컬 알림 예약·취소. 시스템의 '대기 중 알림'이 유일한 진실이고, 화면은 refresh()로 그걸 읽는다.
@Observable
final class NotificationManager {
    static let shared = NotificationManager()

    /// 한 번짜리 알림이 걸린 열차 id 집합 (홈 화면 종 아이콘 표시용)
    var armedTrainIds: Set<String> = []
    /// 평일 출근 알림이 실제로 예약되어 있는지
    var routineScheduled = false
    var authorizationDenied = false

    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: 권한

    @discardableResult
    func requestAuthorization() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorizationDenied = false
            return true
        case .denied:
            authorizationDenied = true
            return false
        case .notDetermined:
            fallthrough
        @unknown default:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorizationDenied = !granted
            return granted
        }
    }

    // MARK: 상태 읽기

    func refresh() async {
        let ids = await center.pendingNotificationRequests().map(\.identifier)
        armedTrainIds = Set(ids.compactMap { id -> String? in
            let parts = id.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "train" else { return nil }
            return String(parts[1])
        })
        routineScheduled = ids.contains { $0.hasPrefix("routine|") }
    }

    // MARK: 한 번짜리 열차 알림

    func toggleTrainAlarm(_ option: TrainOption, leadMinutes: Int) async {
        if armedTrainIds.contains(option.id) {
            cancelTrainAlarm(option.id)
        } else {
            guard await requestAuthorization() else { return }
            scheduleTrainAlarm(option, leadMinutes: leadMinutes)
        }
        await refresh()
    }

    private func scheduleTrainAlarm(_ option: TrainOption, leadMinutes: Int) {
        let train = Fmt.time.string(from: option.departure)
        let leave = Fmt.time.string(from: option.leaveBy)
        let type = option.train.type.rawValue
        let leadDate = option.leaveBy.addingTimeInterval(-Double(leadMinutes * 60))

        if leadDate > .now {
            schedule(id: "train|\(option.id)|lead",
                     title: "출발 \(leadMinutes)분 전",
                     body: "\(train) \(type) 열차를 타려면 \(leave)에 나가세요.",
                     trigger: oneShot(at: leadDate))
        }
        schedule(id: "train|\(option.id)|go",
                 title: "지금 출발!",
                 body: "\(train) \(type) 열차 · 승강장 \(Fmt.time.string(from: option.platformArrival)) 도착 목표",
                 trigger: oneShot(at: option.leaveBy))
    }

    func cancelTrainAlarm(_ trainId: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["train|\(trainId)|lead", "train|\(trainId)|go"])
    }

    // MARK: 평일 출근 알림 (월~금 반복)

    func scheduleRoutine(train: Train, leaveByMinutes: Int, platformMinutes: Int, leadMinutes: Int) async {
        guard await requestAuthorization() else { return }
        cancelRoutine()
        let leadMinutesOfDay = leaveByMinutes - leadMinutes
        let type = train.type.rawValue
        for weekday in 2...6 {   // 월(2) ~ 금(6)
            if leadMinutesOfDay >= 0 {
                schedule(id: "routine|\(weekday)|lead",
                         title: "출발 \(leadMinutes)분 전",
                         body: "\(train.timeString) \(type) 열차를 타려면 \(Self.hhmm(leaveByMinutes))에 나가세요.",
                         trigger: weekly(weekday: weekday, minutesOfDay: leadMinutesOfDay))
            }
            schedule(id: "routine|\(weekday)|go",
                     title: "지금 출발!",
                     body: "\(train.timeString) \(type) 열차 · 승강장 \(Self.hhmm(platformMinutes)) 도착 목표",
                     trigger: weekly(weekday: weekday, minutesOfDay: leaveByMinutes))
        }
        await refresh()
    }

    func cancelRoutine() {
        var ids: [String] = []
        for weekday in 2...6 {
            ids.append("routine|\(weekday)|lead")
            ids.append("routine|\(weekday)|go")
        }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        routineScheduled = false
    }

    // MARK: 내부

    private func schedule(id: String, title: String, body: String, trigger: UNNotificationTrigger) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private func oneShot(at date: Date) -> UNNotificationTrigger {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }

    private func weekly(weekday: Int, minutesOfDay: Int) -> UNNotificationTrigger {
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = minutesOfDay / 60
        comps.minute = minutesOfDay % 60
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
    }

    static func hhmm(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}

/// 앱이 켜져 있는 동안에도 배너를 보여주기 위한 델리게이트
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
