import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var records: [TripRecord]
    private let notifier = NotificationManager.shared
    @AppStorage("leadMinutes") private var leadMinutes = 5
    @AppStorage("routineEnabled") private var routineEnabled = false
    @AppStorage("routineTargetMinutes") private var routineTargetMinutes = 8 * 60
    @AppStorage("routineDirection") private var routineDirectionRaw = Direction.up.rawValue
    @AppStorage("stationCode") private var stationCode = Timetable.defaultStationCode
    @AppStorage("exitLabel") private var exitLabel = "10번 출구"
    @AppStorage("applyRealtimeDelay") private var applyRealtimeDelay = true
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
                    Picker("출발역", selection: $stationCode) {
                        ForEach(timetable.stations) { st in
                            Text(st.isExpressStop ? "\(st.name) (급행)" : st.name).tag(st.code)
                        }
                    }
                    TextField("출구 (표시용)", text: $exitLabel)
                } header: {
                    Text("역")
                } footer: {
                    Text("\(timetable.line) 전 역을 지원합니다. 급행 정차역은 (급행)으로 표시됩니다. 역을 바꾸면 측정 기록은 그대로 두고 시간표만 바뀝니다.")
                }

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
                    Stepper("미리 알림  출발 \(leadMinutes)분 전", value: $leadMinutes, in: 1...30)
                    Toggle("평일 출근 알림", isOn: $routineEnabled)
                    if routineEnabled {
                        Picker("방향", selection: $routineDirectionRaw) {
                            ForEach(Direction.allCases) { d in
                                Text(d.title).tag(d.rawValue)
                            }
                        }
                        DatePicker("타고 싶은 열차", selection: routineTargetBinding, displayedComponents: .hourAndMinute)
                        if let plan = RoutineSync.plan(records: records) {
                            LabeledContent("실제 열차", value: "\(plan.train.timeString) \(plan.train.type.rawValue)")
                            LabeledContent("출발 알림", value: "\(NotificationManager.hhmm(plan.leaveByMinutes - leadMinutes)) · \(NotificationManager.hhmm(plan.leaveByMinutes))")
                        }
                    }
                } header: {
                    Text("출발 알림")
                } footer: {
                    Text(routineEnabled
                         ? "월~금 매일, 고른 시각 이후 첫 열차 기준으로 출발 \(leadMinutes)분 전과 출발 시각에 알립니다. 측정이 쌓여 이동 시간이 바뀌면 앱을 열 때 자동으로 다시 맞춥니다."
                         : "홈 화면에서 열차 옆 종 아이콘을 누르면 그 열차 한 번만 알림을 받습니다. 매일 같은 열차를 탄다면 평일 출근 알림을 켜세요.")
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
                    LabeledContent("API 키", value: RealtimeService.shared.isConfigured ? "설정됨" : "없음")
                    Toggle("실시간 지연을 출발 시각에 반영", isOn: $applyRealtimeDelay)
                        .disabled(!RealtimeService.shared.isConfigured)
                } header: {
                    Text("실시간 도착 정보")
                } footer: {
                    Text("서울 열린데이터광장 인증키를 프로젝트의 LeaveNow/Resources/Secrets.plist 에 넣고 다시 설치하면 켜집니다. 실시간 정보와 시간표 열차를 대응시켜 지연된 만큼 출발 시각을 늦춥니다.")
                }

                Section {
                    LabeledContent("노선", value: "\(timetable.line) · \(timetable.stations.count)개 역")
                    LabeledContent("출처", value: timetable.source)
                    ForEach(Direction.allCases) { d in
                        let weekday = timetable.trains(stationCode: stationCode, direction: d, dayType: .weekday).count
                        let weekend = timetable.trains(stationCode: stationCode, direction: d, dayType: .weekend).count
                        LabeledContent(d.title, value: "평일 \(weekday)편 · 주말 \(weekend)편")
                    }
                } header: {
                    Text("시간표")
                } footer: {
                    Text("시간표를 갱신하려면 프로젝트에서 scripts/fetch_timetable.py 를 실행하면 됩니다.")
                }

                Section {
                    Button("측정 기록 전체 삭제", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("설정")
            .onChange(of: routineEnabled) { _, _ in resync() }
            .onChange(of: routineTargetMinutes) { _, _ in resync() }
            .onChange(of: routineDirectionRaw) { _, _ in resync() }
            .onChange(of: stationCode) { _, _ in resync() }
            .onChange(of: leadMinutes) { _, _ in resync() }
            .onChange(of: bufferMinutes) { _, _ in resync() }
            .onChange(of: estimateModeRaw) { _, _ in resync() }
            .onChange(of: includePrep) { _, _ in resync() }
            .confirmationDialog("모든 측정 기록을 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("전체 삭제", role: .destructive) { deleteAll() }
            }
        }
    }

    private var routineTargetBinding: Binding<Date> {
        Binding(
            get: {
                let start = Calendar.current.startOfDay(for: .now)
                return Calendar.current.date(byAdding: .minute, value: routineTargetMinutes, to: start) ?? start
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                routineTargetMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
            }
        )
    }

    private func resync() {
        Task { await RoutineSync.resync(records: records) }
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
