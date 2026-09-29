import SwiftUI

/// 화면 아래에서 차오른 물. level(0~1)만큼 차 있고, 물결은 천천히 출렁인다.
/// '동작 줄이기'가 켜져 있으면 물결을 멈춘다.
struct WaterView: View {
    var level: Double
    var water: Theme.Water
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let height = max(0, min(1, level)) * geo.size.height
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .bottom) {
                    WaveShape(phase: t * 1.1 + 1.4, amplitude: 7)
                        .fill(water.top.opacity(0.45))
                        .frame(height: height + 16)
                    WaveShape(phase: t * 1.5, amplitude: 6)
                        .fill(LinearGradient(colors: [water.top, water.bottom], startPoint: .top, endPoint: .bottom))
                        .frame(height: height + 12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.8), value: level)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct WaveShape: Shape {
    var phase: Double
    var amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let mid = amplitude
        path.move(to: CGPoint(x: 0, y: mid))
        var x: CGFloat = 0
        while x <= width {
            let rel = Double(x / max(width, 1))
            let y = mid + CGFloat(sin(rel * 2 * .pi * 1.3 + phase)) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 3
        }
        path.addLine(to: CGPoint(x: width, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}


/// 물 화면 전체. 글자를 두 겹으로 그려서 물에 잠긴 부분은 흰색, 물 밖은 짙은 색으로 보이게 한다.
/// 물이 빠지면 숫자가 물 밖으로 드러나며 색이 바뀐다.
struct WaterScene<Content: View>: View {
    var level: Double
    var water: Theme.Water
    var paper: Color
    var dryInk: Color
    var drySecondary: Color
    /// 아래 시트에 가려지는 높이. 물 바닥을 이 위로 올려서 남은 물이 항상 보이게 한다
    var floor: CGFloat = 0
    /// (주 글자색, 보조 글자색) 을 받아 글자 층을 그린다
    @ViewBuilder var content: (Color, Color) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { outer in
            let insets = outer.safeAreaInsets
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let visible = max(0, geo.size.height - floor)
                    let waterHeight = floor + max(0, min(1, level)) * visible
                    ZStack(alignment: .bottom) {
                        paper
                        WaveShape(phase: t * 1.1 + 1.4, amplitude: 7)
                            .fill(water.top.opacity(0.45))
                            .frame(height: waterHeight + 16)
                        WaveShape(phase: t * 1.5, amplitude: 6)
                            .fill(LinearGradient(colors: [water.top, water.bottom], startPoint: .top, endPoint: .bottom))
                            .frame(height: waterHeight + 12)
                        layer(dryInk, drySecondary, insets: insets)
                        layer(.white, .white.opacity(0.85), insets: insets)
                            .mask(alignment: .bottom) {
                                WaveShape(phase: t * 1.5, amplitude: 6)
                                    .frame(height: waterHeight + 12)
                            }
                    }
                }
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.8), value: level)
    }

    private func layer(_ primary: Color, _ secondary: Color, insets: EdgeInsets) -> some View {
        content(primary, secondary)
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
