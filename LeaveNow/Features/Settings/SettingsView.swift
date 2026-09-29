import SwiftData
import SwiftUI

/// S1 내 이동 시간 (1단계 범위)
struct SettingsView: View {
    @Bindable private var profile = Profile.shared
    @Query(sort: \Place.lastUsedAt, order: .reverse) private var places: [Place]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            Form {
                Section("집") {
                    Button {
                        showSearch = true
                    } label: {
                        HStack {
                            Text("타는 역").foregroundStyle(Theme.ink)
                            Spacer()
                            if let s = StationDirectory.shared.station(named: profile.homeStation) { LineDots(lines: s.lines) }
                            Text(profile.homeStation).foregroundStyle(Theme.mute)
                        }
                    }
                    Stepper("집 → 승강장  \(profile.homeToPlatform)분", value: $profile.homeToPlatform, in: 1...60)
                }
                Section {
                    Stepper("승강장 여유  \(profile.platformBuffer)분", value: $profile.platformBuffer, in: 0...15)
                    Stepper("목적지 일찍 도착  \(profile.arriveEarly)분", value: $profile.arriveEarly, in: 0...60)
                    Stepper("미리 알림  \(profile.leadMinutes)분 전", value: $profile.leadMinutes, in: 1...60)
                } header: {
                    Text("계산")
                } footer: {
                    Text("바꾼 값은 다음에 경로를 계산할 때부터 적용돼요.")
                }
                if !places.isEmpty {
                    Section("저장한 곳") {
                        ForEach(places) { p in
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("이름", text: Binding(get: { p.name }, set: { p.name = $0 }))
                                    .font(.body.weight(.semibold))
                                Text("\(p.stationName) · \(String(format: "%d:%02d", p.deadlineMinutes / 60, p.deadlineMinutes % 60))까지 · 역에서 \(p.walkFromStation)분")
                                    .font(.caption).foregroundStyle(Theme.mute)
                            }
                        }
                        .onDelete { offsets in offsets.forEach { context.delete(places[$0]) } }
                    }
                }
                Section {
                    NavigationLink("0단계 실험 (개발용)") { SpikeView() }
                    Button("첫 설정 다시 하기") {
                        profile.onboarded = false
                        dismiss()
                    }
                }
            }
            .navigationTitle("내 이동 시간")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
            .sheet(isPresented: $showSearch) {
                StationSearchSheet { station in
                    profile.homeStation = station.name
                    showSearch = false
                }
            }
        }
    }
}
