import SwiftUI

/// 처음 실행할 때 출발역·방향을 정하는 화면
struct OnboardingView: View {
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @AppStorage("stationCode") private var savedStationCode = ""
    @AppStorage("direction") private var savedDirectionRaw = Direction.up.rawValue
    @AppStorage("routineDirection") private var savedRoutineDirectionRaw = Direction.up.rawValue
    @AppStorage("exitLabel") private var savedExitLabel = ""
    @AppStorage("bufferMinutes") private var bufferMinutes = 4

    private let store = TimetableStore.shared
    @State private var lineId = ""
    @State private var stationCode = ""
    @State private var directionRaw = Direction.up.rawValue
    @State private var exitLabel = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("집에서 나서는 순간부터 열차 탑승까지 걸리는 시간을 재서, 몇 시에 나가야 하는지 알려주는 앱입니다. 먼저 출발역을 정해주세요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("출발역") {
                    StationPickerSection(lineId: $lineId, stationCode: $stationCode)
                    if !stationCode.isEmpty {
                        TextField("출구 (예: 10번 출구, 선택)", text: $exitLabel)
                    }
                }

                if !stationCode.isEmpty {
                    Section {
                        if store.isLoaded(stationCode) {
                            Picker("주로 가는 방향", selection: $directionRaw) {
                                ForEach(Direction.allCases) { d in
                                    Text(store.directionTitle(stationCode: stationCode, direction: d)).tag(d.rawValue)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        } else if let err = store.errors[stationCode] {
                            Text(err).font(.footnote).foregroundStyle(.red)
                            Button("다시 시도") { Task { await store.refresh(stationCode: stationCode) } }
                        } else {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("시간표를 불러오는 중…").foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("방향")
                    } footer: {
                        Text("홈 화면에서 언제든 바꿀 수 있습니다.")
                    }

                    Section {
                        Stepper("승강장 여유  \(bufferMinutes)분", value: $bufferMinutes, in: 1...10)
                    } footer: {
                        Text("열차 시각보다 이만큼 일찍 승강장에 도착하도록 계산합니다. 구간별 소요 시간은 측정 탭에서 재면 됩니다.")
                    }
                }

                Section {
                    Button {
                        finish()
                    } label: {
                        Text("시작하기")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!store.isLoaded(stationCode))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("출발시각 설정")
            .task(id: stationCode) {
                await store.ensureLoaded(stationCode: stationCode)
            }
        }
        .interactiveDismissDisabled()
    }

    private func finish() {
        savedStationCode = stationCode
        savedDirectionRaw = directionRaw
        savedRoutineDirectionRaw = directionRaw
        savedExitLabel = exitLabel.trimmingCharacters(in: .whitespaces)
        hasCompletedSetup = true
    }
}
