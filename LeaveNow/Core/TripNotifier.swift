import Foundation
import UserNotifications

/// 한 번 이동할 때 알림은 두 번: 미리 알림과 지금 현관
enum TripNotifier {
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    static func schedule(placeName: String, plan: TripPlan, leadMinutes: Int) {
        cancelAll()
        add(prefix: "trip", placeName: placeName, plan: plan, leadMinutes: leadMinutes)
    }

    /// 알림 두 개를 prefix.lead, prefix.go 로 건다. 반복 일정은 날짜마다 prefix 를 달리해 미리 걸어 둔다
    static func add(prefix: String, placeName: String, plan: TripPlan, leadMinutes: Int) {
        let center = UNUserNotificationCenter.current()
        let train = trainLabel(plan)
        let leave = Fmt.time.string(from: plan.leaveBy)
        let platform = Fmt.time.string(from: plan.platformBy)

        let lead = plan.leaveBy.addingTimeInterval(TimeInterval(-leadMinutes * 60))
        if lead > .now {
            let c = UNMutableNotificationContent()
            c.title = "\(leadMinutes)분 뒤 현관"
            c.body = "\(leave)에 나서야 \(train)을 탈 수 있어요."
            c.sound = .default
            c.interruptionLevel = .timeSensitive
            center.add(UNNotificationRequest(identifier: "\(prefix).lead", content: c, trigger: trigger(lead)))
        }
        if plan.leaveBy > .now {
            let c = UNMutableNotificationContent()
            c.title = "지금 현관을 나서요"
            c.body = "\(train) · 승강장에 \(platform)까지 · \(placeName)"
            c.sound = .default
            c.interruptionLevel = .timeSensitive
            center.add(UNNotificationRequest(identifier: "\(prefix).go", content: c, trigger: trigger(plan.leaveBy)))
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["trip.lead", "trip.go"])
    }

    static func trainLabel(_ plan: TripPlan) -> String {
        guard let ride = plan.trip.rides.first else { return "열차" }
        return "\(Fmt.time.string(from: ride.departure)) \(ride.line)\(ride.express ? " 급행" : "")"
    }

    /// "9:12 급행", "9:15 2호선" 처럼 짧게
    static func shortTrainLabel(_ plan: TripPlan) -> String {
        guard let ride = plan.trip.rides.first else { return "열차" }
        let short = LineStyle.short(ride.line)
        return "\(Fmt.time.string(from: ride.departure)) \(ride.express ? "급행" : short + (Int(short) != nil ? "호선" : ""))"
    }

    private static func trigger(_ date: Date) -> UNCalendarNotificationTrigger {
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
    }
}


/// 앱이 켜져 있어도 알림 배너를 보여준다
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
