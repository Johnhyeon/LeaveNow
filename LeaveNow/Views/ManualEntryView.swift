import SwiftUI
import SwiftData

/// 시계로 따로 잰 값을 나중에 손으로 입력하는 화면
struct ManualEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("direction") private var directionRaw = Direction.up.rawValue

    @State private var date = Date.now
    @State private var minutes: [SegmentKind: Int] = [:]
    @State private var seconds: [SegmentKind: Int] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("일시", selection: $date)
                    Picker("방향", selection: $directionRaw) {
                        ForEach(Direction.allCases) { d in
                            Text(d.title).tag(d.rawValue)
                        }
                    }
                }
                Section {
                    ForEach(SegmentKind.allCases) { kind in
                        HStack {
                            Label(kind.title, systemImage: kind.systemImage)
                            Spacer()
                            TextField("0", value: minutesBinding(kind), format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 44)
                            Text("분")
                            TextField("0", value: secondsBinding(kind), format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 44)
                            Text("초")
                        }
                    }
                } header: {
                    Text("구간별 소요 시간")
                } footer: {
                    Text("모르는 구간은 비워 두면 됩니다. 비워 둔 구간은 계산에서 제외됩니다.")
                }
            }
            .navigationTitle("직접 입력")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }.disabled(!hasAnyValue)
                }
            }
        }
    }

    private var hasAnyValue: Bool {
        SegmentKind.allCases.contains { total(for: $0) > 0 }
    }

    private func total(for kind: SegmentKind) -> Double {
        Double((minutes[kind] ?? 0) * 60 + (seconds[kind] ?? 0))
    }

    private func minutesBinding(_ kind: SegmentKind) -> Binding<Int?> {
        Binding<Int?>(get: { minutes[kind] }, set: { minutes[kind] = $0 })
    }

    private func secondsBinding(_ kind: SegmentKind) -> Binding<Int?> {
        Binding<Int?>(get: { seconds[kind] }, set: { seconds[kind] = $0 })
    }

    private func save() {
        let direction = Direction.parse(directionRaw)
        let durations = SegmentKind.allCases.map { total(for: $0) }
        context.insert(TripRecord(date: date, direction: direction, durations: durations, note: "직접 입력"))
        dismiss()
    }
}
