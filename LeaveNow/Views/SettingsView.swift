import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("bufferMinutes") private var bufferMinutes = 4
    @AppStorage("estimateMode") private var estimateModeRaw = EstimateMode.safe.rawValue
    @AppStorage("includePrep") private var includePrep = true
    @State private var defaults: [SegmentKind: Double] = SegmentDefaults.load()
    @State private var showDeleteConfirm = false
    @AppStorage("crosswalkRedSeconds") private var crosswalkRed = 0.0
    @AppStorage("crosswalkGreenSeconds") private var crosswalkGreen = 0.0

    private var timetable: Timetable { .shared }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("승강장 여유  \(bufferMinutes)분", value: $bufferMinutes, in: 1...10)
                    Picker("계산 기준", selection: $estimateModeRaw) {
                        ForEach(EstimateMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode.rawValue)
                        }
                    }
                    Toggle("준비 시간 포함", isOn: $includePrep)
                } header: {
                    Text("출발 계산")
                } footer: {
                    let mode = EstimateMode(rawValue: estimateModeRaw) ?? .safe
                    Text("열차 시각보다 \(bufferMinutes)분 일찍 승강장에 도착하도록 계산합니다. \(mode.detail). 준비 시간을 끄면 '현관을 나서는 시각' 기준으로 알려줍니다.")
                }

                Section {
                    ForEach(SegmentKind.travelSegments) { kind in
                        Stepper(value: binding(for: kind), in: 0...900, step: 10) {
                            HStack {
                                Text(kind.title)
                                Spacer()
                                Text(Fmt.duration(binding(for: kind).wrappedValue))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    LabeledContent("횡단보도 신호",
                                   value: crosswalkRed > 0 ? "빨강 \(Fmt.duration(crosswalkRed)) · 초록 \(Fmt.duration(crosswalkGreen))" : "미측정")
                    Button("기본 테스트 값으로 되돌리기") {
                        defaults = [:]
                        SegmentDefaults.save(defaults)
                    }
                } header: {
                    Text("구간 테스트 값")
                } footer: {
                    Text("측정 기록이 \(Estimator.minimumSamples)회 미만인 구간에 쓰는 임시 값입니다. 실측이 쌓이면 자동으로 무시됩니다.")
                }

                Section {
                    LabeledContent("역", value: "\(timetable.station) \(timetable.exit)")
                    LabeledContent("출처", value: timetable.source)
                    ForEach(Direction.allCases) { d in
                        let weekday = timetable.trains(direction: d, dayType: .weekday).count
                        let weekend = timetable.trains(direction: d, dayType: .weekend).count
                        LabeledContent(d.rawValue, value: "평일 \(weekday)편 · 주말 \(weekend)편")
                    }
                } header: {
                    Text("시간표")
                } footer: {
                    Text("실제 시간표로 바꾸려면 프로젝트의 Resources/timetable.json 을 교체하면 됩니다.")
                }

                Section {
                    Button("측정 기록 전체 삭제", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("설정")
            .confirmationDialog("모든 측정 기록을 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("전체 삭제", role: .destructive) { deleteAll() }
            }
        }
    }

    private func binding(for kind: SegmentKind) -> Binding<Double> {
        Binding(
            get: { defaults[kind] ?? kind.testDefaultSeconds },
            set: { newValue in
                defaults[kind] = newValue
                SegmentDefaults.save(defaults)
            }
        )
    }

    private func deleteAll() {
        try? context.delete(model: TripRecord.self)
    }
}
