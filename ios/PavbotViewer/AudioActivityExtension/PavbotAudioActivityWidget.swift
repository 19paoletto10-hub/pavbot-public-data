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
            PavbotNotificationAudioBanner(source: context.attributes.source, topic: context.attributes.topic, state: context.state)
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
                    PavbotDynamicIslandTrailingStatus(source: context.attributes.source, state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        ProgressView(value: progressValue(context.state))
                            .tint(activityTint(context.attributes.source))
                        PavbotRemainingPlaybackLabel(state: context.state)
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

private struct PavbotNotificationAudioBanner: View {
    let source: PavbotAudioActivitySource
    let topic: String
    let state: PavbotAudioActivityAttributes.ContentState

    var body: some View {
        let tabLabel = state.tabLabel ?? topic

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                statusIcon

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.isFinished ? "Odsłuchane" : "Pavbot")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(state.title)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)

                    Text(tabLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !state.isFinished {
                    PavbotRemainingPlaybackLabel(state: state)
                }
            }

            if state.isFinished {
                completionNotes
            } else {
                playbackProgress(topic: tabLabel)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if state.isFinished {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
                .accessibilityLabel("Audio zakonczone")
        } else {
            PavbotAudioActivityIcon(source: source, isPlaying: state.isPlaying, size: 30)
        }
    }

    @ViewBuilder
    private var completionNotes: some View {
        if state.keyNotes.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(state.keyNotes.prefix(3), id: \.self) { note in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Circle()
                            .fill(.secondary.opacity(0.45))
                            .frame(width: 4, height: 4)

                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 46)
        }
    }

    private func playbackProgress(topic: String) -> some View {
        VStack(spacing: 7) {
            ProgressView(value: progressValue(state))
                .tint(activityTint(source))

            HStack {
                Text(formatPlaybackTime(state.elapsed))
                Spacer()
                Text(topic)
                    .lineLimit(1)
                Spacer()
                Text(state.duration > 0 ? formatPlaybackTime(state.duration) : "--:--")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
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

private struct PavbotDynamicIslandTrailingStatus: View {
    let source: PavbotAudioActivitySource
    let state: PavbotAudioActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            PavbotRemainingPlaybackLabel(state: state)
            PavbotNewsDynamicIslandBadge(source: source)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct PavbotRemainingPlaybackLabel: View {
    let state: PavbotAudioActivityAttributes.ContentState

    var body: some View {
        Text(state.remainingPlaybackLabel)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .accessibilityLabel("Do końca audio \(state.remainingPlaybackLabel)")
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
