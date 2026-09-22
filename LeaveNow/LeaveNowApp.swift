import SwiftUI
import SwiftData

@main
struct LeaveNowApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: TripRecord.self)
    }
}
