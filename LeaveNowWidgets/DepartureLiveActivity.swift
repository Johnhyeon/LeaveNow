import ActivityKit
import SwiftUI
import WidgetKit

struct DepartureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.75))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let line = Color(hex: context.state.lineColorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.trainLabel, systemImage: "tram.fill")
                        .font(.caption)
                        .foregroundStyle(line)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.trainDeparture, style: .time)
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(phaseTitle(context.state.phase))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(timerInterval: Date.now...max(Date.now, context.state.target), countsDown: true)
                            .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle().fill(line).frame(width: 8, height: 8)
                    Text(context.state.phase == .beforeLeaving ? "현관" : "승강장")
                        .font(.caption2)
                }
            } compactTrailing: {
                Text(timerInterval: Date.now...max(Date.now, context.state.target), countsDown: true)
                    .monospacedDigit()
                    .font(.caption2.weight(.semibold))
                    .frame(width: 44)
            } minimal: {
                Text(timerInterval: Date.now...max(Date.now, context.state.target), countsDown: true, showsHours: false)
                    .monospacedDigit()
                    .font(.system(size: 9, weight: .semibold))
            }
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<DepartureActivityAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(context.attributes.originName) → \(context.attributes.destinationName)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("\(state.trainLabel) ") + Text(state.trainDeparture, style: .time)
            }
            .font(.caption)
            .foregroundStyle(.white)
            HStack(alignment: .firstTextBaseline) {
                Text(phaseTitle(state.phase))
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text(timerInterval: Date.now...max(Date.now, state.target), countsDown: true)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
            }
            ProgressView(timerInterval: Date.now...max(Date.now.addingTimeInterval(1), state.target), countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(Color(hex: state.lineColorHex))
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

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex.replacingOccurrences(of: "#", with: "")).scanHexInt64(&value)
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
