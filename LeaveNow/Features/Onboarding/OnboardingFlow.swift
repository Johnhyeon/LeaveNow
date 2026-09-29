import CoreLocation
import SwiftUI

/// 첫 설정: O1 시작 → O2 집 위치 → O3 가까운 역 확인
struct OnboardingFlow: View {
    private let profile = Profile.shared
    @State private var path: [Step] = []
    @State private var home: CLLocation?
    @State private var suggestions: [Suggestion] = []

    enum Step: Hashable { case home, station }
    struct Suggestion: Identifiable, Hashable {
        let station: Station
        let walkMinutes: Int
        var id: String { station.name }
    }

    var body: some View {
        NavigationStack(path: $path) {
            IntroStep { path.append(.home) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .home:
                        HomeLocationStep { location, picked in
                            home = location
                            suggestions = picked
                            path.append(.station)
                        }
                    case .station:
                        StationConfirmStep(suggestions: suggestions) { station, toPlatform in
                            if let home {
                                profile.homeLat = home.coordinate.latitude
                                profile.homeLon = home.coordinate.longitude
                            }
                            profile.homeStation = station.name
                            profile.homeToPlatform = toPlatform
                            profile.onboarded = true
                        }
                    }
                }
        }
    }
}

// MARK: O1

private struct IntroStep: View {
    let next: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("몇 시에 현관을\n나서야 할까요?")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
            Text("가야 할 곳과 도착할 시각만 알려주세요. 집에서 나설 시각을 계산하고, 그때가 되면 알려드립니다.")
                .font(.body)
                .foregroundStyle(Theme.mute)
            Spacer()
            Button(action: next) {
                Text("시작하기").font(.headline.weight(.heavy)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .foregroundStyle(Theme.onInk)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper.ignoresSafeArea())
    }
}

// MARK: O2

private struct HomeLocationStep: View {
    let done: (CLLocation?, [OnboardingFlow.Suggestion]) -> Void
    @State private var working = false
    @State private var failed = false
    @State private var showSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("지금 집에 계세요?")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            Text("집 위치로 가까운 역과 걷는 시간을 찾아드려요. 집 위치는 이 폰에만 저장돼요.")
                .foregroundStyle(Theme.mute)
            if failed {
                Text("위치를 받지 못했어요. 설정에서 위치 권한을 확인하거나, 역 이름으로 찾아주세요.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer()
            Button {
                Task { await useCurrentLocation() }
            } label: {
                HStack {
                    if working { ProgressView().tint(.white) }
                    Text(working ? "가까운 역 찾는 중…" : "지금 위치를 집으로")
                }
                .font(.headline.weight(.heavy)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .foregroundStyle(Theme.onInk)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(working)
            Button("역 이름으로 찾기") { showSearch = true }
                .frame(maxWidth: .infinity)
                .foregroundStyle(Theme.mute)
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper.ignoresSafeArea())
        .sheet(isPresented: $showSearch) {
            StationSearchSheet { station in
                showSearch = false
                done(nil, [.init(station: station, walkMinutes: 7)])
            }
        }
    }

    private func useCurrentLocation() async {
        working = true
        defer { working = false }
        guard let location = await LocationHelper.shared.currentLocation() else {
            failed = true
            return
        }
        var list: [OnboardingFlow.Suggestion] = []
        for (station, _) in StationDirectory.shared.nearest(to: location, limit: 3) {
            let walk = await LocationHelper.walkingMinutes(from: location, to: station.location)
            list.append(.init(station: station, walkMinutes: walk))
        }
        done(location, list.sorted { $0.walkMinutes < $1.walkMinutes })
    }
}

// MARK: O3

private struct StationConfirmStep: View {
    let suggestions: [OnboardingFlow.Suggestion]
    let finish: (Station, Int) -> Void
    @State private var selected: OnboardingFlow.Suggestion?
    @State private var toPlatform = 10
    @State private var showSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("여기서 타시면 되죠?")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
            VStack(spacing: 8) {
                ForEach(suggestions) { s in
                    Button {
                        select(s)
                    } label: {
                        HStack {
                            LineDots(lines: s.station.lines)
                            Text(s.station.name).font(.headline).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("걸어서 \(s.walkMinutes)분").font(.subheadline).foregroundStyle(Theme.mute)
                        }
                        .padding(14)
                        .background(selected == s ? Theme.now.opacity(0.12) : Theme.card,
                                    in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(selected == s ? Theme.now : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
                Button("다른 역 찾기") { showSearch = true }
                .foregroundStyle(Theme.now)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("집에서 승강장까지").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mute)
                HStack {
                    Button { toPlatform = max(1, toPlatform - 1) } label: { Image(systemName: "minus.circle.fill") }
                    Text("\(toPlatform)분").font(Theme.number(44)).foregroundStyle(Theme.ink).frame(minWidth: 110)
                    Button { toPlatform = min(60, toPlatform + 1) } label: { Image(systemName: "plus.circle.fill") }
                }
                .font(.title)
                .foregroundStyle(Theme.ink)
                Text("걸어서 \(selected?.walkMinutes ?? 0)분에 엘리베이터·신호·역 안 이동 3분을 더했어요. 다니면서 자동으로 맞춰져요.")
                    .font(.footnote)
                    .foregroundStyle(Theme.mute)
            }
            Spacer()
            Button {
                if let s = selected { finish(s.station, toPlatform) }
            } label: {
                Text("맞아요").font(.headline.weight(.heavy)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .foregroundStyle(Theme.onInk)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(selected == nil)
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper.ignoresSafeArea())
        .onAppear { if selected == nil, let first = suggestions.first { select(first) } }
        .sheet(isPresented: $showSearch) {
            StationSearchSheet { station in
                showSearch = false
                select(.init(station: station, walkMinutes: selected?.walkMinutes ?? 7))
            }
        }
    }

    private func select(_ s: OnboardingFlow.Suggestion) {
        selected = s
        toPlatform = s.walkMinutes + 3
    }
}

/// 노선 색 점들
struct LineDots: View {
    let lines: [String]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(lines.prefix(3), id: \.self) { line in
                Text(LineStyle.short(line))
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(LineStyle.color(line), in: Capsule())
            }
        }
    }
}

/// 역 이름 검색
struct StationSearchSheet: View {
    let pick: (Station) -> Void
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(StationDirectory.shared.search(text)) { station in
                Button {
                    pick(station)
                } label: {
                    HStack {
                        Text(station.name).foregroundStyle(Theme.ink)
                        Spacer()
                        LineDots(lines: station.lines)
                    }
                }
            }
            .overlay {
                if text.isEmpty {
                    ContentUnavailableView("역 이름을 입력하세요", systemImage: "tram", description: Text("예: 가양, 강남, 서울역"))
                }
            }
            .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "역 이름")
            .navigationTitle("역 찾기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }
}
