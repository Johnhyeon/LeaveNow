import SwiftData
import SwiftUI

/// 홈: 진행 중인 이동이 있으면 물 화면(M1), 없으면 일정 없는 날 홈(M1b)
struct HomeRootView: View {
    @Query(sort: \PlannedTrip.createdAt, order: .reverse) private var trips: [PlannedTrip]
    @State private var showForm = false
    @State private var prefill: Place?
    @State private var showSettings = false

    private var active: PlannedTrip? {
        trips.first { t in
            !t.cancelled && (t.expectedArrival ?? t.deadline) > Date.now.addingTimeInterval(-10 * 60)
        }
    }

    var body: some View {
        Group {
            if let trip = active {
                TripHomeView(trip: trip, onSettings: { showSettings = true }, onNew: { prefill = nil; showForm = true })
            } else {
                NoTripHomeView(onGo: { place in prefill = place; showForm = true },
                               onSettings: { showSettings = true })
            }
        }
        .sheet(isPresented: $showForm) {
            DestinationFormView(prefill: prefill) { showForm = false }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

/// M1b: 오늘 정해진 이동이 없을 때
struct NoTripHomeView: View {
    let onGo: (Place?) -> Void
    let onSettings: () -> Void
    @Query(sort: \Place.lastUsedAt, order: .reverse) private var places: [Place]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(Fmt.weekday.string(from: .now)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.mute)
                Spacer()
                Button(action: onSettings) {
                    Image(systemName: "gearshape").font(.body.weight(.semibold)).frame(width: 32, height: 32)
                }
                .foregroundStyle(Theme.mute)
                .accessibilityLabel("설정")
            }
            Spacer()
            Text("오늘은 정해진\n이동이 없어요")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.ink)
            Spacer()
            Button {
                onGo(nil)
            } label: {
                Text("어디 가요?").font(.title3.weight(.heavy)).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.ink)
            .foregroundStyle(Theme.onInk)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            if !places.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(places.prefix(6)) { p in
                            Button {
                                onGo(p)
                            } label: {
                                Text("\(p.name) · \(String(format: "%d:%02d", p.deadlineMinutes / 60, p.deadlineMinutes % 60))")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Color(.secondarySystemFill), in: Capsule())
                                    .foregroundStyle(Theme.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("저장한 곳을 누르면 바로 계산해요").font(.footnote).foregroundStyle(Theme.mute)
            }
        }
        .padding(24)
        .foregroundStyle(Theme.ink)
        .background(Theme.paper.ignoresSafeArea())
    }
}

/// M1: 진행 중인 이동. 현관까지 → 열차까지 → 도착까지 차례로 물이 빠진다
struct TripHomeView: View {
    let trip: PlannedTrip
    let onSettings: () -> Void
    let onNew: () -> Void

    private let profile = Profile.shared
    @State private var recalculating = false

    var body: some View {
        if let fallbackPlan = trip.plan, let origin = trip.origin {
            // 계획은 매번 새로 읽는다. 다시 계산하면 물 화면과 시트가 손대지 않아도 1초 안에 바뀐다
            WaterHomeView(live: { now in content(plan: trip.plan ?? fallbackPlan, origin: origin, now: now) },
                          onSettings: onSettings,
                          primaryAction: { Task { await recalculate(origin: origin) } },
                          extraActions: [
                            .init(title: "다른 곳 가기") { onNew() },
                            .init(title: "이번 이동 취소", role: .destructive) {
                                trip.cancelled = true
                                try? trip.modelContext?.save()
                                TripNotifier.cancelAll()
                            },
                          ])
        } else {
            Text("계획을 읽지 못했어요").onAppear { trip.cancelled = true }
        }
    }

    private enum Phase: String { case beforeLeaving, toTrain, riding }

    private func phase(plan: TripPlan, now: Date) -> Phase {
        if now < plan.leaveBy.addingTimeInterval(60) { return .beforeLeaving }
        if now < plan.trip.departure { return .toTrain }
        return .riding
    }

