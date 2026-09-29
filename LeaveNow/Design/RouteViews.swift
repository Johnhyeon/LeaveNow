import SwiftUI

/// 노선도의 한 칸: 역(또는 지점)과 그 아래로 이어지는 구간
struct RouteStop: Identifiable {
    enum Leg {
        case walk               // 걷거나 기다리는 구간: 점선
        case line(Color)        // 열차 구간: 노선색 실선
    }
    let id = UUID()
    let time: String
    let title: String
    var detail: String? = nil
    var nodeColor: Color? = nil
    var isNow = false
    /// 다음 칸까지의 구간. 마지막 칸은 nil
    var leg: Leg? = nil
    /// 다음 칸까지 걸리는 분. 세로 간격에 비례한다
    var minutes: Double = 0
}

/// 세로 노선도. 간격이 실제 걸리는 시간에 비례한다.
struct RouteMapView: View {
    let stops: [RouteStop]
    var night = false

    private var mute: Color { night ? Theme.nightMute : Theme.mute }
    private var nowColor: Color { night ? Theme.nightNow : Theme.now }
    private var background: Color { night ? Theme.nightSheet : Theme.sheet }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(stops) { stop in
                let height = stop.leg == nil ? 18 : max(30, stop.minutes * 2.6)
                HStack(alignment: .top, spacing: 8) {
                    Text(stop.time)
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(stop.isNow ? nowColor : mute)
                        .frame(width: 44, alignment: .trailing)
                    ZStack(alignment: .top) {
                        legView(stop.leg)
                            .frame(height: height)
                            .offset(y: 7)
                        node(stop)
                    }
                    .frame(width: 26, height: height, alignment: .top)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.title).font(.subheadline.weight(.bold))
                        if let detail = stop.detail {
                            Text(detail).font(.caption).foregroundStyle(mute)
                        }
                    }
                    .offset(y: -1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func legView(_ leg: RouteStop.Leg?) -> some View {
        switch leg {
        case .walk:
            DottedLine()
                .stroke(Theme.walk, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 6]))
                .frame(width: 3)
        case .line(let color):
            Capsule().fill(color).frame(width: 6)
        case nil:
            Color.clear.frame(width: 1)
        }
    }

    private func node(_ stop: RouteStop) -> some View {
        Group {
            if stop.isNow {
                Circle().fill(nowColor)
                    .overlay(Circle().stroke(nowColor.opacity(0.25), lineWidth: 5))
            } else {
                Circle().fill(background)
                    .overlay(Circle().stroke(stop.nodeColor ?? (night ? .white : Theme.ink), lineWidth: 3))
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// 시트가 접혀 있을 때 보이는 한 줄 노선
struct RouteStripView: View {
    let stops: [RouteStop]
    var night = false

    var body: some View {
        let total = max(stops.compactMap { $0.leg == nil ? nil : $0.minutes }.reduce(0, +), 1)
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(stops.filter { $0.leg != nil }) { stop in
                    let w = geo.size.width * stop.minutes / total
                    switch stop.leg {
                    case .walk:
                        HorizontalDottedLine()
                            .stroke(night ? Color.white.opacity(0.35) : Theme.walk,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 6]))
                            .frame(width: w, height: 3)
                    case .line(let color):
                        Capsule().fill(color).frame(width: max(w, 6), height: 5)
                    case nil:
                        EmptyView()
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

private struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: 0))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.height))
        return p
    }
}

private struct HorizontalDottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return p
    }
}
