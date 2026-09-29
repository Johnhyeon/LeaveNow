import SwiftUI

/// 3안(물 화면 + 올리면 노선도) 디자인 규칙. 색과 글꼴은 여기서만 정한다. 자세한 설명은 docs/DESIGN.md
enum Theme {
    // 바탕 (다크 모드면 밤 색으로 바뀐다)
    static let paper = Color.adaptive(light: "#EEF3F9", dark: "#0B1020")
    static let nightPaper = Color(hex: "#0B1020")   // 막차처럼 항상 밤인 화면
    static let sheet = Color.adaptive(light: "#F7F9FC", dark: "#141B2E")
    static let nightSheet = Color(hex: "#141B2E")
    static let card = Color.adaptive(light: "#FFFFFF", dark: "#1A2236")

    // 글자
    static let ink = Color.adaptive(light: "#0F1724", dark: "#F2F5FA")
    /// ink 색 버튼 위의 글자
    static let onInk = Color.adaptive(light: "#FFFFFF", dark: "#0B1020")
    static let mute = Color.adaptive(light: "#5E6C7F", dark: "#8FA0B8")
    static let nightMute = Color(hex: "#8FA0B8")

    // 표시
    static let now = Color(hex: "#0A6CFF")          // 노선도의 '지금' 점
    static let nightNow = Color(hex: "#FFB23E")
    static let walk = Color(hex: "#A7B1BE")         // 걷는 구간 점선

    /// 물 색. 남은 시간이 5분 안쪽이면 주황으로 바뀐다
    struct Water { let top: Color; let bottom: Color }
    static let dayWater = Water(top: Color(hex: "#5AA7FF"), bottom: Color(hex: "#2F7BF0"))
    static let urgentWater = Water(top: Color(hex: "#FFA25C"), bottom: Color(hex: "#F2711C"))
    static let nightWater = Water(top: Color(hex: "#2CC0B2"), bottom: Color(hex: "#138C84"))
    static let urgentSeconds: TimeInterval = 5 * 60

    /// 큰 숫자: 둥근 글꼴, 가장 굵게, 숫자 폭 고정
    static func number(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded).monospacedDigit()
    }
}
