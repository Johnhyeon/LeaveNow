import SwiftUI
import SwiftData

private struct Lap: Identifiable {
    let id = UUID()
    let kind: SegmentKind
    let seconds: Double
}

struct MeasureView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("direction") private var directionRaw = Direction.bohun.rawValue

    @State private var sessionStart: Date?
    @State private var segmentStart: Date?
    @State private var laps: [Lap] = []
    @State private var showSaved = false
    @State private var showCancelConfirm = false
    @State private var showManualEntry = false
    @State private var showSignalCycle = false

    private var currentKind: SegmentKind? {
        guard sessionStart != nil, laps.count < SegmentKind.allCases.count else { return nil }
        return SegmentKind.allCases[laps.count]
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessionStart == nil {
                    idleView
                } else {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        runningView(now: context.date)
                    }
                }
            }
            .navigationTitle("측정")
            .toolbar {
                if sessionStart != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") { showCancelConfirm = true }
                    }
                }
            }
            .confirmationDialog("이번 측정을 버릴까요?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                Button("측정 취소", role: .destructive) { reset() }
            }
            .sheet(isPresented: $showManualEntry) { ManualEntryView() }
            .sheet(isPresented: $showSignalCycle) { SignalCycleView() }
            .alert("저장했습니다", isPresented: $showSaved) {
                Button("확인") {}
            } message: {
                Text("기록 탭에서 확인할 수 있습니다. 같은 구간이 \(Estimator.minimumSamples)회 이상 쌓이면 홈 화면 계산에 실측값이 쓰입니다.")
            }
        }
    }

    // MARK: 대기 화면

    private var idleView: some View {
        List {
            Section {
                Picker("방향", selection: $directionRaw) {
                    ForEach(Direction.allCases) { d in
                        Text(d.rawValue).tag(d.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                ForEach(Array(SegmentKind.allCases.enumerated()), id: \.element) { index, kind in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .frame(width: 22, height: 22)
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                            Text(kind.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("측정 순서")
            } footer: {
                Text("옷을 입기 시작할 때 시작 버튼을 누르고, 각 구간이 끝날 때마다 버튼을 한 번씩 누르세요. 마지막 '열차 탑승'을 누르면 자동으로 저장됩니다.")
            }

            Section {
                Button {
                    start()
                } label: {
                    Label("측정 시작", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Button {
                    showManualEntry = true
                } label: {
                    Label("시계로 잰 값 직접 입력", systemImage: "square.and.pencil")
                }
                Button {
                    showSignalCycle = true
                } label: {
                    Label("횡단보도 신호 주기 측정", systemImage: "light.beacon.max")
                }
            } header: {
                Text("다른 방법")
            } footer: {
                Text("신호 주기를 재두면 횡단보도 실측이 쌓이기 전까지 빨간불 길이를 대기 시간으로 씁니다.")
            }
        }
    }

    // MARK: 진행 화면

    private func runningView(now: Date) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("전체 경과")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(Fmt.stopwatch(now.timeIntervalSince(sessionStart ?? now)))
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.top)

            if let kind = currentKind {
                VStack(spacing: 8) {
                    Label(kind.title, systemImage: kind.systemImage)
                        .font(.title2.weight(.semibold))
                    Text(kind.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(Fmt.stopwatch(now.timeIntervalSince(segmentStart ?? now)))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Button {
                    finishSegment(at: now)
                } label: {
                    Text(kind.finishLabel)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
            }

            List {
                Section("완료한 구간") {
                    if laps.isEmpty {
                        Text("아직 없음").foregroundStyle(.secondary)
                    }
                    ForEach(laps) { lap in
                        HStack {
                            Image(systemName: lap.kind.systemImage)
                                .frame(width: 24)
                                .foregroundStyle(.secondary)
                            Text(lap.kind.title)
                            Spacer()
                            Text(Fmt.duration(lap.seconds)).monospacedDigit()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: 동작

    private func start() {
        let now = Date.now
        sessionStart = now
        segmentStart = now
        laps = []
    }

    private func finishSegment(at now: Date) {
        guard let kind = currentKind, let segStart = segmentStart else { return }
        laps.append(Lap(kind: kind, seconds: now.timeIntervalSince(segStart)))
        segmentStart = now
        if laps.count == SegmentKind.allCases.count {
            save()
        }
    }

    private func save() {
        let direction = Direction(rawValue: directionRaw) ?? .bohun
        let record = TripRecord(date: sessionStart ?? .now,
                                direction: direction,
                                durations: laps.map(\.seconds))
        context.insert(record)
        reset()
        showSaved = true
    }

    private func reset() {
        sessionStart = nil
        segmentStart = nil
        laps = []
    }
}
