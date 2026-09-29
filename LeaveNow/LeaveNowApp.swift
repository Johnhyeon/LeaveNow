import SwiftUI
import SwiftData
import UserNotifications

@main
struct LeaveNowApp: App {
    private let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        // 위치 경계 이벤트로 앱이 백그라운드에서 다시 깨어날 때도 델리게이트가 살아 있어야 한다
        _ = GeofenceSpike.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [TripRecord.self, Place.self, PlannedTrip.self])
    }
}
