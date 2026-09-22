import SwiftUI

/// 노선 → 역 선택. 설정 화면과 초기 설정 화면에서 공용
struct StationPickerSection: View {
    @Binding var lineId: String
    @Binding var stationCode: String
    private let store = TimetableStore.shared

    var body: some View {
        Picker("노선", selection: $lineId) {
            Text("선택").tag("")
            ForEach(store.lines) { line in
                Label {
                    Text(line.name)
                } icon: {
                    Circle().fill(Color(hex: line.color)).frame(width: 10, height: 10)
                }
                .tag(line.id)
            }
        }
        .onChange(of: lineId) { _, newValue in
            if let line = store.line(id: newValue), !line.stations.contains(where: { $0.code == stationCode }) {
                stationCode = line.stations.first?.code ?? ""
            }
        }
        if let line = store.line(id: lineId) {
            Picker("역", selection: $stationCode) {
                ForEach(line.stations) { st in
                    Text(st.express ? "\(st.name) (급행)" : st.name).tag(st.code)
                }
            }
        }
    }
}

extension Color {
    /// "#RRGGBB" 문자열로 색 만들기
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
