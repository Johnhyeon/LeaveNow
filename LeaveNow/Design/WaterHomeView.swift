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
        var details: SheetDetails? = nil
    }

    /// 시트를 채우는 정보. 미리보기처럼 없으면 경로 한 줄만 보인다
    struct SheetDetails {
        struct Item: Hashable { let symbol: String; let text: String }
        struct Option: Hashable { let left: String; let right: String; let warning: Bool }
        var compact: [Item] = []          // 접었을 때 한 줄: 알림 시각, 탈 칸
        var leaveTime: String             // "18:23"
        var leaveLabel: String            // "집에서 출발"
        var arriveLine: String            // "시청 19:12 도착 · 1분 일찍"
        var chips: [String] = []          // "환승 1회", "도어 투 도어 49분"
        var fastCar: (title: String, subtitle: String)? = nil
        var alternatives: [Option] = []   // 놓치면 다음 열차
        var alerts: [Item] = []           // 알림 시각
    }

    struct SheetAction: Identifiable {
        let id = UUID()
        let title: String
        var role: ButtonRole? = nil
        let action: () -> Void
    }

    /// 시각을 받아 그때의 내용을 만든다. 시트는 따로 떠 있는 화면이라 스스로 매초 다시 읽어야
    /// 다시 계산한 결과가 손대지 않아도 바로 보인다
    let makeContent: (Date) -> Content
    var onClose: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    var primaryAction: (() -> Void)? = nil
    var extraActions: [SheetAction] = []

    init(live makeContent: @escaping (Date) -> Content, onClose: (() -> Void)? = nil, onSettings: (() -> Void)? = nil,
         primaryAction: (() -> Void)? = nil, extraActions: [SheetAction] = []) {
        self.makeContent = makeContent
        self.onClose = onClose
        self.onSettings = onSettings
        self.primaryAction = primaryAction
        self.extraActions = extraActions
    }

    /// 미리보기처럼 내용이 고정일 때
    init(content: Content, onClose: (() -> Void)? = nil, onSettings: (() -> Void)? = nil,
         primaryAction: (() -> Void)? = nil, extraActions: [SheetAction] = []) {
        self.init(live: { _ in content }, onClose: onClose, onSettings: onSettings,
                  primaryAction: primaryAction, extraActions: extraActions)
    }

    @State private var showSheet = true
    // 개발용: -sheetLarge 로 실행하면 시트를 펼친 채로 시작
    @State private var detent: PresentationDetent = ProcessInfo.processInfo.arguments.contains("-sheetLarge") ? .large : .height(128)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let content = makeContent(context.date)
            let remaining = max(0, content.target.timeIntervalSince(context.date))
            let water = content.night ? Theme.nightWater
                : (remaining < Theme.urgentSeconds ? Theme.urgentWater : Theme.dayWater)
            WaterScene(level: remaining / content.window,
                       water: water,
                       paper: content.night ? Theme.nightPaper : Theme.paper,
                       dryInk: content.night ? .white : Theme.ink,
                       drySecondary: content.night ? Theme.nightMute : Theme.mute,
                       floor: detent == .large ? 0 : 150) { primary, secondary in
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
            TimelineView(.periodic(from: .now, by: 1)) { context in
                RouteSheet(content: makeContent(context.date), detent: detent,
                           primaryAction: primaryAction, extraActions: extraActions)
            }
            .presentationDetents([.height(128), .large], selection: $detent)
            .presentationBackgroundInteraction(.enabled(upThrough: .height(128)))
            .presentationCornerRadius(28)
            .presentationBackground(makeContent(.now).night ? Theme.nightSheet : Theme.sheet)
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

    private var ink: Color { content.night ? .white : Theme.ink }
    private var mute: Color { content.night ? Theme.nightMute : Theme.mute }
    private var card: Color { content.night ? Color.white.opacity(0.06) : Theme.card }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 접었을 때도 보이는 부분
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
            if let d = content.details, !d.compact.isEmpty, detent != .large {
                HStack(spacing: 14) {
                    ForEach(d.compact, id: \.self) { item in
                        Label(item.text, systemImage: item.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(mute)
                            .lineLimit(1)
                    }
                }
            }

            if detent == .large {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let d = content.details { summary(d) }
                        RouteMapView(stops: content.stops, night: content.night)
                            .foregroundStyle(ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(card, in: RoundedRectangle(cornerRadius: 20))
                        if let d = content.details { extras(d) }
                        buttons
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
    }

    @ViewBuilder
    private func summary(_ d: WaterHomeView.SheetDetails) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(d.leaveTime).font(Theme.number(40)).foregroundStyle(ink)
                Text(d.leaveLabel).font(.title3.weight(.heavy)).foregroundStyle(ink)
            }
            Text(d.arriveLine).font(.subheadline.weight(.semibold)).foregroundStyle(mute)
            if !d.chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(d.chips, id: \.self) { chip in
                        Text(chip)
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Color(.secondarySystemFill), in: Capsule())
                            .foregroundStyle(ink)
                    }
                }
                .padding(.top, 2)
            }
        }
        if let car = d.fastCar {
            HStack(spacing: 12) {
                Image(systemName: "tram.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.now)
                    .frame(width: 40, height: 40)
                    .background(Theme.now.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(car.title).font(.subheadline.weight(.bold)).foregroundStyle(ink)
                    Text(car.subtitle).font(.caption).foregroundStyle(mute)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private func extras(_ d: WaterHomeView.SheetDetails) -> some View {
        if !d.alternatives.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("이 열차를 놓치면").font(.caption.weight(.bold)).foregroundStyle(mute)
                ForEach(d.alternatives, id: \.self) { option in
                    HStack {
                        Text(option.left).font(.subheadline.weight(.semibold)).foregroundStyle(ink)
                        Spacer()
                        Text(option.right)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(option.warning ? Color.orange : mute)
                    }
                }
            }
            .padding(14)
            .background(card, in: RoundedRectangle(cornerRadius: 16))
        }
        if !d.alerts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("알림").font(.caption.weight(.bold)).foregroundStyle(mute)
                ForEach(d.alerts, id: \.self) { item in
                    Label(item.text, systemImage: item.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
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
            .foregroundStyle(content.night ? Theme.nightPaper : Theme.onInk)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            ForEach(extraActions) { action in
                Button(action.title, role: action.role, action: action.action)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .padding(.top, 4)
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
