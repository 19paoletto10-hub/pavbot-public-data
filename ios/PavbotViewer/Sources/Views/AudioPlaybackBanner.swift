import SwiftUI

enum AudioPlaybackBannerLayout {
    static let nativeTabBarHeight: CGFloat = 49
    static let phoneTabBarVisualGap: CGFloat = 9
    static let phoneLoweringAdjustment: CGFloat = 25
    static let splitBottomClearance: CGFloat = 20
    static let estimatedBannerHeight: CGFloat = 68
    static let buttonHitSize: CGFloat = 44
    static let alwaysOnTopZIndex: Double = 10_000

    static func bottomClearance(for layoutStyle: PavbotRootLayoutStyle, bottomSafeArea: CGFloat = 0) -> CGFloat {
        switch layoutStyle {
        case .tab:
            max(
                nativeTabBarHeight,
                bottomSafeArea + nativeTabBarHeight + phoneTabBarVisualGap - phoneLoweringAdjustment
            )
        case .split:
            max(splitBottomClearance, bottomSafeArea + 12)
        }
    }

    static func contentReserveHeight(for layoutStyle: PavbotRootLayoutStyle, bottomSafeArea: CGFloat = 0) -> CGFloat {
        estimatedBannerHeight + bottomClearance(for: layoutStyle, bottomSafeArea: bottomSafeArea)
    }
}

struct AudioPlaybackBannerSnapshot: Equatable {
    let source: PavbotAudioActivitySource
    let title: String
    let topic: String
    let progress: Double
    let isPlaying: Bool
    let playPauseSystemImage: String
    let sourceSystemImage: String
    let timeLabel: String
    let destination: PavbotAudioDestination?

    @MainActor
    init?(service: AudioPlaybackService) {
        guard let artifact = service.currentArtifact else { return nil }
        source = .mp3Podcast
        title = artifact.title
        topic = artifact.topic
        isPlaying = service.isPlaying
        playPauseSystemImage = service.isPlaying ? "pause.fill" : "play.fill"
        sourceSystemImage = source.compactSystemImage
        progress = Self.progress(currentTime: service.currentTime, duration: service.duration)
        timeLabel = Self.timeLabel(currentTime: service.currentTime, duration: service.duration)
        destination = nil
    }

    @MainActor
    init?(coordinator: PavbotAudioSessionCoordinator) {
        guard let snapshot = coordinator.currentSnapshot else { return nil }
        source = snapshot.source
        title = snapshot.title
        topic = snapshot.topic
        progress = snapshot.progress
        isPlaying = snapshot.isPlaying
        playPauseSystemImage = snapshot.playPauseSystemImage
        sourceSystemImage = snapshot.sourceSystemImage
        timeLabel = snapshot.timeLabel
        destination = snapshot.destination
    }

    private static func progress(currentTime: Double, duration: Double) -> Double {
        guard duration.isFinite, duration > 0, currentTime.isFinite else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    private static func timeLabel(currentTime: Double, duration: Double) -> String {
        guard duration.isFinite, duration > 0, currentTime.isFinite else { return "00:00" }
        return "\(format(currentTime)) / \(format(duration))"
    }

    private static func format(_ seconds: Double) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

struct AudioPlaybackBanner: View {
    @Environment(PavbotAudioSessionCoordinator.self) private var audioCoordinator
    @Environment(AppRouter.self) private var router
    @Environment(PavbotHaptics.self) private var haptics

    var body: some View {
        if let snapshot = AudioPlaybackBannerSnapshot(coordinator: audioCoordinator) {
            HStack(spacing: 12) {
                infoArea(for: snapshot)

                Button {
                    snapshot.isPlaying ? audioCoordinator.pauseActive() : audioCoordinator.resumeActive()
                    haptics.play(.lightImpact)
                } label: {
                    Image(systemName: snapshot.playPauseSystemImage)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: AudioPlaybackBannerLayout.buttonHitSize, height: AudioPlaybackBannerLayout.buttonHitSize)
                        .background(tint(for: snapshot.source), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(snapshot.isPlaying ? "Pauza audio" : "Odtwórz audio")
                .accessibilityIdentifier("audio.banner.playPause")

                Button {
                    audioCoordinator.stopActive()
                    haptics.play(.warning)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: AudioPlaybackBannerLayout.buttonHitSize, height: AudioPlaybackBannerLayout.buttonHitSize)
                        .background(Color(.secondarySystemBackground), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zamknij odtwarzanie audio")
                .accessibilityIdentifier("audio.banner.close")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .stroke(tint(for: snapshot.source).opacity(0.18), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 7)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("audio.banner")
        }
    }

    private func tint(for source: PavbotAudioActivitySource) -> Color {
        switch source {
        case .mp3Podcast:
            .purple
        case .pulseDayTTS:
            .orange
        case .researchTTS:
            .teal
        }
    }

    @ViewBuilder
    private func infoArea(for snapshot: AudioPlaybackBannerSnapshot) -> some View {
        if let destination = snapshot.destination {
            Button {
                router.openAudioDestination(destination)
                haptics.play(.selection)
            } label: {
                infoContent(for: snapshot)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Otwórz aktualnie czytany artykuł")
            .accessibilityIdentifier("audio.banner.openDetail")
        } else {
            infoContent(for: snapshot)
        }
    }

    private func infoContent(for snapshot: AudioPlaybackBannerSnapshot) -> some View {
        HStack(spacing: 12) {
            AudioPlaybackSourceIcon(source: snapshot.source, isPlaying: snapshot.isPlaying)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(snapshot.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(snapshot.timeLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Text(snapshot.topic)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: snapshot.progress)
                        .progressViewStyle(.linear)
                        .tint(tint(for: snapshot.source))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct AudioPlaybackSourceIcon: View {
    let source: PavbotAudioActivitySource
    let isPlaying: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: source.compactSystemImage)
                .font(.title2.weight(.semibold))

            if source == .researchTTS {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(.systemBackground), tint)
                    .offset(x: 4, y: 4)
            } else if !isPlaying {
                Image(systemName: "pause.circle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color(.systemBackground), tint)
                    .offset(x: 4, y: 4)
            }
        }
        .foregroundStyle(tint)
        .frame(width: 38, height: 38)
        .background(tint.opacity(0.12), in: Circle())
        .accessibilityHidden(true)
    }

    private var tint: Color {
        switch source {
        case .mp3Podcast:
            .purple
        case .pulseDayTTS:
            .orange
        case .researchTTS:
            .teal
        }
    }
}
