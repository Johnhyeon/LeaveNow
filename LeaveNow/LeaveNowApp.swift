import SwiftUI
import SwiftData
import UserNotifications

@main
struct LeaveNowApp: App {
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TripRecord.self)
    }
}
