import SwiftData
import SwiftUI

/// M3 경로 결과: 최단시간·최소환승을 계산하고, 같은 경로면 하나만 보여준다
struct RouteResultView: View {
    let origin: OriginInfo
    let placeName: String
    let stationName: String
    let deadline: Date
    let walkFromStation: Int
    let onPlanned: () -> Void

    private let profile = Profile.shared
    @Environment(\.modelContext) private var context
    @Query private var places: [Place]
    @Query private var trips: [PlannedTrip]

    @State private var plans: [RouteMode: TripPlan] = [:]
    @State private var mode: RouteMode = .fastest
    @State private var error: String?
    @State private var loading = true

    private var stationTarget: Date {
        deadline.addingTimeInterval(TimeInterval(-(profile.arriveEarly + walkFromStation) * 60))
    }
    private var sameRoute: Bool {
        guard let a = plans[.fastest], let b = plans[.fewestTransfers] else { return true }
        return a.trip.signature == b.trip.signature
    }
    private var current: TripPlan? { plans[mode] ?? plans.values.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("열차 시간을 맞춰보는 중…").foregroundStyle(Theme.mute)
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                } else if let error {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(error).foregroundStyle(.orange).font(.subheadline.weight(.semibold))
                        Button("다시 시도") { Task { await load() } }
                    }
                } else if let plan = current {
                    result(plan)
                }
            }
            .padding(20)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("\(origin.station) → \(stationName)")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let plan = current, !loading {
                Button {
                    save(plan)
                } label: {
                    Text("이 경로로 알림 받기").font(.headline.weight(.heavy)).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.ink)
                .foregroundStyle(Theme.onInk)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(Theme.paper)
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(placeName) · \(Fmt.time.string(from: deadline))까지")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.mute)
            if profile.arriveEarly > 0 {
                Text("\(profile.arriveEarly)분 일찍 도착하도록 계산했어요 · 설정에서 바꿀 수 있어요")
                    .font(.caption)
                    .foregroundStyle(Theme.mute)
            }
            if !loading, !sameRoute {
                Picker("경로", selection: $mode) {
                    ForEach(RouteMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func result(_ plan: TripPlan) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Fmt.time.string(from: plan.leaveBy)).font(Theme.number(56))
            Text(origin.label == "지금 여기" ? "출발" : "\(origin.label)에서 출발").font(.title3.weight(.heavy))
            Spacer()
            Text(plan.trip.transferCount == 0 ? "환승 없음" : "환승 \(plan.trip.transferCount)회")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(.secondarySystemFill), in: Capsule())
        }
        if plan.isLate {
            Text("마감까지는 못 가요 · \(Fmt.time.string(from: plan.trip.arrival.addingTimeInterval(TimeInterval(walkFromStation * 60)))) 도착 예상")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.orange)
        }
        if let car = RouteStops.fastCarText(plan) {
            FastCarCard(title: car.title, subtitle: car.subtitle)
        }
        RouteMapView(stops: RouteStops.make(plan: plan, origin: origin, placeName: placeName,
                                            walkFromStation: walkFromStation, arriveEarly: profile.arriveEarly,
                                            deadline: deadline, includeNow: false),
                     large: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
        let options = RouteStops.alternatives(plan: plan, placeName: placeName,
                                              walkFromStation: walkFromStation, deadline: deadline)
        if !options.isEmpty {
            AlternativesCard(options: options)
        }
        Text(otherLine(plan)).font(.footnote).foregroundStyle(Theme.mute)
    }

    private func otherLine(_ plan: TripPlan) -> String {
        if sameRoute { return "최소환승도 같은 경로예요." }
        let other: RouteMode = plan.mode == .fastest ? .fewestTransfers : .fastest
        guard let o = plans[other] else { return "" }
        let diff = Int(plan.leaveBy.timeIntervalSince(o.leaveBy) / 60)
        let when = diff > 0 ? "\(diff)분 먼저" : (diff < 0 ? "\(-diff)분 늦게" : "같은 시각에")
        return "\(other.title)은 환승 \(o.trip.transferCount)회, \(when) 나가야 해요."
    }

    private func load() async {
        loading = true
        error = nil
        do {
            plans = try await RoutePlanner.shared.planBoth(origin: origin, destination: stationName,
                                                           stationArrivalTarget: stationTarget,
                                                           bufferMinutes: profile.platformBuffer)
            mode = .fastest
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func save(_ plan: TripPlan) {
        // 저장한 곳: 같은 역·같은 이름이 있으면 갱신
        let minutes = Calendar.current.component(.hour, from: deadline) * 60 + Calendar.current.component(.minute, from: deadline)
        if let p = places.first(where: { $0.stationName == stationName && $0.name == placeName }) {
            p.deadlineMinutes = minutes
            p.walkFromStation = walkFromStation
            p.lastUsedAt = .now
        } else {
            context.insert(Place(name: placeName, stationName: stationName, walkFromStation: walkFromStation, deadlineMinutes: minutes))
        }
        // 이동은 하나만: 앞의 계획은 취소
        for t in trips where !t.cancelled { t.cancelled = true }
        context.insert(PlannedTrip(placeName: placeName, destinationStation: stationName, walkFromStation: walkFromStation,
                                   deadline: deadline, origin: origin, plan: plan))
        try? context.save()
        Task {
            if await TripNotifier.requestAuthorization() {
                TripNotifier.schedule(placeName: placeName, plan: plan, leadMinutes: profile.leadMinutes)
            }
        }
        onPlanned()
    }
}
