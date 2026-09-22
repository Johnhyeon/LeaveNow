import SwiftUI

struct ContentView: View {
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
    }
}