    private func content(plan: TripPlan, origin: OriginInfo, now: Date) -> WaterHomeView.Content {
        let ride = plan.trip.rides.first
        let trainText = ride.map { "\(Fmt.time.string(from: $0.departure)) \($0.express ? "급행" : $0.line)" } ?? ""
        let arrive = trip.expectedArrival ?? plan.trip.arrival
        let stops = RouteStops.make(plan: plan, origin: origin, placeName: trip.placeName,
                                    walkFromStation: trip.walkFromStation, arriveEarly: profile.arriveEarly,
                                    deadline: trip.deadline, now: now)
        let late = plan.isLate || arrive > trip.deadline
        var target = plan.leaveBy, unit = origin.label == "집" ? "분 뒤 현관" : "분 뒤 출발", window: TimeInterval = 20 * 60
        switch phase(plan: plan, now: now) {
        case .beforeLeaving: break
        case .toTrain: target = plan.trip.departure; unit = "분 뒤 열차"; window = TimeInterval((origin.toPlatformMinutes + profile.platformBuffer) * 60)
        case .riding: target = plan.trip.arrival; unit = "분 뒤 도착"; window = max(60, plan.trip.arrival.timeIntervalSince(plan.trip.departure))
        }
        return .init(meta: "\(trip.placeName) · \(Fmt.time.string(from: trip.deadline))까지",
                     unit: unit,
                     target: target,
                     window: window,
                     peekLeft: "\(Fmt.time.string(from: plan.leaveBy)) \(origin.label == "지금 여기" ? "출발" : origin.label) · \(trainText)",
                     peekRight: "\(trip.placeName) \(Fmt.time.string(from: arrive))",
                     stops: stops,
                     night: false,
                     buttonTitle: recalculating ? "다시 계산하는 중…" : "지금 기준으로 다시 계산",
                     note: late ? "마감보다 늦게 도착해요 · \(Fmt.time.string(from: arrive)) 예상" : nil,
                     noteIsWarning: late,
                     details: details(plan: plan, origin: origin, arrive: arrive, now: now))
    }

    private func details(plan: TripPlan, origin: OriginInfo, arrive: Date, now: Date) -> WaterHomeView.SheetDetails {
        let t = { (d: Date) in Fmt.time.string(from: d) }
        let lead = plan.leaveBy.addingTimeInterval(TimeInterval(-profile.leadMinutes * 60))
        let early = Int(trip.deadline.timeIntervalSince(arrive) / 60)
        let doorToDoor = Int(arrive.timeIntervalSince(plan.leaveBy) / 60)
        let car = RouteStops.fastCar(plan)
        var compact: [WaterHomeView.SheetDetails.Item] = [.init(symbol: "bell.fill", text: "알림 \(t(lead)) · \(t(plan.leaveBy))")]
        if let car { compact.append(.init(symbol: "tram.fill", text: "\(car.car)칸 타기")) }

        let walk = TimeInterval(trip.walkFromStation * 60)
        let alternatives = (plan.alternatives ?? []).map { alt -> WaterHomeView.SheetDetails.Option in
            let first = alt.rides.first
            let label = first.map { "\(t($0.departure)) \($0.express ? "급행" : LineStyle.short($0.line) + (Int(LineStyle.short($0.line)) != nil ? "호선" : ""))" } ?? t(alt.departure)
            let placeArrive = alt.arrival.addingTimeInterval(walk)
            let diff = Int(placeArrive.timeIntervalSince(trip.deadline) / 60)
            let status = diff > 0 ? "\(diff)분 늦음" : (diff == 0 ? "딱 맞음" : "\(-diff)분 일찍")
            return .init(left: label, right: "\(trip.placeName) \(t(placeArrive)) · \(status)", warning: diff > 0)
        }
        var alerts: [WaterHomeView.SheetDetails.Item] = []
        if lead > now { alerts.append(.init(symbol: "bell", text: "\(t(lead)) 미리 알림 · \(profile.leadMinutes)분 뒤 현관")) }
        if plan.leaveBy > now { alerts.append(.init(symbol: "bell.badge", text: "\(t(plan.leaveBy)) 지금 현관을 나서요")) }

        var chips = [plan.trip.transferCount == 0 ? "환승 없음" : "환승 \(plan.trip.transferCount)회", "도어 투 도어 \(doorToDoor)분"]
        if plan.trip.rides.first?.express == true { chips.append("급행") }
        return .init(compact: compact,
                     leaveTime: t(plan.leaveBy),
                     leaveLabel: origin.label == "지금 여기" ? "출발" : "\(origin.label)에서 출발",
                     arriveLine: "\(trip.placeName) \(t(arrive)) 도착 · \(early >= 0 ? "\(early)분 일찍" : "\(-early)분 늦음")",
                     chips: chips,
                     fastCar: car.map { ("\($0.station)에서 \($0.car)칸에 타세요", "\($0.transfer) 환승 통로가 가까워요") },
                     alternatives: alternatives,
                     alerts: alerts)
    }

    private func recalculate(origin: OriginInfo) async {
        guard !recalculating else { return }
        recalculating = true
        defer { recalculating = false }
        let target = trip.deadline.addingTimeInterval(TimeInterval(-(profile.arriveEarly + trip.walkFromStation) * 60))
        let mode = trip.plan?.mode ?? .fastest
        if let plan = try? await RoutePlanner.shared.plan(origin: origin, destination: trip.destinationStation,
                                                           stationArrivalTarget: target,
                                                           bufferMinutes: profile.platformBuffer, mode: mode) {
            trip.update(plan: plan)
            try? trip.modelContext?.save()
            TripNotifier.schedule(placeName: trip.placeName, plan: plan, leadMinutes: profile.leadMinutes)
        }
    }
}
