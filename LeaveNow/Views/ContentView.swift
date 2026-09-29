import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @State private var designPreview: WaterHomeView.Content?

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
        .task {
            // 개발용: xcrun simctl launch ... -spikeLiveActivity 2 로 실행하면 카운트다운을 바로 시작
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-spikeLiveActivity"), i + 1 < args.count, let m = Double(args[i + 1]) {
                LiveActivitySpike.shared.start(minutes: m)
            }
            if let i = args.firstIndex(of: "-designPreview"), i + 1 < args.count {
                switch args[i + 1] {
                case "night": designPreview = .lastTrainSample()
                case "urgent": designPreview = .morningSample(minutes: 4)
                case "expanded": designPreview = .morningSample()
                default: designPreview = .morningSample()
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { designPreview != nil },
            set: { if !$0 { designPreview = nil } }
        )) {
            if let designPreview { WaterHomeView(content: designPreview) }
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasCompletedSetup },
            set: { if !$0 { hasCompletedSetup = true } }
        )) {
            OnboardingView()
        }
    }
}
