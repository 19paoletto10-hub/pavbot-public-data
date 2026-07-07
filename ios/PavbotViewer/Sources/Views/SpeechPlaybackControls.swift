import SwiftUI

struct PavbotSpeechRatePicker: View {
    let title: String
    @Binding var speechRate: MobileNewsSpeechRate
    @Environment(PavbotHaptics.self) private var haptics

    var body: some View {
        Picker(title, selection: $speechRate) {
            ForEach(MobileNewsSpeechRate.allCases) { rate in
                Text(rate.label)
                    .tag(rate)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
        .accessibilityLabel(title)
        .onChange(of: speechRate) { _, _ in
            haptics.play(.selection)
        }
    }
}

struct PavbotSpeechTimelineScrubber: View {
    let timeline: SpeechTimeline?
    let currentSegmentIndex: Int
    let estimatedElapsed: Double
    let estimatedDuration: Double
    let currentSegmentText: String?
    let seekToProgress: (Double) -> Void

    @State private var draftProgress: Double?

    private var displayedProgress: Double {
        if let draftProgress {
            return draftProgress
        }
        guard estimatedDuration > 0 else { return 0 }
        return min(max(estimatedElapsed / estimatedDuration, 0), 1)
    }

    @ViewBuilder
    var body: some View {
        if let timeline, !timeline.segments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Slider(
                    value: Binding(
                        get: { displayedProgress },
                        set: { draftProgress = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: handleEditingChanged
                )
                .accessibilityLabel("Oś czasu czytania")

                HStack {
                    Text(pavbotPlaybackTime(draftProgress.map { $0 * estimatedDuration } ?? estimatedElapsed))
                    Spacer()
                    Text(pavbotPlaybackTime(estimatedDuration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

                if let currentSegmentText {
                    Text("Fragment \(currentSegmentIndex + 1) z \(timeline.segments.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(currentSegmentText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func handleEditingChanged(_ editing: Bool) {
        guard !editing else { return }
        let progress = draftProgress ?? displayedProgress
        seekToProgress(progress)
        draftProgress = nil
    }
}
