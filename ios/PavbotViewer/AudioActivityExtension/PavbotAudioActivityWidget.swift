import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PavbotAudioActivityBundle: WidgetBundle {
    var body: some Widget {
        PavbotAudioActivityWidget()
    }
}

struct PavbotAudioActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PavbotAudioActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: context.state.isPlaying ? "waveform.circle.fill" : "pause.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pavbot")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(context.state.title)
                            .font(.headline)
                            .lineLimit(2)
                    }
                }

                ProgressView(value: progressValue(context.state))
                    .tint(.blue)

                HStack {
                    Text(formatPlaybackTime(context.state.elapsed))
                    Spacer()
                    Text(context.attributes.topic)
                    Spacer()
                    Text(context.state.duration > 0 ? formatPlaybackTime(context.state.duration) : "--:--")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground))
            .activitySystemActionForegroundColor(.blue)
            .widgetURL(deepLinkURL(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isPlaying ? "waveform.circle.fill" : "pause.circle.fill")
                        .foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.attributes.topic)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(formatPlaybackTime(context.state.elapsed))
                        .font(.caption.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: progressValue(context.state))
                        .tint(.blue)
                }
            } compactLeading: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text(compactProgress(context.state))
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "waveform")
                    .foregroundStyle(.blue)
            }
            .widgetURL(deepLinkURL(context.attributes))
        }
    }
}

private func deepLinkURL(_ attributes: PavbotAudioActivityAttributes) -> URL? {
    URL(string: "pavbot://artifact?id=\(attributes.artifactID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? attributes.artifactID)")
}

private func progressValue(_ state: PavbotAudioActivityAttributes.ContentState) -> Double {
    guard state.duration > 0 else { return 0 }
    return min(max(state.elapsed / state.duration, 0), 1)
}

private func compactProgress(_ state: PavbotAudioActivityAttributes.ContentState) -> String {
    guard state.duration > 0 else { return "ON" }
    return "\(Int(progressValue(state) * 100))%"
}

private func formatPlaybackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let totalSeconds = Int(seconds.rounded())
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}
