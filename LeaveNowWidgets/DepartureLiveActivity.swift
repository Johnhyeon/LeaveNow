import ActivityKit
import SwiftUI
import WidgetKit

// 3안 규칙을 위젯에서도 쓴다 (위젯 확장은 앱의 Theme 를 못 보므로 필요한 색만 옮겨 둔다)
private enum W {
    static let card = Color(red: 0.07, green: 0.09, blue: 0.13)
    static let water = Color(red: 0.35, green: 0.65, blue: 1.0)        // #5AA7FF
    static let urgent = Color(red: 1.0, green: 0.64, blue: 0.36)       // #FFA25C
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded).monospacedDigit() }
}

struct DepartureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(W.card.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let s = context.state
            let range = s.windowStart...max(s.windowStart.addingTimeInterval(1), s.target)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(phaseTitle(s.phase))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    (Text("\(s.trainLabel) ") + Text(s.trainDeparture, style: .time))
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(timerInterval: Date.now...max(Date.now, s.target), countsDown: true)
                            .font(W.number(44))
                        WaterBar(range: range)
                    }
                }
            } compactLeading: {
                ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular)
                    .tint(W.water)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                Text(timerInterval: Date.now...max(Date.now, s.target), countsDown: true)
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                    .frame(width: 46)
            } minimal: {
                ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular)
                    .tint(W.water)
            }
        }
    }
}

/// 잠금화면과 펼친 아일랜드의 '물 막대'. 시스템이 알아서 줄여준다
private struct WaterBar: View {
    let range: ClosedRange<Date>
    var body: some View {
        ProgressView(timerInterval: range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
            .progressViewStyle(.linear)
            .tint(W.water)
            .scaleEffect(x: 1, y: 2.4, anchor: .center)
            .padding(.vertical, 4)
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<DepartureActivityAttributes>

    var body: some View {
        let s = context.state
        let range = s.windowStart...max(s.windowStart.addingTimeInterval(1), s.target)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(phaseTitle(s.phase))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                (Text("\(s.trainLabel) ") + Text(s.trainDeparture, style: .time))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text(timerInterval: Date.now...max(Date.now, s.target), countsDown: true)
                .font(W.number(56))
                .foregroundStyle(.white)
            WaterBar(range: range)
            Text("\(context.attributes.originName) → \(context.attributes.destinationName)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(16)
    }
}

private func phaseTitle(_ phase: DepartureActivityAttributes.ContentState.Phase) -> String {
    switch phase {
    case .beforeLeaving: return "현관까지"
    case .toPlatform: return "승강장까지"
    case .done: return "도착"
    }
}
