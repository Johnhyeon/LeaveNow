import SwiftUI

/// 횡단보도 신호 주기 측정: 빨간불 시작 → 초록불 시작 → 다시 빨간불 시작
struct SignalCycleView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("crosswalkRedSeconds") private var savedRed = 0.0
    @AppStorage("crosswalkGreenSeconds") private var savedGreen = 0.0

    @State private var redStart: Date?
    @State private var greenStart: Date?
    @State private var measuredRed: Double?
    @State private var measuredGreen: Double?

    private enum Step { case waitRed, waitGreen, waitRedAgain, done }

    private var step: Step {
        if measuredGreen != nil { return .done }
        if greenStart != nil { return .waitRedAgain }
        if redStart != nil { return .waitGreen }
        return .waitRed
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                content(now: context.date)
            }
            .navigationTitle("신호 주기 측정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private func content(now: Date) -> some View {
        VStack(spacing: 24) {
            if savedRed > 0 || savedGreen > 0 {
                Text("저장된 값 · 빨간불 \(Fmt.duration(savedRed)) / 초록불 \(Fmt.duration(savedGreen))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Group {
                switch step {
                case .waitRed:
                    instruction("횡단보도 앞에서 기다리다가", "빨간불이 켜지는 순간 누르세요")
                case .waitGreen:
                    instruction("빨간불 진행 중 · \(Fmt.stopwatch(now.timeIntervalSince(redStart ?? now)))",
                                "초록불이 켜지는 순간 누르세요")
                case .waitRedAgain:
                    instruction("초록불 진행 중 · \(Fmt.stopwatch(now.timeIntervalSince(greenStart ?? now)))",
                                "다시 빨간불이 켜지는 순간 누르세요")
                case .done:
                    VStack(spacing: 8) {
                        Text("측정 결과").font(.headline)
                        Text("빨간불 \(Fmt.duration(measuredRed ?? 0))")
                        Text("초록불 \(Fmt.duration(measuredGreen ?? 0))")
                        Text("한 주기 \(Fmt.duration((measuredRed ?? 0) + (measuredGreen ?? 0)))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.title3)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Button {
                tap(at: now)
            } label: {
                Text(buttonTitle)
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(step == .done ? .green : (step == .waitGreen ? .red : .accentColor))
            .controlSize(.large)

            if step != .waitRed {
                Button("처음부터 다시") { reset() }
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
    }

    private var buttonTitle: String {
        switch step {
        case .waitRed: return "빨간불 켜짐"
        case .waitGreen: return "초록불 켜짐"
        case .waitRedAgain: return "다시 빨간불 켜짐"
        case .done: return "이 값으로 저장"
        }
    }

    private func instruction(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline).monospacedDigit()
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func tap(at now: Date) {
        switch step {
        case .waitRed:
            redStart = now
        case .waitGreen:
            greenStart = now
            measuredRed = now.timeIntervalSince(redStart ?? now)
        case .waitRedAgain:
            measuredGreen = now.timeIntervalSince(greenStart ?? now)
        case .done:
            savedRed = measuredRed ?? 0
            savedGreen = measuredGreen ?? 0
            dismiss()
        }
    }

    private func reset() {
        redStart = nil
        greenStart = nil
        measuredRed = nil
        measuredGreen = nil
    }
}
