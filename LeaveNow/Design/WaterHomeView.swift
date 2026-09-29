import SwiftUI

/// 3안 홈: 평소엔 물과 큰 숫자, 아래 시트를 올리면 노선도.
/// 지금은 예시 데이터로 모양을 확인하는 미리보기용. 1단계에서 실제 계산과 연결한다.
struct WaterHomeView: View {
    struct Content {
        let meta: String
        let unit: String            // "분 뒤 현관"
        let target: Date            // 이 시각까지 나가야 한다
        let window: TimeInterval    // 물이 가득 찬 상태가 나타내는 시간
        let peekLeft: String
        let peekRight: String
        let stops: [RouteStop]
        let night: Bool
        let buttonTitle: String
        var note: String? = nil         // 시트 위쪽 안내 한 줄 (예: 늦음)
        var noteIsWarning = false
    }

    struct SheetAction: Identifiable {
        let id = UUID()
        let title: String
        var role: ButtonRole? = nil
        let action: () -> Void
    }

    let content: Content
    var onClose: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    var primaryAction: (() -> Void)? = nil
    var extraActions: [SheetAction] = []

    @State private var showSheet = true
    @State private var detent: PresentationDetent = .height(128)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, content.target.timeIntervalSince(context.date))
            let water = content.night ? Theme.nightWater
                : (remaining < Theme.urgentSeconds ? Theme.urgentWater : Theme.dayWater)
            WaterScene(level: remaining / content.window,
                       water: water,
                       paper: content.night ? Theme.nightPaper : Theme.paper,
                       dryInk: content.night ? .white : Theme.ink,
                       drySecondary: content.night ? Theme.nightMute : Theme.mute) { primary, secondary in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(content.meta)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(secondary)
                        Spacer()
                        if let onClose {
                            Button("닫기", action: onClose)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(secondary)
                        }
                        if let onSettings {
                            Button(action: onSettings) {
                                Image(systemName: "gearshape")
                                    .font(.body.weight(.semibold))
                                    .frame(width: 32, height: 32)
                            }
                            .foregroundStyle(secondary)
                            .accessibilityLabel("설정")
                        }
                    }
                    Spacer(minLength: 24)
                    Text(bigNumber(remaining))
                        .font(Theme.number(detent == .large ? 64 : 150))
                        .foregroundStyle(primary)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: bigNumber(remaining))
                    Text(remaining < 60 ? "지금 나가세요" : content.unit)
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(primary)
                    // 숫자가 화면 위쪽 3분의 1쯤 오도록 아래 공간을 더 크게 둔다
                    Spacer(minLength: 24)
                    Spacer(minLength: 24)
                    Spacer().frame(height: detent == .large ? 0 : 128)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(content.meta). \(bigNumber(remaining)) \(content.unit)")
        }
        .sheet(isPresented: $showSheet) {
            RouteSheet(content: content, detent: detent, primaryAction: primaryAction, extraActions: extraActions)
                .presentationDetents([.height(128), .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .height(128)))
                .presentationCornerRadius(28)
                .presentationBackground(content.night ? Theme.nightSheet : Theme.sheet)
                .interactiveDismissDisabled()
        }
    }

    private func bigNumber(_ remaining: TimeInterval) -> String {
        if remaining < 60 { return "0" }
        let minutes = Int((remaining / 60).rounded(.up))
        if minutes >= 100 { return String(format: "%d:%02d", minutes / 60, minutes % 60) }
        return "\(minutes)"
    }
}

private struct RouteSheet: View {
    let content: WaterHomeView.Content
    let detent: PresentationDetent
    var primaryAction: (() -> Void)? = nil
    var extraActions: [WaterHomeView.SheetAction] = []

    var body: some View {
        let ink = content.night ? Color.white : Theme.ink
        let mute = content.night ? Theme.nightMute : Theme.mute
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(content.peekLeft).font(.subheadline.weight(.bold)).foregroundStyle(ink)
                Spacer()
                Text(content.peekRight).font(.caption.weight(.semibold)).foregroundStyle(mute)
            }
            RouteStripView(stops: content.stops, night: content.night)
            if let note = content.note {
                Text(note)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(content.noteIsWarning ? Color.orange : mute)
            }
            if detent == .large {
                Divider().padding(.vertical, 4)
                ScrollView {
                    RouteMapView(stops: content.stops, night: content.night)
                        .foregroundStyle(ink)
                        .padding(.top, 8)
                }
                Button {
                    primaryAction?()
                } label: {
                    Text(content.buttonTitle)
                        .font(.headline.weight(.heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(content.night ? .white : Theme.ink)
                .foregroundStyle(content.night ? Theme.nightPaper : .white)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                ForEach(extraActions) { action in
                    Button(action.title, role: action.role, action: action.action)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }
}

// MARK: 예시 데이터

extension WaterHomeView.Content {
    static func morningSample(minutes: Double = 12) -> Self {
        let gold = Color(hex: "#BDB092"), red = Color(hex: "#D4003B")
        return .init(
            meta: "회사 · 강남 · 10:00까지",
            unit: "분 뒤 현관",
            target: .now.addingTimeInterval(minutes * 60),
            window: 20 * 60,
            peekLeft: "8:59 현관 · 9:12 급행",
            peekRight: "회사 9:48",
            stops: [
                .init(time: "지금", title: "지금", isNow: true, leg: .walk, minutes: 12),
                .init(time: "8:59", title: "현관", detail: "집 → 승강장 9분 · 여유 4분", leg: .walk, minutes: 13),
                .init(time: "9:12", title: "가양", detail: "9호선 급행 · 7정거장", nodeColor: gold, leg: .line(gold), minutes: 25),
                .init(time: "9:37", title: "신논현", detail: "환승 5분", nodeColor: gold, leg: .walk, minutes: 5),
                .init(time: "9:42", title: "신논현", detail: "신분당선 · 1정거장", nodeColor: red, leg: .line(red), minutes: 1),
                .init(time: "9:43", title: "강남", nodeColor: red, leg: .walk, minutes: 5),
                .init(time: "9:48", title: "회사", detail: "12분 일찍"),
            ],
            night: false,
            buttonTitle: "출발 준비")
    }

    static func lastTrainSample(minutes: Double = 47) -> Self {
        let green = Color(hex: "#00A84D"), gold = Color(hex: "#BDB092")
        return .init(
            meta: "집까지 가는 막차 · 홍대입구",
            unit: "분 뒤 일어나기",
            target: .now.addingTimeInterval(minutes * 60),
            window: 60 * 60,
            peekLeft: "23:10 일어나기 · 23:24 막차",
            peekRight: "주말이라 1시간 12분 일찍",
            stops: [
                .init(time: "지금", title: "지금", isNow: true, leg: .walk, minutes: 47),
                .init(time: "23:10", title: "일어나기", detail: "역까지 7분 · 여유 8분", nodeColor: .white, leg: .walk, minutes: 14),
                .init(time: "23:24", title: "홍대입구", detail: "2호선 막차 · 2정거장", nodeColor: green, leg: .line(green), minutes: 5),
                .init(time: "23:29", title: "당산", detail: "환승", nodeColor: green, leg: .walk, minutes: 9),
                .init(time: "23:38", title: "당산", detail: "9호선", nodeColor: gold, leg: .line(gold), minutes: 13),
                .init(time: "23:51", title: "가양", nodeColor: gold, leg: .walk, minutes: 9),
                .init(time: "0:00", title: "집", nodeColor: .white),
            ],
            night: true,
            buttonTitle: "일어나기 알림 받기")
    }
}
