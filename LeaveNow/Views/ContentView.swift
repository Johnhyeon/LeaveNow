import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("홈", systemImage: "house") }
            MeasureView()
                .tabItem { Label("측정", systemImage: "stopwatch") }
            HistoryView()
                .tabItem { Label("기록", systemImage: "list.bullet.clipboard") }
            SettingsView()
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedSetup },
            set: { if !$0 { hasCompletedSetup = true } }
        )) {
            OnboardingView()
        }
    }
}
