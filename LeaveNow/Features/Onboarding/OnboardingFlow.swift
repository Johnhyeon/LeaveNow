import CoreLocation
import MapKit
import SwiftUI

/// 첫 설정: O1 시작 → O2 집 위치와 타는 역 (한 화면)
struct OnboardingFlow: View {
    // 개발용: -onboardingMap 으로 실행하면 집 위치 화면부터
    @State private var path: [Step] = ProcessInfo.processInfo.arguments.contains("-onboardingMap") ? [.home] : []
    enum Step: Hashable { case home }

    var body: some View {
        NavigationStack(path: $path) {
            IntroStep { path.append(.home) }
                .navigationDestination(for: Step.self) { _ in HomeStationStep() }
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

// MARK: O2 집 위치와 타는 역

/// 지도 가운데 핀을 집에 맞추면 아래에 가까운 역이 바로 나온다.
/// 집에 있지 않아도 주소 검색이나 지도 이동으로 설정할 수 있다.
private struct HomeStationStep: View {
    private let profile = Profile.shared

    struct Nearby: Identifiable, Hashable {
        let station: Station
        var walkMinutes: Int
        var id: String { station.name }
    }

    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.5663, longitude: 126.9779),   // 서울시청
        span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)))
    @State private var center = CLLocationCoordinate2D(latitude: 37.5663, longitude: 126.9779)
    @State private var nearby: [Nearby] = []
    @State private var selected: Nearby?
    @State private var toPlatform = 10
    @State private var userAdjusted = false
    @State private var showStationSearch = false
    @State private var locating = false
    @StateObject private var search = PlaceSearch()
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera) {
                ForEach(nearby) { n in
                    Annotation(n.station.name, coordinate: n.station.coordinate) {
                        Circle()
                            .fill(n == selected ? Theme.now : LineStyle.color(n.station.lines.first ?? ""))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                center = context.region.center
                refreshNearby()
            }
            .overlay {
                // 가운데 핀 = 집
                Image(systemName: "house.circle.fill")
                    .font(.system(size: 40))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.ink)
                    .shadow(radius: 4)
                    .offset(y: -20)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .bottom)

            searchBar
        }
        .safeAreaInset(edge: .bottom) { panel }
        .navigationTitle("집이 어디예요?")
        .navigationBarTitleDisplayMode(.inline)
        .task { await startAtCurrentLocationIfAllowed() }
        .sheet(isPresented: $showStationSearch) {
            StationSearchSheet { station in
                showStationSearch = false
                let n = Nearby(station: station, walkMinutes: estimateWalk(to: station))
                if !nearby.contains(n) { nearby.insert(n, at: 0) }
                choose(n)
            }
        }
    }

    // MARK: 검색창

    private var searchBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.mute)
                TextField("주소나 건물 이름으로 찾기", text: $search.query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .foregroundStyle(Theme.ink)
                if !search.query.isEmpty {
                    Button { search.query = ""; searchFocused = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.mute)
                    }
                }
                Divider().frame(height: 20)
                Button {
                    Task { await moveToCurrentLocation() }
                } label: {
                    if locating { ProgressView() } else { Image(systemName: "location.fill") }
                }
                .foregroundStyle(Theme.now)
                .accessibilityLabel("현재 위치로")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)

            if searchFocused && !search.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(search.results.prefix(5), id: \.self) { item in
                        Button {
                            Task { await pick(item) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundStyle(Theme.ink)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle).font(.caption).foregroundStyle(Theme.mute)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                        Divider()
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: 아래 패널

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("핀을 집에 맞추면 가까운 역을 찾아요. 집 위치는 이 폰에만 저장돼요.")
                .font(.footnote)
                .foregroundStyle(Theme.mute)

            Text("타는 역").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mute)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(nearby) { n in
                        Button { choose(n) } label: {
                            HStack(spacing: 6) {
                                LineDots(lines: n.station.lines)
                                Text(n.station.name).font(.subheadline.weight(.bold))
                                Text("\(n.walkMinutes)분").font(.caption).foregroundStyle(Theme.mute)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(n == selected ? Theme.now.opacity(0.15) : Color(.secondarySystemFill), in: Capsule())
                            .overlay(Capsule().stroke(n == selected ? Theme.now : .clear, lineWidth: 2))
                            .foregroundStyle(Theme.ink)
                        }
                        .buttonStyle(.plain)
                    }
                    Button("다른 역") { showStationSearch = true }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Color(.secondarySystemFill), in: Capsule())
                        .foregroundStyle(Theme.now)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("집 → 승강장").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mute)
                    Text("걸어서 \(selected?.walkMinutes ?? 0)분 + 엘리베이터·신호·역 안 3분")
                        .font(.caption).foregroundStyle(Theme.mute)
                }
                Spacer()
                Button { toPlatform = max(1, toPlatform - 1); userAdjusted = true } label: { Image(systemName: "minus.circle.fill") }
                Text("\(toPlatform)분").font(Theme.number(30)).frame(minWidth: 70)
                Button { toPlatform = min(60, toPlatform + 1); userAdjusted = true } label: { Image(systemName: "plus.circle.fill") }
            }
            .font(.title2)
            .foregroundStyle(Theme.ink)

            Button {
                finish()
            } label: {
                Text(selected.map { "\($0.station.name)역에서 탈게요" } ?? "역을 골라주세요")
                    .font(.headline.weight(.heavy)).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .foregroundStyle(Theme.onInk)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(selected == nil)
        }
        .padding(20)
        .background(Theme.paper, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .shadow(color: .black.opacity(0.1), radius: 10, y: -2)
    }

    // MARK: 동작

    private func refreshNearby() {
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let list = StationDirectory.shared.nearest(to: here, limit: 3).map {
            Nearby(station: $0.station, walkMinutes: Self.walkEstimate(meters: $0.meters))
        }
        nearby = list
        // 고른 역이 목록에 없으면 가장 가까운 역을 자동 선택
        if let sel = selected, let same = list.first(where: { $0.station == sel.station }) {
            choose(same, refine: false)
        } else if let first = list.first {
            choose(first)
        }
    }

    private func choose(_ n: Nearby, refine: Bool = true) {
        selected = n
        if !userAdjusted { toPlatform = n.walkMinutes + 3 }
        guard refine else { return }
        // 지도 도보 경로로 걷는 시간을 더 정확히
        let home = CLLocation(latitude: center.latitude, longitude: center.longitude)
        Task {
            let minutes = await LocationHelper.walkingMinutes(from: home, to: n.station.location)
            guard selected?.station == n.station else { return }
            var updated = n
            updated.walkMinutes = minutes
            selected = updated
            if let i = nearby.firstIndex(where: { $0.station == n.station }) { nearby[i] = updated }
            if !userAdjusted { toPlatform = minutes + 3 }
        }
    }

    private func estimateWalk(to station: Station) -> Int {
        Self.walkEstimate(meters: CLLocation(latitude: center.latitude, longitude: center.longitude).distance(from: station.location))
    }

    static func walkEstimate(meters: Double) -> Int { max(1, Int((meters * 1.3 / 75).rounded(.up))) }

    private func startAtCurrentLocationIfAllowed() async {
        if LocationHelper.shared.isAuthorized {
            await moveToCurrentLocation()
        } else {
            refreshNearby()
        }
    }

    private func moveToCurrentLocation() async {
        locating = true
        defer { locating = false }
        guard let loc = await LocationHelper.shared.currentLocation() else { return }
        move(to: loc.coordinate)
    }

    private func pick(_ completion: MKLocalSearchCompletion) async {
        searchFocused = false
        if let coord = await search.coordinate(for: completion) {
            search.query = completion.title
            move(to: coord)
        }
    }

    private func move(to coord: CLLocationCoordinate2D) {
        center = coord
        camera = .region(MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        refreshNearby()
    }

    private func finish() {
        guard let selected else { return }
        profile.homeLat = center.latitude
        profile.homeLon = center.longitude
        profile.homeStation = selected.station.name
        profile.homeToPlatform = toPlatform
        profile.onboarded = true
    }
}

/// 주소·장소 자동완성 (애플 지도)
@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" { didSet { completer.queryFragment = query } }
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.55, longitude: 126.98),
                                              span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8))
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let list = completer.results
        Task { @MainActor in self.results = list }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    func coordinate(for completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        let response = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        return response?.mapItems.first?.placemark.coordinate
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
