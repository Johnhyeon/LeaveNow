import CoreLocation
import SwiftData
import SwiftUI

/// M2 목적지 입력: 출발지(자동 선택), 최근 목적지, 도착역, 몇 시까지, 역에서 걸어서
struct DestinationFormView: View {
    var prefill: Place? = nil
    let onPlanned: () -> Void

    private let profile = Profile.shared
    @Query(sort: \Place.lastUsedAt, order: .reverse) private var places: [Place]
    @Environment(\.dismiss) private var dismiss

    @State private var origin: OriginChoice = .home
    @State private var hereOrigin: OriginInfo?
    @State private var stationName = ""
    @State private var placeName = ""
    @State private var deadline = DestinationFormView.defaultDeadline()
    @State private var walkFromStation = 0
    @State private var showSearch = false
    @State private var goRoute = false

    enum OriginChoice: Hashable {
        case home
        case place(String)   // 저장한 곳 이름
        case here
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("출발") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("집", selected: origin == .home) { origin = .home }
                            ForEach(places) { p in
                                chip(p.name, selected: origin == .place(p.name)) { origin = .place(p.name) }
                            }
                            chip(hereOrigin.map { "지금 여기 · \($0.station)" } ?? "지금 여기", selected: origin == .here) {
                                origin = .here
                                if hereOrigin == nil { Task { await locateHere() } }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if !places.isEmpty {
                    Section("최근") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(places.prefix(6)) { p in
                                    chip(p.name, selected: stationName == p.stationName) { apply(p) }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section {
                    Button {
                        showSearch = true
                    } label: {
                        HStack {
                            Text("도착역").foregroundStyle(Theme.ink)
                            Spacer()
                            if let s = StationDirectory.shared.station(named: stationName) {
                                LineDots(lines: s.lines)
                                Text(s.name).foregroundStyle(Theme.ink)
                            } else {
                                Text("역 찾기").foregroundStyle(Theme.mute)
                            }
                        }
                    }
                    DatePicker("몇 시까지", selection: $deadline, displayedComponents: .hourAndMinute)
                    Stepper(value: $walkFromStation, in: 0...40) {
                        HStack {
                            Text("역에서 걸어서")
                            Spacer()
                            Text(walkFromStation == 0 ? "선택" : "\(walkFromStation)분").foregroundStyle(Theme.mute)
                        }
                    }
                } footer: {
                    Text("목적지에 \(profile.arriveEarly)분 일찍 도착하도록 계산해요.")
                }

                Section {
                    Button {
                        goRoute = true
                    } label: {
                        Text("경로 보기").font(.headline.weight(.heavy)).frame(maxWidth: .infinity)
                    }
                    .disabled(StationDirectory.shared.station(named: stationName) == nil || resolvedOrigin == nil)
                }
            }
            .navigationTitle("어디로 가요?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
            .sheet(isPresented: $showSearch) {
                StationSearchSheet { station in
                    stationName = station.name
                    if placeName.isEmpty || StationDirectory.shared.station(named: placeName) != nil {
                        placeName = station.name
                    }
                    showSearch = false
                }
            }
            .navigationDestination(isPresented: $goRoute) {
                if let origin = resolvedOrigin {
                    RouteResultView(origin: origin,
                                    placeName: placeName.isEmpty ? stationName : placeName,
                                    stationName: stationName,
                                    deadline: resolvedDeadline,
                                    walkFromStation: walkFromStation,
                                    onPlanned: onPlanned)
                }
            }
            .task {
                if let prefill { apply(prefill) }
                await autoPickOrigin()
            }
        }
    }

    // MARK: 값

    private var resolvedOrigin: OriginInfo? {
        switch origin {
        case .home:
            return profile.homeOrigin
        case .place(let name):
            guard let p = places.first(where: { $0.name == name }) else { return nil }
            // 저장한 곳에서 출발: 그곳에서 역까지 걷는 시간 + 역 안 이동 3분
            return OriginInfo(label: p.name, station: p.stationName, toPlatformMinutes: max(3, p.walkFromStation + 3))
        case .here:
            return hereOrigin
        }
    }

    /// 오늘 그 시각이 이미 지났으면 내일로
    private var resolvedDeadline: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: deadline)
        var date = cal.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: 0, of: .now) ?? deadline
        if date < .now { date = cal.date(byAdding: .day, value: 1, to: date) ?? date }
        return date
    }

    private func apply(_ p: Place) {
        stationName = p.stationName
        placeName = p.name
        walkFromStation = p.walkFromStation
        let cal = Calendar.current
        deadline = cal.date(bySettingHour: p.deadlineMinutes / 60, minute: p.deadlineMinutes % 60, second: 0, of: .now) ?? deadline
    }

    /// 지금 위치로 출발지를 골라둔다: 집 근처면 집, 저장한 곳 역 근처면 그곳, 아니면 지금 여기
    private func autoPickOrigin() async {
        guard LocationHelper.shared.isAuthorized, let here = await LocationHelper.shared.currentLocation() else { return }
        if let home = profile.home, here.distance(from: home) < 300 {
            origin = .home
            return
        }
        for p in places {
            if let s = StationDirectory.shared.station(named: p.stationName), here.distance(from: s.location) < 500 {
                origin = .place(p.name)
                return
            }
        }
        await locateHere(from: here)
        origin = .here
    }

    private func locateHere(from known: CLLocation? = nil) async {
        let here: CLLocation?
        if let known { here = known } else { here = await LocationHelper.shared.currentLocation() }
        guard let here, let nearest = StationDirectory.shared.nearest(to: here, limit: 1).first else { return }
        let walk = await LocationHelper.walkingMinutes(from: here, to: nearest.station.location)
        hereOrigin = OriginInfo(label: "지금 여기", station: nearest.station.name, toPlatformMinutes: walk + 3)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Theme.now.opacity(0.14) : Color(.secondarySystemFill), in: Capsule())
                .foregroundStyle(selected ? Theme.now : Theme.ink)
        }
        .buttonStyle(.plain)
    }

    static func defaultDeadline() -> Date {
        let cal = Calendar.current
        let next = cal.date(byAdding: .hour, value: 2, to: .now) ?? .now
        return cal.date(bySettingHour: cal.component(.hour, from: next), minute: 0, second: 0, of: next) ?? next
    }
}
