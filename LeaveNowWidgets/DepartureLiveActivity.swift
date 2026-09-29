import ActivityKit
import SwiftUI
import WidgetKit

// 3안 규칙을 위젯에서도 쓴다 (위젯 확장은 앱의 Theme 를 못 보므로 필요한 색만 옮겨 둔다)
private enum W {
    static let card = Color(red: 0.07, green: 0.09, blue: 0.13)
    static let water = Color(red: 0.35, green: 0.65, blue: 1.0)        // #5AA7FF
    static func number(_ size: CGFloat) -> Font { .system(size: size, weight: .black, design: .rounded).monospacedDigit() }
    /// 앱과 같은 "9:08" 모양
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "H:mm"
        return f.string(from: date)
    }
}

/// 지금 무엇까지 세는지. 열차가 떠나면 시스템이 isStale 을 켜 주므로 앱 없이도 바뀐다
private struct Stage {
    let title: String      // "9:12 급행까지" / "강남 도착까지"
    let detail: String     // "승강장 목표 9:08" / "9:12 급행 타는 중"
    let range: ClosedRange<Date>

    init(_ context: ActivityViewContext<DepartureActivityAttributes>) {
        let s = context.state
        if context.isStale || s.trainDeparture <= .now {
            title = "\(context.attributes.destinationName) 도착까지"
            detail = "\(s.trainLabel) 타는 중"
            range = s.trainDeparture...max(s.trainDeparture.addingTimeInterval(60), s.arrival)
        } else {
            title = "\(s.trainLabel)까지"
            detail = "승강장 목표 \(W.time(s.platformBy))"
            range = s.windowStart...max(s.windowStart.addingTimeInterval(60), s.trainDeparture)
        }
    }

    /// 남은 시간 글자는 지금부터 끝까지
    var countdown: ClosedRange<Date> { Date.now...max(Date.now, range.upperBound) }
}

struct DepartureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(W.card.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let stage = Stage(context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(stage.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(stage.detail)
                        .font(.caption.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(timerInterval: stage.countdown, countsDown: true)
                            .font(W.number(44))
                        WaterBar(range: stage.range)
                    }
                }
            } compactLeading: {
                ProgressView(timerInterval: stage.range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular)
                    .tint(W.water)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                Text(timerInterval: stage.countdown, countsDown: true)
                    .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 62)
            } minimal: {
                ProgressView(timerInterval: stage.range, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
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
        let stage = Stage(context)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(stage.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text(stage.detail)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text(timerInterval: stage.countdown, countsDown: true)
                .font(W.number(56))
                .foregroundStyle(.white)
            WaterBar(range: stage.range)
            Text("\(context.attributes.originName) → \(context.attributes.destinationName) · 도착 \(W.time(context.state.arrival))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(16)
    }
}
