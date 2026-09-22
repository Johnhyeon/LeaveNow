import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \TripRecord.date, order: .reverse) private var records: [TripRecord]
    private let notifier = NotificationManager.shared
    private let realtime = RealtimeService.shared
    @AppStorage("applyRealtimeDelay") private var applyRealtimeDelay = true
    @AppStorage("leadMinutes") private var leadMinutes = 5
    @AppStorage("direction") private var directionRaw = Direction.up.rawValue
    @AppStorage("stationCode") private var stationCode = Timetable.defaultStationCode
    @AppStorage("exitLabel") private var exitLabel = "10번 출구"
    @AppStorage("bufferMinutes") private var bufferMinutes = 4
    @AppStorage("estimateMode") private var estimateModeRaw = EstimateMode.safe.rawValue
    @AppStorage("includePrep") private var includePrep = true
    @State private var showBreakdown = false

    private var direction: Direction { Direction.parse(directionRaw) }
    private var stationName: String { Timetable.shared.station(code: stationCode)?.name ?? "?" }
    private var mode: EstimateMode { EstimateMode(rawValue: estimateModeRaw) ?? .safe }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                content(now: context.date)
            }
            .navigationTitle("\(stationName)역 \(exitLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .task { await syncNotifications() }
            .task(id: stationCode) {
                // 화면이 떠 있는 동안 30초마다 실시간 도착 정보 갱신
                while !Task.isCancelled {
                    await realtime.refresh(stationName: stationName)
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await syncNotifications() }
                    Task { await realtime.refresh(stationName: stationName) }
                }
            }
            .onChange(of: records.count) { _, _ in
                Task { await syncNotifications() }
            }
        }
    }

    /// 대기 중 알림 상태를 읽고, 평일 출근 알림을 현재 추정치로 다시 예약
    private func syncNotifications() async {
        await notifier.refresh()
        await RoutineSync.resync(records: records)
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let estimates = Estimator.estimates(records: records, mode: mode)
        let travel = Estimator.travelSeconds(estimates, includePrep: includePrep)
        let buffer = Double(bufferMinutes * 60)
        let scheduled = Planner.options(now: now, stationCode: stationCode, direction: direction, bufferSeconds: buffer, travelSeconds: travel)
        let delays = realtime.isConfigured ? RealtimeMatcher.delays(options: scheduled, arrivals: realtime.arrivals, direction: direction) : [:]
        let options = scheduled.map { opt -> TrainOption in
            guard applyRealtimeDelay, let d = delays[opt.id] else { return opt }
            return opt.applying(delay: d)
        }
        let next = options.first { $0.isCatchable(at: now) }

        List {
            Section {
                Picker("방향", selection: $directionRaw) {
                    ForEach(Direction.allCases) { d in
                        Text(d.title).tag(d.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("지금 나가면") {
                if let next {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Fmt.time.string(from: next.leaveBy))
                                .font(.system(size: 46, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("까지 출발")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        Text(Fmt.relative(next.leaveBy, from: now))
                            .font(.headline)
                            .foregroundStyle(.tint)
                        Divider()
                        infoRow("탈 열차", "\(Fmt.time.string(from: next.departure)) \(next.train.type.rawValue)")
                        infoRow("승강장 도착 목표", "\(Fmt.time.string(from: next.platformArrival)) (\(bufferMinutes)분 전)")
                        infoRow("이동 시간", Fmt.duration(travel))
                        if next.delay != 0 {
                            infoRow("실시간 반영", delayText(next.delay))
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("오늘 남은 열차가 없습니다.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if !realtime.isConfigured {
                    Text("설정 탭의 안내대로 API 키 파일을 넣으면 실시간 도착 정보가 표시됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let err = realtime.errorText {
                    Text(err).font(.footnote).foregroundStyle(.red)
                } else {
                    let mine = realtime.arrivals.filter { $0.direction == direction }.prefix(4)
                    if mine.isEmpty {
                        Text(realtime.lastUpdated == nil ? "불러오는 중…" : "이 방향으로 접근 중인 열차 정보가 없습니다.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(mine)) { arrival in
                        HStack {
                            TypeBadge(type: arrival.type)
                            Text("\(arrival.destination)행")
                            Spacer()
                            Text(arrival.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("실시간 도착")
                    Spacer()
                    if let t = realtime.lastUpdated {
                        Text("갱신 \(Fmt.timeWithSeconds.string(from: t))")
                    }
                    Button {
                        Task { await realtime.refresh(stationName: stationName) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(!realtime.isConfigured || realtime.isLoading)
                }
            }

            Section("다음 열차 · \(DayType.of(now).title)") {
                if options.isEmpty {
                    Text("시간표에 열차가 없습니다.").foregroundStyle(.secondary)
                }
                ForEach(options) { option in
                    TrainRow(option: option,
                             now: now,
                             isNext: option.id == next?.id,
                             isArmed: notifier.armedTrainIds.contains(option.id)) {
                        Task { await notifier.toggleTrainAlarm(option, leadMinutes: leadMinutes) }
                    }
                }
            }

            Section {
                DisclosureGroup(isExpanded: $showBreakdown) {
                    ForEach(estimates.filter { $0.kind.countsTowardTravel }) { est in
                        EstimateRow(estimate: est, disabled: est.kind == .prep && !includePrep)
                    }
                } label: {
                    HStack {
                        Text("이동 시간 추정 · \(mode.rawValue)")
                        Spacer()
                        Text(Fmt.duration(travel)).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("측정 기록이 \(Estimator.minimumSamples)회 이상 쌓인 구간은 실측값을, 그 전까지는 설정의 테스트 값을 사용합니다.")
            }
        }
        .alert("알림이 꺼져 있습니다", isPresented: Binding(
            get: { notifier.authorizationDenied },
            set: { if !$0 { notifier.authorizationDenied = false } }
        )) {
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("닫기", role: .cancel) {}
        } message: {
            Text("iOS 설정 > 출발시각 > 알림 에서 알림을 허용해야 출발 알림을 받을 수 있습니다.")
        }
    }

    private func delayText(_ delay: TimeInterval) -> String {
        let minutes = Int((delay / 60).rounded())
        if minutes == 0 { return "정시" }
        return minutes > 0 ? "+\(minutes)분 지연" : "\(minutes)분 빠름"
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.subheadline)
    }
}

private struct TrainRow: View {
    let option: TrainOption
    let now: Date
    let isNext: Bool
    let isArmed: Bool
    let onToggleAlarm: () -> Void

    var body: some View {
        let catchable = option.isCatchable(at: now)
        HStack {
            if catchable {
                Button(action: onToggleAlarm) {
                    Image(systemName: isArmed ? "bell.fill" : "bell")
                        .foregroundStyle(isArmed ? Color.accentColor : Color.secondary)
                        .frame(width: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isArmed ? "출발 알림 해제" : "출발 알림 설정")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.time.string(from: option.departure))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    TypeBadge(type: option.train.type)
                    if let note = option.train.note {
                        Text("\(note)행")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("출발 \(Fmt.time.string(from: option.leaveBy))")
                    .monospacedDigit()
                    .fontWeight(isArmed ? .semibold : .regular)
                HStack(spacing: 4) {
                    if option.delay != 0 {
                        let m = Int((option.delay / 60).rounded())
                        Text(m > 0 ? "+\(m)분" : "\(m)분")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(m > 0 ? .red : .green)
                    }
                    Text(Fmt.relative(option.leaveBy, from: now))
                        .font(.caption)
                        .foregroundStyle(catchable ? Color.secondary : Color.red)
                }
            }
        }
        .opacity(catchable ? 1 : 0.45)
        .listRowBackground(isNext ? Color.accentColor.opacity(0.12) : nil)
    }
}

struct TypeBadge: View {
    let type: TrainType

    var body: some View {
        Text(type.rawValue)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(type == .express ? Color.red.opacity(0.15) : Color.gray.opacity(0.15))
            .foregroundStyle(type == .express ? .red : .secondary)
            .clipShape(Capsule())
    }
}

private struct EstimateRow: View {
    let estimate: SegmentEstimate
    let disabled: Bool

    var body: some View {
        HStack {
            Image(systemName: estimate.kind.systemImage)
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(estimate.kind.title)
            Spacer()
            Text(Fmt.duration(estimate.seconds)).monospacedDigit()
            Text(estimate.isMeasured ? "실측 \(estimate.sampleCount)회" : "테스트")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(estimate.isMeasured ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                .foregroundStyle(estimate.isMeasured ? .green : .orange)
                .clipShape(Capsule())
        }
        .font(.subheadline)
        .strikethrough(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}
