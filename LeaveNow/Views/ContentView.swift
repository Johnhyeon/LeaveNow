import SwiftData
import SwiftUI

struct ContentView: View {
    private let profile = Profile.shared
    @Environment(\.modelContext) private var context
    @State private var designPreview: WaterHomeView.Content?
    @State private var routePreview: (from: String, to: String, deadline: Date)?

    var body: some View {
        Group {
            if profile.onboarded {
                HomeRootView()
            } else {
                OnboardingFlow()
            }
        }
        .task { await runDebugArguments() }
        .sheet(isPresented: Binding(get: { routePreview != nil }, set: { if !$0 { routePreview = nil } })) {
            if let r = routePreview {
                NavigationStack {
                    RouteResultView(origin: OriginInfo(label: "집", station: r.from, toPlatformMinutes: profile.homeToPlatform),
                                    placeName: r.to, stationName: r.to, deadline: r.deadline, walkFromStation: 5) { routePreview = nil }
                }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { designPreview != nil },
            set: { if !$0 { designPreview = nil } }
        )) {
            if let designPreview { WaterHomeView(content: designPreview) }
        }
    }

    /// 개발용 실행 인자 (xcrun simctl launch ... 뒤에 붙인다)
    /// -spikeLiveActivity 2 · -designPreview morning|urgent|night
    /// -planTest 가양 강남 10:00 : 계산 결과를 콘솔에 출력
    /// -seedTrip 가양 강남 10:00 : 그 계획을 실제 이동으로 저장해 홈에 띄운다
    /// -resetOnboarding
    private func runDebugArguments() async {
        let args = ProcessInfo.processInfo.arguments
        func value(_ flag: String, _ offset: Int = 1) -> String? {
            guard let i = args.firstIndex(of: flag), i + offset < args.count else { return nil }
            return args[i + offset]
        }
        if args.contains("-resetOnboarding") { profile.onboarded = false }
        if let m = value("-spikeLiveActivity").flatMap(Double.init) { LiveActivitySpike.shared.start(minutes: m) }
        if let kind = value("-designPreview") {
            designPreview = kind == "night" ? .lastTrainSample() : (kind == "urgent" ? .morningSample(minutes: 4) : .morningSample())
        }
        for flag in ["-planTest", "-seedTrip", "-routePreview"] {
            guard let from = value(flag, 1), let to = value(flag, 2), let hhmm = value(flag, 3) else { continue }
            let parts = hhmm.split(separator: ":").compactMap { Int($0) }
            let cal = Calendar.current
            var deadline = cal.date(bySettingHour: parts.first ?? 10, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: .now) ?? .now
            if deadline < .now { deadline = cal.date(byAdding: .day, value: 1, to: deadline) ?? deadline }
            if !profile.onboarded || profile.homeStation.isEmpty {
                profile.homeStation = from
                profile.onboarded = true
            }
            if flag == "-routePreview" {
                routePreview = (from, to, deadline)
                continue
            }
            let origin = OriginInfo(label: "집", station: from, toPlatformMinutes: profile.homeToPlatform)
            let target = deadline.addingTimeInterval(TimeInterval(-profile.arriveEarly * 60))
            let started = Date.now
            do {
                let both = try await RoutePlanner.shared.planBoth(origin: origin, destination: to, stationArrivalTarget: target,
                                                                  bufferMinutes: profile.platformBuffer)
                guard let plan = both[.fastest] else { continue }
                if flag == "-planTest" {
                    let again = Date.now
                    _ = try await RoutePlanner.shared.planBoth(origin: origin, destination: to, stationArrivalTarget: target,
                                                               bufferMinutes: profile.platformBuffer)
                    print("PLAN 두 번째 계산 \(String(format: "%.2f", Date.now.timeIntervalSince(again)))초 · 최소환승 같은 경로 \(both[.fastest]?.trip.signature == both[.fewestTransfers]?.trip.signature)")
                }
                print("PLAN \(from)→\(to) 마감 \(Fmt.dateTime.string(from: deadline)) · 계산 \(String(format: "%.1f", Date.now.timeIntervalSince(started)))초")
                print("PLAN 현관 \(Fmt.time.string(from: plan.leaveBy)) · 승강장 \(Fmt.time.string(from: plan.platformBy)) · 늦음 \(plan.isLate)")
                for r in plan.trip.rides {
                    print("PLAN   \(r.line)\(r.express ? " 급행" : "") \(r.from) \(Fmt.timeWithSeconds.string(from: r.departure)) → \(r.to) \(Fmt.timeWithSeconds.string(from: r.arrival)) · \(r.stops)정거장")
                }
                for t in plan.trip.transfers { print("PLAN   환승 \(t.station) 걸어서 \(t.walkSeconds)초 대기 \(t.waitSeconds)초") }
                if flag == "-seedTrip" {
                    context.insert(PlannedTrip(placeName: to, destinationStation: to, walkFromStation: 0,
                                               deadline: deadline, origin: origin, plan: plan))
                    try? context.save()
                }
            } catch {
                print("PLAN 오류 \(error.localizedDescription)")
            }
        }
    }
}
