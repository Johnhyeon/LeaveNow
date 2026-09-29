import SwiftData
import SwiftUI

/// 홈: 진행 중인 이동이 있으면 물 화면(M1), 없으면 일정 없는 날 홈(M1b)
struct HomeRootView: View {
    @Query(sort: \PlannedTrip.createdAt, order: .reverse) private var trips: [PlannedTrip]
    @State private var showForm = false
    @State private var prefill: Place?
    @State private var showSettings = false

    private func active(at now: Date) -> PlannedTrip? {
        trips.first { t in
            !t.cancelled && (t.expectedArrival ?? t.deadline) > now.addingTimeInterval(-10 * 60)
        }
    }

    var body: some View {
        // 이동이 끝났는지 30초마다 다시 본다. 안 그러면 화면을 건드려야 일정 없는 홈으로 바뀐다
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let trip = active(at: context.date) {
                TripHomeView(trip: trip, onSettings: { showSettings = true }, onNew: { prefill = nil; showForm = true })
            } else {
                NoTripHomeView(onGo: { place in prefill = place; showForm = true },
                               onSettings: { showSettings = true })
                    .onAppear { if TripActivity.isRunning { TripActivity.endAll() } }
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
            PlaceShortcuts(showsTime: true) { onGo($0) }
                .padding(.top, 8)
            Text("누르면 바로 채워져요 · 길게 누르면 빼거나 지울 수 있어요").font(.footnote).foregroundStyle(Theme.mute)
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
    @State private var departing = false
    /// 출발했는데 원래 열차가 어려워 바꿨을 때 한동안 띄우는 안내
    @State private var notice: String?

    var body: some View {
        if let fallbackPlan = trip.plan, let origin = trip.origin {
            // 계획은 매번 새로 읽는다. 다시 계산하면 물 화면과 시트가 손대지 않아도 1초 안에 바뀐다
            WaterHomeView(live: { now in content(plan: trip.plan ?? fallbackPlan, origin: origin, now: now) },
                          onSettings: onSettings,
                          primaryAction: { Task { await recalculate(origin: origin) } },
                          extraActions: (trip.departedAt == nil ? [] : [
                            WaterHomeView.SheetAction(title: "출발 취소") { undoDeparture() },
                          ]) + [
                            .init(title: "다른 곳 가기") { onNew() },
                            .init(title: "이번 이동 취소", role: .destructive) {
                                trip.cancelled = true
                                try? trip.modelContext?.save()
                                TripNotifier.cancelAll()
                                TripActivity.endAll()
                            },
                          ])
            .task {
                // 개발용: -departNow 로 실행하면 출발 버튼을 누른 것처럼
                if ProcessInfo.processInfo.arguments.contains("-departNow"), trip.departedAt == nil {
                    await depart(origin: origin)
                }
            }
        } else {
            Text("계획을 읽지 못했어요").onAppear { trip.cancelled = true }
        }
    }

    private enum Phase: String { case beforeLeaving, toTrain, riding }

    private func phase(plan: TripPlan, now: Date) -> Phase {
        // 출발 버튼을 누르면 현관 시각 전이라도 바로 '열차까지'로 넘어간다
        if trip.departedAt == nil, now < plan.leaveBy.addingTimeInterval(60) { return .beforeLeaving }
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
        let current = phase(plan: plan, now: now)
        var target = plan.leaveBy, unit = origin.label == "집" ? "분 뒤 현관" : "분 뒤 출발", window: TimeInterval = 20 * 60
        switch current {
        case .beforeLeaving: break
        case .toTrain:
            target = plan.trip.departure
            unit = "분 뒤 열차"
            // 출발을 눌렀으면 그때부터 열차까지 물이 빠진다
            window = trip.departedAt.map { max(60, plan.trip.departure.timeIntervalSince($0)) }
                ?? TimeInterval((origin.toPlatformMinutes + profile.platformBuffer) * 60)
        case .riding: target = plan.trip.arrival; unit = "분 뒤 도착"; window = max(60, plan.trip.arrival.timeIntervalSince(plan.trip.departure))
        }
        let note: String? = notice
            ?? (late ? "마감보다 늦게 도착해요 · \(Fmt.time.string(from: arrive)) 예상" : nil)
            ?? (current == .toTrain && trip.departedAt != nil ? "승강장 목표 \(Fmt.time.string(from: plan.platformBy))" : nil)
        let main: WaterHomeView.MainAction? = trip.departedAt == nil && current != .riding
            ? .init(title: departing ? "확인하는 중…" : "출발", busy: departing) { Task { await depart(origin: origin) } }
            : nil
        return .init(meta: "\(trip.placeName) · \(Fmt.time.string(from: trip.deadline))까지",
                     unit: unit,
                     target: target,
                     window: window,
                     peekLeft: "\(Fmt.time.string(from: plan.leaveBy)) \(origin.label == "지금 여기" ? "출발" : origin.label) · \(trainText)",
                     peekRight: "\(trip.placeName) \(Fmt.time.string(from: arrive))",
                     stops: stops,
                     night: false,
                     buttonTitle: recalculating ? "다시 계산하는 중…" : "지금 기준으로 다시 계산",
                     note: note,
                     noteIsWarning: late || notice != nil,
                     details: details(plan: plan, origin: origin, arrive: arrive, now: now),
                     mainAction: main)
    }

    private func details(plan: TripPlan, origin: OriginInfo, arrive: Date, now: Date) -> WaterHomeView.SheetDetails {
        let t = { (d: Date) in Fmt.time.string(from: d) }
        let lead = plan.leaveBy.addingTimeInterval(TimeInterval(-profile.leadMinutes * 60))
        let early = Int(trip.deadline.timeIntervalSince(arrive) / 60)
        let doorToDoor = Int(arrive.timeIntervalSince(plan.leaveBy) / 60)
        let car = RouteStops.fastCar(plan)
        let departed = trip.departedAt != nil
        // 출발하면 알림은 취소되므로 알림 시각 대신 출발한 시각을 보여준다
        var compact: [WaterHomeView.SheetDetails.Item] = [departed
            ? .init(symbol: "figure.walk", text: "\(t(trip.departedAt ?? now)) 출발함")
            : .init(symbol: "bell.fill", text: "알림 \(t(lead)) · \(t(plan.leaveBy))")]
        if let car { compact.append(.init(symbol: "tram.fill", text: "\(car.car)칸 타기")) }

        let alternatives = RouteStops.alternatives(plan: plan, placeName: trip.placeName,
                                                   walkFromStation: trip.walkFromStation, deadline: trip.deadline)
        var alerts: [WaterHomeView.SheetDetails.Item] = []
        if !departed, lead > now { alerts.append(.init(symbol: "bell", text: "\(t(lead)) 미리 알림 · \(profile.leadMinutes)분 뒤 현관")) }
        if !departed, plan.leaveBy > now { alerts.append(.init(symbol: "bell.badge", text: "\(t(plan.leaveBy)) 지금 현관을 나서요")) }

        var chips = [plan.trip.transferCount == 0 ? "환승 없음" : "환승 \(plan.trip.transferCount)회", "도어 투 도어 \(doorToDoor)분"]
        if plan.trip.rides.first?.express == true { chips.append("급행") }
        return .init(compact: compact,
                     leaveTime: t(plan.leaveBy),
                     leaveLabel: origin.label == "지금 여기" ? "출발" : "\(origin.label)에서 출발",
                     arriveLine: "\(trip.placeName) \(t(arrive)) 도착 · \(early >= 0 ? "\(early)분 일찍" : "\(-early)분 늦음")",
                     chips: chips,
                     fastCar: RouteStops.fastCarText(plan),
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
            if let departedAt = trip.departedAt {
                TripActivity.start(plan: plan, origin: origin, destinationName: trip.placeName, startedAt: departedAt)
            } else {
                TripNotifier.schedule(placeName: trip.placeName, plan: plan, leadMinutes: profile.leadMinutes)
            }
        }
    }

    /// 출발 버튼: 시각을 기록하고 잠금화면에 열차까지 남은 시간을 띄운다.
    /// 지금 나가도 원래 열차를 못 타면 다음 열차로 바꾼다
    private func depart(origin: OriginInfo) async {
        guard !departing, var plan = trip.plan else { return }
        departing = true
        defer { departing = false }
        let now = Date.now
        if now.addingTimeInterval(TimeInterval(origin.toPlatformMinutes * 60)) > plan.trip.departure {
            let target = trip.deadline.addingTimeInterval(TimeInterval(-(profile.arriveEarly + trip.walkFromStation) * 60))
            if let next = try? await RoutePlanner.shared.plan(origin: origin, destination: trip.destinationStation,
                                                               stationArrivalTarget: target,
                                                               bufferMinutes: profile.platformBuffer,
                                                               mode: plan.mode, now: now) {
                notice = "\(TripNotifier.shortTrainLabel(plan))은 어려워요 · \(TripNotifier.shortTrainLabel(next))으로 바꿨어요"
                plan = next
                trip.update(plan: next)
                Task {
                    try? await Task.sleep(for: .seconds(60))
                    notice = nil
                }
            }
        }
        trip.departedAt = now
        try? trip.modelContext?.save()
        TripNotifier.cancelAll()
        TripActivity.start(plan: plan, origin: origin, destinationName: trip.placeName, startedAt: now)
    }

    private func undoDeparture() {
        trip.departedAt = nil
        try? trip.modelContext?.save()
        TripActivity.endAll()
        notice = nil
        if let plan = trip.plan {
            TripNotifier.schedule(placeName: trip.placeName, plan: plan, leadMinutes: profile.leadMinutes)
        }
    }
}
