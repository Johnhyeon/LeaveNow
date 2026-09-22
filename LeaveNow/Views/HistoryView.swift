import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TripRecord.date, order: .reverse) private var records: [TripRecord]

    var body: some View {
        NavigationStack {
            List {
                if records.isEmpty {
                    ContentUnavailableView("기록 없음",
                                           systemImage: "stopwatch",
                                           description: Text("측정 탭에서 이동을 기록하면 여기에 쌓입니다."))
                }
                ForEach(records) { record in
                    NavigationLink {
                        RecordDetailView(record: record)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Fmt.dateTime.string(from: record.date))
                            HStack(spacing: 8) {
                                Text(record.direction.rawValue)
                                Text("이동 \(Fmt.duration(record.travelTotal))")
                                if let wait = record.duration(for: .platformWait) {
                                    Text("대기 \(Fmt.duration(wait))")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(records[i]) }
                }
            }
            .navigationTitle("기록")
            .toolbar {
                if !records.isEmpty {
                    EditButton()
                }
            }
        }
    }
}

struct RecordDetailView: View {
    let record: TripRecord

    var body: some View {
        List {
            Section {
                LabeledContent("일시", value: Fmt.dateTime.string(from: record.date))
                LabeledContent("방향", value: record.direction.rawValue)
                LabeledContent("이동 시간 (승강장 대기 제외)", value: Fmt.duration(record.travelTotal))
                LabeledContent("전체", value: Fmt.duration(record.total))
            }
            Section("구간별") {
                ForEach(SegmentKind.allCases) { kind in
                    HStack {
                        Image(systemName: kind.systemImage)
                            .frame(width: 24)
                            .foregroundStyle(.secondary)
                        Text(kind.title)
                        if kind.isVariable {
                            Text("변동")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                        Text(record.duration(for: kind).map(Fmt.duration) ?? "-")
                            .monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("측정 상세")
        .navigationBarTitleDisplayMode(.inline)
    }
}
