import CoreLocation
import SwiftUI

/// 0단계 위험 요소 확인용 화면. 1차 개발이 끝나면 지운다.
struct SpikeView: View {
    private let geo = GeofenceSpike.shared
    private let live = LiveActivitySpike.shared
    @State private var minutes = 2.0
    @State private var preview: PreviewKind?

    enum PreviewKind: String, Identifiable { case morning, night, urgent; var id: String { rawValue } }

    var body: some View {
        Form {
            Section {
                Button("아침 홈 (12분 남음)") { preview = .morning }
                Button("아침 홈 (4분 남음 · 주황)") { preview = .urgent }
                Button("막차 (47분 남음)") { preview = .night }
            } header: {
                Text("3안 디자인 미리보기")
            } footer: {
                Text("예시 데이터입니다. 아래 시트를 위로 올리면 노선도가 펼쳐집니다.")
            }

            Section {
                Stepper("열차까지 \(Int(minutes))분", value: $minutes, in: 1...30)
                Button("라이브 액티비티 시작") { live.start(minutes: minutes) }
                Button("모두 끝내기", role: .destructive) { Task { await live.endAll() } }
                if !live.message.isEmpty {
                    Text(live.message).font(.footnote).foregroundStyle(.secondary)
                }
                if !live.enabled {
                    Text("설정 > 출발시각 > 실시간 현황이 꺼져 있습니다.").font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("잠금화면 카운트다운")
            } footer: {
                Text("시작한 뒤 앱을 완전히 종료하고 잠금화면과 다이내믹 아일랜드의 숫자가 계속 줄어드는지 보세요.")
            }

            Section {
                LabeledContent("권한", value: authText)
                if geo.authorization != .authorizedAlways {
                    Button("위치 권한 요청 (항상 허용까지)") { geo.requestAlways() }
                }
                LabeledContent("중심", value: String(format: "%.5f, %.5f", geo.center.latitude, geo.center.longitude))
                Picker("반경", selection: Binding(get: { geo.radius }, set: { geo.radius = $0 })) {
                    Text("50m").tag(50.0)
                    Text("100m").tag(100.0)
                    Text("150m").tag(150.0)
                }
                .pickerStyle(.segmented)
                Button("지금 위치를 출구로 저장") { geo.useCurrentLocationAsCenter() }
                if geo.monitoring {
                    Button("감시 중지", role: .destructive) { geo.stop() }
                } else {
                    Button("감시 시작") { geo.start() }
                        .disabled(geo.authorization != .authorizedAlways)
                }
                Button {
                    geo.markGroundTruth()
                } label: {
                    Label("지금 출구에 도착했어요", systemImage: "hand.tap")
                        .font(.headline)
                }
            } header: {
                Text("역 도착 감지")
            } footer: {
                Text("처음 한 번은 10번 출구 앞에서 \"지금 위치를 출구로 저장\"을 누르세요. 그 뒤 출근길에 출구에 닿는 순간 \"지금 출구에 도착했어요\"를 누르면, 자동 감지 시각과 비교할 수 있습니다. 앱은 꺼져 있어도 됩니다.")
            }

            Section {
                if geo.log.isEmpty {
                    Text("기록 없음").foregroundStyle(.secondary)
                }
                ForEach(geo.log) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(entry.kind).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(Fmt.timeWithSeconds.string(from: entry.date)).monospacedDigit()
                        }
                        Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !geo.log.isEmpty {
                    Button("기록 지우기", role: .destructive) { geo.clearLog() }
                }
            } header: {
                Text("기록")
            }
        }
        .fullScreenCover(item: $preview) { kind in
            WaterHomeView(content: sample(kind)) { preview = nil }
        }
        .navigationTitle("0단계 실험")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sample(_ kind: PreviewKind) -> WaterHomeView.Content {
        switch kind {
        case .morning: return .morningSample()
        case .urgent: return .morningSample(minutes: 4)
        case .night: return .lastTrainSample()
        }
    }

    private var authText: String {
        switch geo.authorization {
        case .authorizedAlways: return "항상 허용"
        case .authorizedWhenInUse: return "앱 사용 중만"
        case .denied: return "거부됨"
        case .restricted: return "제한됨"
        case .notDetermined: return "아직 안 물음"
        @unknown default: return "알 수 없음"
        }
    }
}
