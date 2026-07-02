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
                    PavbotAudioActivityIcon(source: context.attributes.source, isPlaying: context.state.isPlaying, size: 30)
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
                    .tint(activityTint(context.attributes.source))

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
            .activitySystemActionForegroundColor(activityTint(context.attributes.source))
            .widgetURL(deepLinkURL(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PavbotAudioActivityIcon(source: context.attributes.source, isPlaying: context.state.isPlaying, size: 24)
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
                    PavbotNewsDynamicIslandBadge(source: context.attributes.source)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        ProgressView(value: progressValue(context.state))
                            .tint(activityTint(context.attributes.source))
                        Text(formatPlaybackTime(context.state.elapsed))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                PavbotAudioActivityIcon(source: context.attributes.source, isPlaying: context.state.isPlaying, size: 18)
            } compactTrailing: {
                PavbotNewsDynamicIslandBadge(source: context.attributes.source)
            } minimal: {
                PavbotAudioActivityIcon(source: context.attributes.source, isPlaying: context.state.isPlaying, size: 16)
            }
            .widgetURL(deepLinkURL(context.attributes))
        }
    }
}

private func deepLinkURL(_ attributes: PavbotAudioActivityAttributes) -> URL? {
    guard attributes.source == .mp3Podcast else { return nil }
    return URL(string: "pavbot://artifact?id=\(attributes.artifactID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? attributes.artifactID)")
}

private struct PavbotAudioActivityIcon: View {
    let source: PavbotAudioActivitySource
    let isPlaying: Bool
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: source.compactSystemImage)
                .font(.system(size: size, weight: .semibold))

            if source == .researchTTS {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: max(size * 0.48, 8), weight: .bold))
                    .foregroundStyle(Color(.systemBackground), activityTint(source))
                    .offset(x: size * 0.12, y: size * 0.12)
            } else if !isPlaying {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: max(size * 0.48, 8), weight: .bold))
                    .foregroundStyle(Color(.systemBackground), activityTint(source))
                    .offset(x: size * 0.12, y: size * 0.12)
            }
        }
        .foregroundStyle(activityTint(source))
        .frame(width: size + 6, height: size + 6)
        .accessibilityHidden(true)
    }
}

private struct PavbotNewsDynamicIslandBadge: View {
    let source: PavbotAudioActivitySource

    var body: some View {
        VStack(spacing: 0) {
            Text("PAV")
                .font(.system(size: 7, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(activityTint(source))

            Divider()
                .overlay(.white.opacity(0.65))

            Text("NEWS")
                .font(.system(size: 6, weight: .black, design: .rounded))
                .foregroundStyle(activityTint(source))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white)
        }
        .frame(width: 30, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(.white.opacity(0.72), lineWidth: 0.7)
        }
        .shadow(color: activityTint(source).opacity(0.24), radius: 2, x: 0, y: 1)
        .accessibilityLabel("Pavbot News, aktywne audio w tle")
    }
}

private func activityTint(_ source: PavbotAudioActivitySource) -> Color {
    switch source {
    case .mp3Podcast:
        .blue
    case .pulseDayTTS:
        .orange
    case .researchTTS:
        .teal
    }
}

private func progressValue(_ state: PavbotAudioActivityAttributes.ContentState) -> Double {
    guard state.duration > 0 else { return 0 }
    return min(max(state.elapsed / state.duration, 0), 1)
}

private func formatPlaybackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "--:--" }
    let totalSeconds = Int(seconds.rounded())
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}
