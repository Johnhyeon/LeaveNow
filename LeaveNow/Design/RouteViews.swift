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
    /// 화면을 넉넉히 쓰는 곳(경로 결과, 펼친 시트)에서는 간격과 글자를 키운다
    var large = false

    private var mute: Color { night ? Theme.nightMute : Theme.mute }
    private var nowColor: Color { night ? Theme.nightNow : Theme.now }
    private var background: Color { night ? Theme.nightSheet : Theme.sheet }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(stops) { stop in
                HStack(alignment: .top, spacing: large ? 10 : 8) {
                    Text(stop.time)
                        .font((large ? Font.subheadline : .caption).weight(.bold).monospacedDigit())
                        .foregroundStyle(stop.isNow ? nowColor : mute)
                        .frame(width: large ? 50 : 44, alignment: .trailing)
                    // 선은 칸 높이를 꽉 채운다. 설명이 두 줄로 늘어나도 다음 역까지 이어진다
                    ZStack(alignment: .top) {
                        legView(stop.leg)
                            .frame(maxHeight: .infinity)
                            .offset(y: 7)
                        node(stop)
                    }
                    .frame(width: 26)
                    .frame(minHeight: legHeight(stop), maxHeight: .infinity, alignment: .top)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.title).font((large ? Font.headline : .subheadline).weight(.bold))
                        if let detail = stop.detail {
                            Text(detail).font(large ? .subheadline : .caption).foregroundStyle(mute)
                        }
                    }
                    .offset(y: large ? -3 : -1)
                    .padding(.bottom, stop.leg == nil ? 0 : 6)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 걸리는 시간에 비례한 칸 높이. 지금부터 나설 때까지 기다리는 구간은 몇 시간이어도 짧게 둔다
    private func legHeight(_ stop: RouteStop) -> CGFloat {
        guard stop.leg != nil else { return 18 }
        if stop.isNow { return large ? 56 : 40 }
        let perMinute: CGFloat = large ? 4.4 : 2.6
        return min(max(large ? 46 : 30, CGFloat(stop.minutes) * perMinute), large ? 240 : 160)
    }

    @ViewBuilder
    private func legView(_ leg: RouteStop.Leg?) -> some View {
        switch leg {
        case .walk:
            DottedLine()
                .stroke(Theme.walk, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 6]))
                .frame(width: 3)
        case .line(let color):
            Capsule().fill(color).frame(width: large ? 7 : 6)
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
        .frame(width: large ? 16 : 14, height: large ? 16 : 14)
    }
}

/// "이 열차를 놓치면" 한 줄
struct RouteOption: Hashable {
    let left: String      // "18:43 급행"
    let right: String     // "시청 19:16 · 1분 늦음"
    let warning: Bool
}

/// 탈 칸 안내 카드
struct FastCarCard: View {
    let title: String
    let subtitle: String
    var night = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tram.fill")
                .font(.title3)
                .foregroundStyle(Theme.now)
                .frame(width: 40, height: 40)
                .background(Theme.now.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(night ? .white : Theme.ink)
                Text(subtitle).font(.caption).foregroundStyle(night ? Theme.nightMute : Theme.mute)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(night ? Color.white.opacity(0.06) : Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// 놓쳤을 때 탈 수 있는 다음 열차들
struct AlternativesCard: View {
    let options: [RouteOption]
    var night = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("이 열차를 놓치면").font(.caption.weight(.bold)).foregroundStyle(night ? Theme.nightMute : Theme.mute)
            ForEach(options, id: \.self) { option in
                HStack {
                    Text(option.left).font(.subheadline.weight(.semibold)).foregroundStyle(night ? .white : Theme.ink)
                    Spacer()
                    Text(option.right)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(option.warning ? Color.orange : (night ? Theme.nightMute : Theme.mute))
                }
            }
        }
        .padding(14)
        .background(night ? Color.white.opacity(0.06) : Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// 시트가 접혀 있을 때 보이는 한 줄 노선
struct RouteStripView: View {
    let stops: [RouteStop]
    var night = false

    var body: some View {
        // 나설 때까지 기다리는 구간은 몇 시간이어도 20분으로 친다
        let span = { (stop: RouteStop) in stop.isNow ? min(stop.minutes, 20) : stop.minutes }
        let total = max(stops.compactMap { $0.leg == nil ? nil : span($0) }.reduce(0, +), 1)
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(stops.filter { $0.leg != nil }) { stop in
                    let w = geo.size.width * span(stop) / total
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
