import SwiftUI
import SwiftData

struct HomeView: View {
    @Query(sort: \TripRecord.date, order: .reverse) private var records: [TripRecord]
    @AppStorage("direction") private var directionRaw = Direction.bohun.rawValue
    @AppStorage("bufferMinutes") private var bufferMinutes = 4
    @AppStorage("estimateMode") private var estimateModeRaw = EstimateMode.safe.rawValue
    @AppStorage("includePrep") private var includePrep = true
    @State private var showBreakdown = false

    private var direction: Direction { Direction(rawValue: directionRaw) ?? .bohun }
    private var mode: EstimateMode { EstimateMode(rawValue: estimateModeRaw) ?? .safe }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                content(now: context.date)
            }
            .navigationTitle("\(Timetable.shared.station) \(Timetable.shared.exit)")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let estimates = Estimator.estimates(records: records, mode: mode)
        let travel = Estimator.travelSeconds(estimates, includePrep: includePrep)
        let buffer = Double(bufferMinutes * 60)
        let options = Planner.options(now: now, direction: direction, bufferSeconds: buffer, travelSeconds: travel)
        let next = options.first { $0.isCatchable(at: now) }

        List {
            Section {
                Picker("방향", selection: $directionRaw) {
                    ForEach(Direction.allCases) { d in
                        Text(d.rawValue).tag(d.rawValue)
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
                    }
                    .padding(.vertical, 4)
                } else {
                    Text("오늘 남은 열차가 없습니다.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("다음 열차 · \(DayType.of(now).title)") {
                if options.isEmpty {
                    Text("시간표에 열차가 없습니다.").foregroundStyle(.secondary)
                }
                ForEach(options) { option in
                    TrainRow(option: option, now: now, isNext: option.id == next?.id)
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

    var body: some View {
        let catchable = option.isCatchable(at: now)
        HStack {
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
                Text(Fmt.relative(option.leaveBy, from: now))
                    .font(.caption)
                    .foregroundStyle(catchable ? Color.secondary : Color.red)
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
